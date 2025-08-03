# Cross-Chain Atomic Swap System

This repository contains smart contracts and examples for building **trustless cross-chain swaps** between Ethereum and Stellar using **Hashed Timelock Contracts (HTLCs)**.

## 📦 What's Inside?

* **[Cross-Chain Resolver](./cross-chain/)** – Coordinates atomic swaps between Ethereum (USDC) and Stellar (XLM)
* **[Soroban Contracts](./soroban-contracts/)** – Complete escrow and trading system on Stellar
  * **Soroban Escrow** – Secure escrow contract with hashlocks and timelocks
  * **Soroban Escrow Factory** – Deploys multiple escrow contracts with predictable addresses
  * **Soroban Dutch Auction** – Linear price decay for time-based auctions
  * **Soroban LOP (Limit Order Protocol)** – Fixed-price and Dutch auction trading
  * **LOP Factory** – Deploys and manages LOP and Dutch Auction contracts
* **[CLI Scripts](./scripts/)** – Command-line tools for Stellar network interaction

## 🏗️ Architecture

```
┌─────────────┐    ┌───────────────────┐    ┌─────────────┐
│   Ethereum  │    │   Cross-Chain      │    │   Stellar   │
│   (USDC)    │◄──►│   Resolver         │◄──►│   (XLM)     │
└─────────────┘    └───────────────────┘    └─────────────┘
       │                   │                     │
       ▼                   ▼                     ▼
  EscrowFactory      LOP + Dutch Auction    EscrowFactory
   (HTLC)               Contracts             (HTLC)
```

* The **Resolver** uses the same secret hash on both chains to ensure atomicity.
* **Factories** allow predictable deployment of escrow and order contracts.
* **LOP** enables both fixed-price and Dutch auction trades.

## 🔑 Key Features

* ✅ Trustless swaps using shared secrets and timelocks
* ✅ Deterministic contract deployment for cross-chain coordination
* ✅ Fixed-price and Dutch auction orders
* ✅ Ready-to-use tests and CLI scripts

## 🚀 Quick Start

1. **Clone the repo**
   ```bash
   git clone <repo-url>
   cd still-fi-main
   ```

2. **Install dependencies**
   ```bash
   pnpm install
   forge install
   ```

3. **Set up environment** → See [Setup Guide](./cross-chain/SETUP.md)

4. **Run tests**
   ```bash
   cd cross-chain
   pnpm test
   ```

## 📁 Project Structure

```
├── cross-chain/           # Ethereum contracts & cross-chain coordination
│   ├── contracts/        # Ethereum Resolver & Factory contracts
│   ├── tests/           # End-to-end atomic swap tests
│   └── README.md        # Cross-chain implementation details
├── soroban-contracts/    # Stellar smart contracts
│   ├── contracts/       # Individual Soroban contracts
│   └── README.md        # Soroban contracts overview
└── scripts/             # Stellar CLI interaction scripts
    └── README.md        # Scripts documentation
```

## 📚 Documentation

### Core Components
* **[Cross-Chain Implementation](./cross-chain/README.md)** - Atomic swaps between Ethereum and Stellar
* **[Soroban Contracts](./soroban-contracts/README.md)** - Complete Stellar smart contract system
* **[CLI Scripts](./scripts/README.md)** - Command-line tools and utilities

### Individual Contracts
* [Soroban Escrow](./soroban-contracts/contracts/soroban-escrow/README.md) - HTLC escrow implementation
* [Soroban Escrow Factory](./soroban-contracts/contracts/soroban-escrow-factory/README.md) - Deterministic escrow deployment
* [Soroban Dutch Auction](./soroban-contracts/contracts/soroban-dutch-auction/README.md) - Time-based price decay auctions
* [Soroban LOP](./soroban-contracts/contracts/soroban-lop/README.md) - Limit Order Protocol
* [LOP Factory](./soroban-contracts/contracts/soroban-lop-factory/README.md) - LOP contract deployment

### Guides
* [Setup Instructions](./cross-chain/SETUP.md) - Environment configuration
* [Script Documentation](./cross-chain/SCRIPTS.md) - Detailed script usage


