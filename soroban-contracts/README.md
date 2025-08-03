# Soroban Smart Contracts

This directory contains a complete **escrow and trading system** built on Soroban (Stellar smart contracts) with support for **Hash Time Lock Contracts (HTLCs)**, **Dutch auctions**, and **limit order protocols**.

## 📦 Project Structure

```text
.
├── contracts/
│   ├── hello-world/              # Simple "Hello World" example contract
│   ├── soroban-escrow/           # Hash Time Lock Contract (HTLC) escrow
│   ├── soroban-escrow-factory/   # Factory for deploying escrow contracts
│   ├── soroban-dutch-auction/    # Linear price decay auction contract
│   ├── soroban-lop/              # Limit Order Protocol (fixed-price & Dutch)
│   └── soroban-lop-factory/      # Factory for deploying LOP contracts
├── Cargo.toml                    # Workspace configuration
└── README.md
```

## 🔧 Contracts Overview

### Core Escrow System
* **[Soroban Escrow](./contracts/soroban-escrow/)** – HTLC implementation for secure escrow transactions
* **[Soroban Escrow Factory](./contracts/soroban-escrow-factory/)** – Deterministic escrow contract deployment

### Trading System  
* **[Soroban Dutch Auction](./contracts/soroban-dutch-auction/)** – Time-based linear price decay auctions
* **[Soroban LOP](./contracts/soroban-lop/)** – Limit Order Protocol supporting fixed-price and Dutch auction orders
* **[LOP Factory](./contracts/soroban-lop-factory/)** – Deploys and manages LOP and Dutch Auction contracts

### Example Contract
* **[Hello World](./contracts/hello-world/)** – Basic Soroban contract example

## 🔑 Key Features

**Escrow System:**
* ✅ Hash-locked withdrawals with secret reveal
* ✅ Time-based cancellation for fund recovery
* ✅ Token agnostic (works with any Stellar asset)
* ✅ Deterministic contract deployment via factory

**Trading System:**
* ✅ Fixed-price limit orders
* ✅ Dutch auction orders with linear price decay
* ✅ Factory-deployed contracts for predictable addresses
* ✅ Comprehensive order management

## 🚀 Quick Start

### Build All Contracts
```bash
stellar contract build
```

### Run All Tests
```bash
cargo test
```

### Build Specific Contract
```bash
cd contracts/soroban-escrow
stellar contract build
```

## 🏗️ Development Workflow

### 1. **Building Contracts**
```bash
# Build all contracts in workspace
stellar contract build

# Build specific contract
cd contracts/CONTRACT_NAME
stellar contract build
```

### 2. **Testing Contracts**
```bash
# Run all tests
cargo test

# Test with verbose output
cargo test -- --nocapture

# Test specific contract
cd contracts/CONTRACT_NAME
cargo test
```

### 3. **Deployment Prerequisites**
```bash
# Add testnet configuration
stellar network add testnet \
  --rpc-url https://soroban-testnet.stellar.org:443 \
  --network-passphrase "Test SDF Network ; September 2015"

# Generate identity
stellar keys generate alice --network testnet
```

## 📚 Contract Documentation

### **Core Escrow Contracts**
* **[Soroban Escrow](./contracts/soroban-escrow/README.md)** – Complete HTLC escrow implementation
* **[Soroban Escrow Factory](./contracts/soroban-escrow-factory/README.md)** – Deterministic escrow deployment

### **Trading Contracts**  
* **[Soroban Dutch Auction](./contracts/soroban-dutch-auction/README.md)** – Linear price decay auctions
* **[Soroban LOP](./contracts/soroban-lop/README.md)** – Limit Order Protocol
* **[LOP Factory](./contracts/soroban-lop-factory/README.md)** – LOP contract deployment and management

### **Example Contract**
* **[Hello World](./contracts/hello-world/README.md)** – Basic Soroban contract structure

## 🔄 Cross-Chain Integration

These contracts are designed to work with the **[Cross-Chain Resolver](../cross-chain/)** for atomic swaps between Ethereum and Stellar:

* **Escrow contracts** provide HTLC functionality for trustless swaps
* **Factory contracts** enable deterministic deployment for cross-chain coordination
* **LOP contracts** support both fixed-price and auction-based trading

## 🛠️ Adding New Contracts

1. **Create directory**: `contracts/your-contract-name/`
2. **Add Cargo.toml**: Include workspace dependencies
3. **Implement contract**: Create `src/lib.rs` with your logic
4. **Add tests**: Create `src/test.rs` with comprehensive tests
5. **Update workspace**: Add contract to root `Cargo.toml`
6. **Document**: Create `README.md` with usage examples

## 🔒 Security Considerations

### **Escrow Contracts**
* Keep secrets secure until withdrawal time
* Ensure sufficient time windows for legitimate operations
* Verify token contracts before creating escrows
* Use unique salts for factory deployments

### **Trading Contracts**
* Validate order parameters before submission
* Monitor auction timing for price decay accuracy
* Verify factory admin permissions and WASM updates

## 🌐 Network Support

All contracts support deployment on:
* **Testnet** – `testnet` (recommended for development)
* **Mainnet** – `mainnet` (production deployments)  
* **Local** – `local` (local development network)