# Cross-Chain Resolver Example: Atomic Swaps between Ethereum and Stellar

This project demonstrates secure and atomic cross-chain asset transfers between Ethereum and Stellar networks using Hashed Timelock Contracts (HTLCs). It showcases how users can safely exchange assets across different blockchain ecosystems without requiring trusted intermediaries.

## 🌟 Overview

The Cross-Chain Resolver Example implements atomic swaps that enable users to exchange assets between Ethereum (USDC) and Stellar (XLM) networks. The system ensures that either both parties receive their desired assets, or both parties can safely reclaim their original funds - there is no scenario where one party loses assets while the other gains them.

## 🔐 Core Concept: Hashed Timelock Contracts (HTLCs)

The atomic swap mechanism relies on three key cryptographic primitives:

### Hashlock
- A cryptographic commitment using a secret value
- The same secret unlocks escrows on both chains
- Ensures that revealing the secret on one chain enables withdrawal on the other

### Timelock
- Time-based constraints that prevent funds from being locked forever
- Allows parties to reclaim their funds if the swap doesn't complete
- Different timelock periods for withdrawal vs. cancellation phases

### Atomicity
- **Success**: Both parties get their desired assets
- **Failure**: Both parties reclaim their original assets
- **No Partial Completion**: Impossible for only one side to complete

## 🌐 Supported Networks

- **Ethereum**: Source chain for USDC transfers using EVM smart contracts
- **Stellar**: Destination chain for XLM transfers using Soroban smart contracts

## 🔄 Swap Scenarios

### 1. Successful Ethereum to Stellar Swap

**Flow:**
1. User locks USDC in Ethereum escrow with hashlock
2. Resolver deploys and funds XLM escrow on Stellar with same hashlock
3. User reveals secret to withdraw XLM from Stellar escrow
4. Resolver uses revealed secret to withdraw USDC from Ethereum escrow

**Result:** User receives XLM, Resolver receives USDC

### 2. Cancellation Scenario

**Flow:**
1. User locks USDC in Ethereum escrow
2. Resolver deploys and funds XLM escrow on Stellar
3. Secret is NOT revealed within timelock period
4. Both parties cancel their respective escrows after timeout

**Result:** User reclaims USDC, Resolver reclaims XLM

## 🏗️ Architecture

### Ethereum Components
- **EscrowFactory**: Deploys escrow contracts with deterministic addresses
- **Resolver Contract**: Orchestrates cross-chain operations and manages escrow lifecycle
- **Node.js Integration**: Handles Ethereum transactions and smart contract interactions

### Stellar Components
- **Pre-deployed LOP Contract**: `CDLWW5OUQZWE76WLYGKN6TCOG2UKOZ4HTOU5UN6RMNTXOCMDVWHE5UO4`
- **Escrow Factory**: `CACURHRDVGNUCFSMDWTIF6TABC76LNTAQYSIVDJK34P43OYOGPSGYDSO`
- **Shell Script Integration**: Manages Stellar operations via CLI commands

### Cross-Chain Coordination
- **Shared Cryptographic Proof**: Same secret/hashlock used on both chains
- **Time-Synchronized Execution**: Coordinated timelock periods ensure safety
- **Deterministic Addressing**: Escrow addresses can be computed before deployment

## ✨ Key Features

### Security
- **Atomic Execution**: No partial failures possible
- **Cryptographic Guarantees**: Hash-based secret sharing ensures trustless operation
- **Time-Based Safety**: Automatic fund recovery if swap doesn't complete

### Cross-Chain Interoperability
- **Heterogeneous Networks**: Connects EVM (Ethereum) and Stellar ecosystems
- **Protocol Agnostic**: Can be extended to other blockchain networks
- **Asset Flexibility**: Supports different token types on each chain

### Developer Experience
- **Comprehensive Testing**: Full test suite covering success and failure scenarios
- **CLI Integration**: Real-world interaction patterns using command-line tools
- **Clear Documentation**: Step-by-step setup and execution guides

## 🧪 Test Coverage

The test suite demonstrates:

1. **End-to-End Atomic Swaps**: Complete successful cross-chain asset exchange
2. **Cancellation Mechanisms**: Safe fund recovery when swaps don't complete
3. **Balance Verification**: Confirms correct asset movements on both chains
4. **Error Handling**: Proper behavior under various failure conditions
5. **Real Network Interaction**: Uses actual Stellar CLI commands and Ethereum forks

## 🚀 Getting Started

1. **Setup**: Follow the [SETUP.md](./SETUP.md) guide to configure your environment
2. **Scripts**: Review [SCRIPTS.md](./SCRIPTS.md) for detailed script documentation
3. **Run Tests**: Execute `pnpm test` to see atomic swaps in action

## 🔧 Technical Implementation

### Smart Contracts
- **Solidity Contracts**: Handle Ethereum-side escrow logic and cross-chain coordination
- **Soroban Contracts**: Manage Stellar-side escrow operations and LOP interactions

### Integration Layer
- **TypeScript Tests**: Orchestrate cross-chain operations and verify outcomes
- **Shell Scripts**: Provide CLI-based interaction with Stellar network
- **Configuration Management**: Environment-based setup for different networks

## 🎯 Use Cases

This example demonstrates patterns applicable to:

- **Decentralized Exchanges**: Cross-chain trading without centralized custody
- **Payment Systems**: Multi-chain payment routing and settlement
- **DeFi Protocols**: Cross-chain lending, borrowing, and yield farming
- **Asset Bridges**: Trustless asset transfers between blockchain networks

