# ARUNIKA — Deployments

## HSK Chain testnet (133) — PENDING FAUCET

**Status: vault NOT yet deployed — blocked on testnet HSK for gas.**

- Project agent key (fresh keypair, created 23 Nov 2026, file mode 600,
  NOT in this repo): `0xEAA2eA592514988305739c0bC6F2c56834615133`
- Faucet https://hsk.xyz/faucet gives 1 tHSK per address per 24h, but it
  requires a Google reCAPTCHA + a browser click — it cannot be claimed from
  this VM (no live-browser/captcha path available to the builder).
- **To unblock:** open https://hsk.xyz/faucet in a browser, paste
  `0xEAA2eA592514988305739c0bC6F2c56834615133`, solve the captcha, click
  "Send Me 1 HSK". Then re-run the deploy steps below.
- Thirdweb universal faucet (0.01 tHSK/claim) was noted as an alternative
  but also needs a browser session.

### Deploy steps (once the agent address holds tHSK)

```bash
export PATH="$HOME/.foundry/bin:$PATH"
export AGENT_KEY_FILE=~/workspace/hsk-chain-hackathon/arunika-keys/agent.key
# 1. deploy (forge script or cast send --create with the compiled bytecode)
# 2. configure: setTokenConfig USDT + WHSK, setCooldown, setMaxDailyLoss, setStopLossBps
# 3. fund: wrap tHSK -> WHSK, transfer WHSK + test USDT to the vault
# 4. run agent paper mode, then live mode for 1-2 small test trades
```

| Item | Value |
|---|---|
| Vault contract | _(pending)_ |
| Deploy tx | _(pending)_ |
| Agent address | `0xEAA2eA592514988305739c0bC6F2c56834615133` |
| Test trade txs | _(pending)_ |

## HSK Chain mainnet (177) — NOT DEPLOYED (gated)

Mainnet deployment is required by the hackathon rules for demo eligibility
and prize claims, but it needs real HSK (gas) + real trading capital and
**explicit user approval**. No mainnet transaction has been sent and no real
funds have moved. This is a separate step after the user approves funding.
