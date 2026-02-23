# X3NA Protocol

A transparent, upgradeable prediction market protocol built on Base. This repository contains all smart contract code for public verification.

## Deployed Contracts (Base Mainnet)

| Contract  | Address                                                                                                                      | Verified |
| --------- | ---------------------------------------------------------------------------------------------------------------------------- | -------- |
| X3NA      | [`0x2BfF6c20964aa5cE17A998F903B6eA23A51F9543`](https://basescan.org/address/0x2BfF6c20964aa5cE17A998F903B6eA23A51F9543#code) | ✅       |
| Referrals | [`0xff8dDbC654056CbCc2C8C96A24EC3D859473b6bc`](https://basescan.org/address/0xff8dDbC654056CbCc2C8C96A24EC3D859473b6bc#code) | ✅       |

## Why Open Source?

We believe in full transparency. All smart contract logic is publicly available so users can:

- Verify there are no hidden fees or backdoors
- Audit the betting and reward distribution logic
- Confirm the fairness of the protocol

## Architecture

```
X3NA (Prediction Market)
├── AccessControlUpgradeable    - Role-based permissions
├── PausableUpgradeable         - Emergency stops
├── ReentrancyGuardUpgradeable  - Security
└── Referrals Integration       - Affiliate system

Referrals (Affiliate System)
├── Tiered reward system (20-50% based on volume)
├── Custom commission support
└── Transparent reward tracking
```

## Key Features

- **Round-based betting**: Bull/Bear predictions on price movements
- **Fair fee structure**: Treasury fee is transparent and applied equally
- **Auto-claim**: Optional automatic reward distribution
- **Referral rewards**: Multi-tier affiliate program

## How It Works

1. **Betting Phase**: Users place bets (Bull or Bear) during active round
2. **Lock Phase**: Betting closes, lock price is recorded
3. **Resolution**: Close price determines winners
4. **Rewards**: Winners share the losing pool minus treasury fee

## Verify Yourself

### Prerequisites

```bash
npm install
```

### Compile

```bash
npm run build
```

### Run Tests

```bash
npm run test
```

### Compare with Deployed Code

Compare the compiled bytecode with verified contracts on BaseScan.

## Documentation

- [X3NA Contract Documentation](./docs/X3NA.md)
- [Referrals Contract Documentation](./docs/Referrals.md)

## Security

- Contracts are upgradeable via OpenZeppelin's TransparentUpgradeableProxy
- Multi-sig admin controls (not exposed in this repo)
- See [SECURITY.md](./SECURITY.md) for vulnerability reporting

## License

This project is licensed under the MIT License - see [LICENSE](./LICENSE) file.

---

**Note**: This repository is for transparency and verification purposes. The deployment scripts and configurations are examples only.
