# ARUNIKA — Network Addresses (VERIFIED)

All addresses below were verified on-chain on **23 Nov 2026** by the builder
(`eth_getCode` + `factory()`/`WETH9()`/`getPool()` calls + QuoterV2 struct
quotes + subgraph pool listings). Do NOT trust any address that is not in
this table. Anything marked UNVERIFIED is not used by the code.

Method: `eth_getCode` length, `factory()` on router/quoter, `getPool()` on the
factory returning the exact subgraph pool address, `WETH9()` on the router,
and live `quoteExactInputSingle` calls (struct params — the HSKSwap QuoterV2
uses the new ABI; the legacy 5-arg form reverts).

## HSK Chain mainnet — chain 177

RPC: `https://mainnet.hsk.xyz` · Explorer: `https://explorer.hsk.xyz`
Subgraph: `https://graphnode.hashkeychain.net/subgraphs/name/hskswap`

| Contract | Address | Verification |
|---|---|---|
| V3 Factory | `0x972cA9D1662F5e029cD18327D29026532E84c742` | code 49,072 B; `getPool(WHSK,USDT,3000)` → `0x4ff5…905dc` ✓ |
| SwapRouter02 | `0x2c16f75b95Cf1390c328aB70e2CEE7f4b80bD8F3` | code 48,996 B; `factory()` = factory; `WETH9()` = WHSK ✓ |
| QuoterV2 | `0x603f70466fDdbE3F238220B9a74FFF419a2BbFDD` | code 16,548 B; live quote 1 USDT → 12.36 WHSK ✓ |
| NonfungiblePositionManager | `0xDF0A9b833Db0E4CeEa103A4408f3B68e7FC0cad5` | code 48,770 B |
| Multicall | `0x7D0CBa43EbDD69ec2CE3B5AeAD3b0FbC796c565B` | code 2,768 B |
| WHSK | `0xB210D2120d57b758EE163cFfb43e73728c471Cf1` | 18 dec; router `WETH9()` ✓ |
| USDT | `0xf1b50ed67a9e2cc94ad3c477779e2d4cbfff9029` | 6 dec (on-chain `decimals()` = 6); matches truncated `0xF1B50e…Ff9029` ✓ |
| WETH | `0xefd4bc9afd210517803f293ababd701caeecdfd0` | 18 dec; matches truncated `0xefd4bC…eCdfd0` ✓ |
| WBTC | `0x6119ca49a79f5825c8b345f8d7ac36b272565b14` | 8 dec (subgraph) |
| USDT/WHSK pool (0.30%) | `0x4ff515761864e7838b0adb8b5b2b8b7a068905dc` | from subgraph + `getPool()` ✓ |
| USDT/WETH pool (0.30%) | `0xb92b79ed6b370d5cfee2e14b1d0983c258304c16` | from subgraph ✓ |
| USDT/WBTC pool (0.30%) | `0xd9ea2ce468957ba49ccc38c4758ed6ecd561449a` | from subgraph ✓ |
| Universal Router | `0x76D86a…d56918` | **UNVERIFIED — truncated in source, NOT used** |

Live mainnet quotes (23 Nov 2026): 1 USDT → 12.36 WHSK (WHSK ≈ $0.081);
1 WHSK → 0.0804 USDT. Consistent both directions.

## HSK Chain testnet — chain 133

RPC: `https://testnet.hsk.xyz` · Explorer: `https://testnet-explorer.hskchain.net`
Subgraph: `https://graphnode-testnet.hashkeychain.net/subgraphs/name/uniswap-v3/hsk-test`

The mainnet addresses have **NO code on testnet** — testnet is a separate
deployment. Testnet addresses were found from the HSKSwap npm package
`@hskswap/sdk-core` (`CHAIN_TO_ADDRESSES_MAP[133]`) and confirmed on-chain
(the factory's `getPool()` returns the subgraph pool; router/quoter
`factory()` points at the testnet factory).

| Contract | Address | Verification |
|---|---|---|
| V3 Factory | `0x2dC2c21D1049F786C535bF9d45F999dB5474f3A0` | code 49,072 B (same bytecode as mainnet factory); `getPool(USDT,WHSK,500)` → `0xff2b…f6ab` ✓; also the creator of pool `0xff2b…` on the explorer ✓ |
| SwapRouter02 | `0xa6914E66690c6794244B5f66a09eAEbf66254237` | code 48,996 B; `factory()` = testnet factory; `WETH9()` = testnet WHSK ✓ |
| QuoterV2 | `0x73820d9eE5Bf1BfcD429580320FC7A374E8fa1cC` | code 16,548 B; live quote 1 USDT → 0.0128 WHSK ✓ |
| NonfungiblePositionManager | `0x73dEc6bfa6751509b08480bd97f54b874E3b20e8` | code 48,770 B |
| Multicall | `0x47F625Ec29637445AA1570d7008Cf78692CdA096` | code 2,768 B |
| WHSK | `0xca8aaceec5db1e91b9ed3a344ba026c4a2b3ebf6` | 18 dec; `symbol()` = WHSK; 2,085 holders |
| USDT | `0x98b6173a8b7dfc52ce8bc88f1184a918a1ccaa4f` | **18 dec on testnet** (not 6!); `symbol()` = USDT |
| USDT/WHSK pool (0.05%) | `0xff2b7e501c870980bf5641b4a70d0f9fb0f6f6ab` | initialised, liquidity > 0, slot0 live ✓ |
| WETH / WBTC | — | **DO NOT EXIST on testnet** (no such tokens in the testnet subgraph). Testnet trades WHSK/USDT only. |

Live testnet quotes (23 Nov 2026): 1 USDT → 0.0128 WHSK; 1 WHSK → 78.04 USDT
(test WHSK ≈ $78 — test-pool price is arbitrary, not a market price).

## Notes

- The subgraph's `factories { id }` (`0x1f98431c…`) is the canonical Uniswap
  address template, NOT the real factory on either chain (no code there).
  The real factories are the ones in the tables above.
- QuoterV2 on both chains takes **struct** params
  (`quoteExactInputSingle((address,address,uint256,uint24,uint160))`).
  The legacy 5-argument form reverts — this was verified live.
- Faucet: https://hsk.xyz/faucet — 1 tHSK per address per 24h, Google
  reCAPTCHA required (browser + human step, see DEPLOYMENTS.md).
