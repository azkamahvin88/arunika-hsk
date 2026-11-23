# ARUNIKA — Deployments

## HSK Chain testnet (133) — DEPLOYED + TRADE-TESTED ✅ (23 Nov 2026 ~20:20 WIB)

**Status: vault live di testnet, 2 trade test sukses (SELL + BUY), agent paper + live terverifikasi.**

- Project agent key (fresh keypair, created 23 Nov 2026, file mode 600,
  NOT in this repo): `0xEAA2eA592514988305739c0bC6F2c56834615133`
- Faucet: user klaim via browser (hskchain.net/faucet). Saldo terverifikasi
  sebelum deploy: **0.1 tHSK** (nonce 0). Sisa setelah semua tx: ~0.0472 tHSK.

| Item | Value |
|---|---|
| Vault contract | `0x642b7BB5D02e0a182BbD301bcDE8F8235EBA5b93` |
| Deploy tx | `0x49fa72679d2790c226a673264ddf6b4197c6dea9a16f92227512e81e93514ed2` |
| Agent address | `0xEAA2eA592514988305739c0bC6F2c56834615133` |
| Explorer | https://testnet-explorer.hskchain.net/address/0x642b7BB5D02e0a182BbD301bcDE8F8235EBA5b93 |

### Config txs (semua status 1)

| Call | Tx |
|---|---|
| setTokenConfig USDT (allowed, 18 dec, max 10 USDT, fee 500) | `0x1c27c4013798dcba6b910df2b1936aee98ea4028a57caaeb1cb3235bf19540bd` |
| setTokenConfig WHSK (allowed, 18 dec, max 1 WHSK, fee 500) | `0xb0725e2863baad5d072d3c05ae4f9915e012fb92163a02ccbb1af20712ca3b81` |
| setCooldown(60) | `0x821a4361016aa195f28c9a432e58139b339d73141c81a53914e706052a0731bb` |
| setMaxDailyLoss(5 USDT) | `0x38d524b5c60c99913d0ed6a54fb5dde72142323e04702d38d2b7792a9fddadf0` |
| setStopLossBps(500) | `0xa249dfc3bad3e7df3aea3d41c18f2d1c25a8a44d4ac9797af772302256e93184` |

### Funding

- Wrap 0.05 tHSK → WHSK: `0x31573eaf02d17e03f6f2148bca5e72efacebe4e3b013c570460a8c56bd12e3f6`
- Transfer 0.05 WHSK ke vault: `0xc5e698ef483376aedf9dead2be7a991120b432bc7b7e0898ab8c6c2d17e2c08d`
- Catatan: test USDT (SimpleERC20, tanpa fungsi mint publik) tidak bisa
  di-mint — USDT pertama vault didapat dari trade SELL di bawah.

### Trade tests (via vault executeTrade, semua guard lolos)

| # | Arah | Size | Hasil | Tx |
|---|---|---|---|---|
| 1 | SELL WHSK → USDT | 0.01 WHSK | keluar 0.78195 USDT (quote 0.78039, minOut 0.77258) | `0x048bb7af98f8318a5e1d5e7ad862ddb4d1ed16fa41ee750b003acf600f819dd0` |
| 2 | BUY USDT → WHSK | 0.5 USDT | masuk 0.0063879 WHSK; posisi terbuka, entry ~$78.27/WHSK, dailyLoss 0 | `0xfb2be1e7146e70317aa46a16569c0690d198e4a0c7989f6b254c43c5fc7237ae` |

Simulasi `staticCall` dijalankan sebelum tiap trade (keduanya lolos).
Cooldown 60 detik dipatuhi antar trade.

### Keadaan akhir vault (terverifikasi on-chain)

- WHSK: 0.046387902131863762 · USDT: 0.281952778704907602
- Posisi WHSK: balance 0.0063879 WHSK, cost 0.5 USDT, entry ~$78.27, open=true
- dailyLossUsd18: 0 · lastTradeAt: sesuai trade 2

### Agent

- Paper mode: 3 tick, harga live $78.0385/WHSK, z=0, HOLD (pool statis,
  warming up) — `decisions.jsonl`.
- Live mode: 2 tick, vault agent check + paused check lolos, HOLD
  ($78.0374/WHSK). Live mode hanya trade saat sinyal z-score trigger;
  pool testnet statis (tidak ada trader lain) sehingga sinyal tetap HOLD
  sampai ada pergerakan harga — trade test dilakukan manual via
  `executeTrade` sebagai gantinya (terbukti di atas).

## HSK Chain mainnet (177) — NOT DEPLOYED (gated)

Mainnet deployment is required by the hackathon rules for demo eligibility
and prize claims, but it needs real HSK (gas) + real trading capital and
**explicit user approval**. No mainnet transaction has been sent and no real
funds have moved. This is a separate step after the user approves funding.
