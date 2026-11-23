# ARUNIKA — autonomous trading agent on HSKSwap

🌅 *Arunika (Sanskrit/Indonesian: morning sun)* — an autonomous trading agent
that trades WHSK/USDT (plus WETH/USDT and WBTC/USDT on mainnet) on **HSKSwap**,
with every trade enforced by **on-chain risk guards**: the agent literally
cannot break its own rules, even if its signal logic is wrong.

Built for **Track 1: AI Agent Trading** — HSK Chain Horizon Hackathon, Seoul
(DoraHacks). Submission deadline: **3 Dec 2026, 11:00 WIB**.

## Architecture

```
┌────────────────────────────┐      ┌──────────────────────────────┐
│  ArunikaVault.sol (on-chain)│◄─────│  agent/ (Node.js + ethers v6)│
│  holds USDT + WHSK          │ swap │  QuoterV2 + subgraph prices  │
│  guards: agent-only, size,  │      │  mean-reversion z-score signal│
│  cooldown, stop-loss, daily │      │  simulate first, then execute│
│  loss cap, allowlist, pause │      │  decision log → decisions.jsonl
└────────────────────────────┘      └──────────────┬───────────────┘
        ▲ reads balances / P&L                     │ config.json
┌───────┴────────────────────┐      (position size, frequency,
│  console/ (web UI)          │       risk appetite, assets)
│  chat + live positions/P&L  │
│  + controls                 │
└────────────────────────────┘
```

## Quickstart

### 1. Contract (Foundry — tests prove the guards)

```bash
forge test        # 12 tests: oversize reverts, non-agent reverts, pause,
                  # allowlist, cooldown, stop-loss, daily-loss cap, slippage
```

### 2. Agent (paper mode = default, no funds move)

```bash
cd agent && npm install
node index.js     # paper mode on HSK testnet (133), WHSK/USDT
```

Live mode only with a funded vault:

```bash
ARUNIKA_MODE=live ARUNIKA_VAULT=0x... AGENT_KEY_FILE=~/.arunika/agent.key node index.js
```

The agent key is a **fresh project-only keypair** (never a personal seed).
It is stored as a file with mode 600 and never committed.

### 3. Console

```bash
cd console && cp ../agent/decisions.jsonl .   # decision log for the UI
python3 -m http.server 8080                    # open http://localhost:8080
```

Ask the chat: `positions?` · `pnl?` · `why did you buy?` · `status?`
Controls write `agent/config.json`, which the agent applies on its next cycle.

## How the signal works

Mean-reversion on the pool price: z-score of the current QuoterV2 price vs a
rolling TWAP (mean ± stddev of the last 40 samples). `|z| ≥ 1.5` → trade
(buy below TWAP, sell above); every trade is simulated first (quote +
vault `staticCall`) and executed only if the on-chain guards pass. Stop-loss
and the daily-loss cap are enforced **in the vault**, from on-chain quoter
prices — not from the agent's word.

## Verified addresses

See [`NETWORK.md`](NETWORK.md) — every router/quoter/factory/token address
was verified on-chain (code, `factory()`, `getPool()`, live quotes) on
23 Nov 2026. Mainnet and testnet are **different deployments**; the mainnet
addresses have no code on testnet. WETH/WBTC pools exist on mainnet only.

## Deployments

See [`DEPLOYMENTS.md`](DEPLOYMENTS.md) for the testnet vault address and tx
hashes. **Mainnet deploy is intentionally NOT done here** — the rules require
a mainnet deployment for demo eligibility, but that step needs real HSK for
gas + real capital and explicit user approval. It is a separate, gated step.

## Repo layout

```
contracts/ArunikaVault.sol   vault + on-chain guards
contracts/test/              forge tests (12) + mock HSKSwap contracts
agent/                       Node.js agent (config, price, signal, index)
console/                     chat + positions/P&L + controls (static web UI)
NETWORK.md                   verified addresses + how they were verified
DEPLOYMENTS.md               testnet deploy record (tx hashes, explorer links)
```

## License

MIT — see [`LICENSE`](LICENSE).
