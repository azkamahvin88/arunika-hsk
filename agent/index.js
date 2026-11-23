// ARUNIKA agent — polls HSKSwap prices, computes a mean-reversion signal,
// simulates every trade, then executes through ArunikaVault (live mode only).
// Paper mode is the default: it logs decisions without sending transactions.
//
// Usage:
//   node index.js                    # paper mode, testnet 133, WHSK/USDT
//   ARUNIKA_MODE=live ARUNIKA_VAULT=0x... AGENT_KEY_FILE=~/.arunika/agent.key node index.js
//
// The agent key NEVER goes in this repo. Pass it via AGENT_KEY_FILE (mode 600)
// or the ARUNIKA_AGENT_KEY env var (prefer the file).
const fs = require("fs");
const path = require("path");
const { ethers } = require("ethers");
const { NETWORKS, loadConfig } = require("./config");
const { quoteUsdtPerToken, quoteTokenOut, subgraphPoolPrice, ERC20_ABI } = require("./price");
const { Signal } = require("./signal");

const VAULT_ABI = [
  "function executeTrade((address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOutMinimum, uint24 fee, uint160 sqrtPriceLimitX96, uint256 signalId) p) external returns (uint256)",
  "function priceOf(address token) external returns (uint256)",
  "function getPosition(address token) external view returns (uint256 balance, uint256 costUsd18, uint256 entryPriceUsd18, bool open)",
  "function dailyLossUsd18() external view returns (uint256)",
  "function paused() external view returns (bool)",
  "function agent() external view returns (address)",
];

const LOG_FILE = path.join(__dirname, "decisions.jsonl");
let signalCounter = 0;

function logDecision(entry) {
  const line = JSON.stringify({ ts: new Date().toISOString(), ...entry });
  fs.appendFileSync(LOG_FILE, line + "\n");
  console.log(line);
}

async function main() {
  const cfg = loadConfig();
  const net = NETWORKS[cfg.chainId];
  if (!net) throw new Error(`unknown chain ${cfg.chainId}`);
  const provider = new ethers.JsonRpcProvider(net.rpc);
  const chainId = Number((await provider.getNetwork()).chainId);
  if (chainId !== cfg.chainId) throw new Error(`RPC chain ${chainId} != configured ${cfg.chainId}`);

  let wallet = null;
  let vault = null;
  if (cfg.mode === "live") {
    if (!cfg.vault) throw new Error("live mode needs ARUNIKA_VAULT");
    const keyFile = process.env.AGENT_KEY_FILE;
    const key = keyFile ? fs.readFileSync(keyFile, "utf8").trim() : process.env.ARUNIKA_AGENT_KEY;
    if (!key) throw new Error("live mode needs AGENT_KEY_FILE or ARUNIKA_AGENT_KEY");
    wallet = new ethers.Wallet(key, provider);
    vault = new ethers.Contract(cfg.vault, VAULT_ABI, wallet);
    const vaultAgent = await vault.agent();
    if (vaultAgent.toLowerCase() !== wallet.address.toLowerCase()) {
      throw new Error(`vault agent is ${vaultAgent}, this key is ${wallet.address} — refusing to trade`);
    }
    if (await vault.paused()) throw new Error("vault is paused — refusing to trade");
    console.log(`LIVE mode: vault=${cfg.vault} agent=${wallet.address}`);
  } else {
    console.log(`PAPER mode: no transactions will be sent (chain ${cfg.chainId} ${net.name})`);
  }

  const signals = {};
  for (const asset of cfg.assets) signals[asset] = new Signal(cfg.window);

  console.log(`Arunika agent started. Poll every ${cfg.pollSeconds}s. Assets: ${cfg.assets.join(", ")}. zEntry=${cfg.zEntry}.`);
  // eslint-disable-next-line no-constant-condition
  while (true) {
    try {
      await tick(cfg, net, provider, wallet, vault, signals);
    } catch (e) {
      logDecision({ kind: "error", error: String(e?.message ?? e).slice(0, 500) });
    }
    await new Promise((r) => setTimeout(r, cfg.pollSeconds * 1000));
  }
}

async function tick(cfg, net, provider, wallet, vault, signals) {
  for (const asset of cfg.assets) {
    const pool = net.pools[asset];
    if (!pool) {
      logDecision({ kind: "skip", asset, reason: `no ${asset} pool on chain ${cfg.chainId}` });
      continue;
    }
    const tokenDecimals = asset === "WHSK" ? 18 : asset === "WBTC" ? 8 : 18;
    const price = await quoteUsdtPerToken(provider, net, pool.token, tokenDecimals);
    const sig = signals[asset];
    sig.push(price);
    const ev = sig.evaluate(price, cfg);
    signalCounter += 1;

    // Cross-check with the subgraph (stale-data guard)
    let sub = null;
    try {
      sub = await subgraphPoolPrice(net, pool.pool);
    } catch { /* subgraph is advisory only */ }

    const entry = {
      kind: "signal", signalId: signalCounter, asset, chainId: cfg.chainId,
      priceUsd: price, z: ev.z ?? null, action: ev.action, reason: ev.reason,
      subgraphTvlUsd: sub?.totalValueLockedUSD ?? null, mode: cfg.mode,
    };

    if (ev.action === "HOLD") {
      logDecision(entry);
      continue;
    }

    // --- Simulate before anything else ---
    const usdtAmount = BigInt(Math.round(cfg.tradeSizeUsdt * 10 ** net.usdtDecimals));
    const buying = ev.action === "BUY";
    const tokenIn = buying ? net.usdt : pool.token;
    const tokenOut = buying ? pool.token : net.usdt;
    const quotedOut = await quoteTokenOut(provider, net, tokenIn, tokenOut, usdtAmount, pool.fee);
    const minOut = (quotedOut * BigInt(10000 - cfg.maxSlippageBps)) / 10000n;
    entry.quoteOut = quotedOut.toString();
    entry.minOut = minOut.toString();
    entry.tradeSizeUsdt = cfg.tradeSizeUsdt;

    if (cfg.mode !== "live") {
      entry.executed = false;
      entry.note = "paper mode — simulated only, no tx sent";
      logDecision(entry);
      continue;
    }

    // Live: static-call the vault first (guard simulation), then send.
    const params = {
      tokenIn, tokenOut,
      amountIn: buying ? usdtAmount : 0n, // sells size the token side below
      amountOutMinimum: minOut,
      fee: pool.fee,
      sqrtPriceLimitX96: 0,
      signalId: signalCounter,
    };
    if (!buying) {
      // SELL: size by current vault position (sell up to the USDT-equivalent size)
      const pos = await vault.getPosition(pool.token);
      const sellAmount = pos.balance / 4n; // trim 25% of the position per signal
      if (sellAmount === 0n) {
        entry.executed = false;
        entry.note = "no position to sell";
        logDecision(entry);
        continue;
      }
      params.amountIn = sellAmount;
      const q = await quoteTokenOut(provider, net, tokenIn, tokenOut, sellAmount, pool.fee);
      params.amountOutMinimum = (q * BigInt(10000 - cfg.maxSlippageBps)) / 10000n;
      entry.quoteOut = q.toString();
      entry.minOut = params.amountOutMinimum.toString();
    }
    try {
      await vault.executeTrade.staticCall(params);
    } catch (e) {
      entry.executed = false;
      entry.note = `vault simulation rejected: ${String(e?.message ?? e).slice(0, 300)}`;
      logDecision(entry);
      continue;
    }
    const tx = await vault.executeTrade(params);
    entry.executed = true;
    entry.txHash = tx.hash;
    entry.explorer = `${net.explorer}/tx/${tx.hash}`;
    logDecision(entry);
    const receipt = await tx.wait();
    logDecision({ kind: "receipt", signalId: signalCounter, txHash: tx.hash, status: receipt.status, blockNumber: receipt.blockNumber });
  }
}

main().catch((e) => {
  console.error("fatal:", e);
  process.exit(1);
});
