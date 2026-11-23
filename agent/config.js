// ARUNIKA agent config. All addresses verified on-chain 23 Nov 2026 — see NETWORK.md.
// Never edit an address here without re-verifying it on the explorer first.
const NETWORKS = {
  // HSK Chain testnet — full HSKSwap deployment exists here, but NO WETH/WBTC
  // pools: only USDT/WHSK (fee 500) + test tokens. USDT is 18 decimals here.
  133: {
    name: "hsk-testnet",
    rpc: "https://testnet.hsk.xyz",
    explorer: "https://testnet-explorer.hskchain.net",
    subgraph: "https://graphnode-testnet.hashkeychain.net/subgraphs/name/uniswap-v3/hsk-test",
    factory: "0x2dC2c21D1049F786C535bF9d45F999dB5474f3A0",
    router: "0xa6914E66690c6794244B5f66a09eAEbf66254237",
    quoter: "0x73820d9eE5Bf1BfcD429580320FC7A374E8fa1cC",
    nfpm: "0x73dEc6bfa6751509b08480bd97f54b874E3b20e8",
    multicall: "0x47F625Ec29637445AA1570d7008Cf78692CdA096",
    whsk: "0xca8aaceec5db1e91b9ed3a344ba026c4a2b3ebf6",
    usdt: "0x98b6173a8b7dfc52ce8bc88f1184a918a1ccaa4f",
    usdtDecimals: 18,
    // USDT/WHSK pool, fee 500
    pools: { "WHSK": { token: "0xca8aaceec5db1e91b9ed3a344ba026c4a2b3ebf6", fee: 500, pool: "0xff2b7e501c870980bf5641b4a70d0f9fb0f6f6ab" } },
  },
  // HSK Chain mainnet — DEPLOY ONLY WITH EXPLICIT USER APPROVAL (funding + capital).
  177: {
    name: "hsk-mainnet",
    rpc: "https://mainnet.hsk.xyz",
    explorer: "https://explorer.hsk.xyz",
    subgraph: "https://graphnode.hashkeychain.net/subgraphs/name/hskswap",
    factory: "0x972cA9D1662F5e029cD18327D29026532E84c742",
    router: "0x2c16f75b95Cf1390c328aB70e2CEE7f4b80bD8F3",
    quoter: "0x603f70466fDdbE3F238220B9a74FFF419a2BbFDD",
    nfpm: "0xDF0A9b833Db0E4CeEa103A4408f3B68e7FC0cad5",
    multicall: "0x7D0CBa43EbDD69ec2CE3B5AeAD3b0FbC796c565B",
    whsk: "0xB210D2120d57b758EE163cFfb43e73728c471Cf1",
    usdt: "0xf1b50ed67a9e2cc94ad3c477779e2d4cbfff9029",
    usdtDecimals: 6,
    pools: {
      "WHSK": { token: "0xB210D2120d57b758EE163cFfb43e73728c471Cf1", fee: 3000, pool: "0x4ff515761864e7838b0adb8b5b2b8b7a068905dc" },
      "WETH": { token: "0xefd4bc9afd210517803f293ababd701caeecdfd0", fee: 3000, pool: "0xb92b79ed6b370d5cfee2e14b1d0983c258304c16" },
      "WBTC": { token: "0x6119ca49a79f5825c8b345f8d7ac36b272565b14", fee: 3000, pool: "0xd9ea2ce468957ba49ccc38c4758ed6ecd561449a" },
    },
  },
};

const DEFAULTS = {
  chainId: 133,
  mode: "paper", // "paper" | "live" — live only when a funded vault is configured
  pollSeconds: 30,
  zEntry: 1.5, // |z-score| above this triggers a trade
  zExit: 0.3, // |z-score| below this closes/ignores
  window: 40, // rolling TWAP window (samples)
  tradeSizeUsdt: 1, // USDT per trade (testnet default: tiny)
  maxSlippageBps: 100, // 1%
  maxDailyLossUsdt: 5,
  stopLossBps: 500, // 5%
  assets: ["WHSK"], // testnet: only WHSK exists. Mainnet adds WETH, WBTC.
};

function loadConfig() {
  const cfg = { ...DEFAULTS };
  try {
    const fs = require("fs");
    const path = require("path");
    const overridePath = path.join(__dirname, "config.json");
    if (fs.existsSync(overridePath)) {
      const o = JSON.parse(fs.readFileSync(overridePath, "utf8"));
      Object.assign(cfg, o);
    }
  } catch (e) {
    console.error("config.json unreadable, using defaults:", e.message);
  }
  // Env overrides (12-factor style, no secrets in files)
  if (process.env.ARUNIKA_CHAIN) cfg.chainId = Number(process.env.ARUNIKA_CHAIN);
  if (process.env.ARUNIKA_MODE) cfg.mode = process.env.ARUNIKA_MODE;
  if (process.env.ARUNIKA_VAULT) cfg.vault = process.env.ARUNIKA_VAULT;
  if (process.env.ARUNIKA_POLL_SECONDS) cfg.pollSeconds = Number(process.env.ARUNIKA_POLL_SECONDS);
  if (process.env.ARUNIKA_TRADE_SIZE_USDT) cfg.tradeSizeUsdt = Number(process.env.ARUNIKA_TRADE_SIZE_USDT);
  return cfg;
}

module.exports = { NETWORKS, DEFAULTS, loadConfig };
