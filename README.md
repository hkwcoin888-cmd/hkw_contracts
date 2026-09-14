# HKW Token Contract

Open-source TRC20 token contract for **HKW** (`hkw.com` / `HKW`) on the TRON network.

> This repository contains **only** the `HKWToken` contract source. Other project contracts, backend services, and the website are **not** included.

## Mainnet

| Item | Value |
| --- | --- |
| Network | TRON |
| Name / Symbol | `hkw.com` / `HKW` |
| Decimals | `6` |
| Max supply | `10,000,000,000` HKW (fixed; burns do not reduce this figure) |
| Contract | [`TAxQAo9dqpVm44BQCZSR5rXKdRFMfaNJE1`](https://tronscan.org/#/contract/TAxQAo9dqpVm44BQCZSR5rXKdRFMfaNJE1) |

## Features

- Standard TRC20 interface (`transfer` / `approve` / `transferFrom` / `balanceOf` / `allowance`)
- Fixed max supply — **no minting**
- Transfer burn-tax: **0.01%** sent to the zero address, capped at **10,000 HKW** per transfer
- DEX pair paths (registered pairs) are tax-exempt
- Optional burn by transferring to the zero address (no admin burn entrypoint)
- On-chain `totalBurned` accumulates explicit burns and transfer-tax burns
- No holding-based sell gate in the token contract
- Owner can only manage pair registration — cannot mint or change tax parameters

## Source

```text
contracts/HKWToken.sol
```

Compiler target: Solidity `>=0.8.0 <0.9.0` (MIT licensed).

## Disclaimer

HKW is currently an informational project website; the prediction-market product is not yet live. Future features may be unavailable to users in certain jurisdictions. Nothing in this repository constitutes gambling, investment advice, a securities offering, or an invitation to trade event contracts.

Website: [https://hkw.com](https://hkw.com)
