# Cross-Chain Resolver Example: Stellar CLI Scripts Overview

This document provides a comprehensive overview of the shell scripts used to interact with the Stellar network in the cross-chain atomic swap implementation.

## 📋 Introduction

The scripts in the `scripts/` directory provide command-line interfaces for interacting with Stellar smart contracts. These scripts are designed to work with the Stellar CLI and are used both for manual testing and automated test execution via the `StellarCLI` wrapper class.

## 🔧 General Usage Patterns

Most scripts follow these conventions:
- Use environment variables for configuration (`SOURCE_KEY`, `NETWORK`)
- Accept command-line arguments for specific parameters
- Output structured information that can be parsed programmatically
- Include error handling and validation
- Support both testnet and mainnet operations

## 📁 Script Categories

### Core Escrow Operations

#### `deploy_escrow_parameterized.sh`
**Purpose**: Deploys a new escrow contract on Stellar with specified parameters

**Usage**: `./deploy_escrow_parameterized.sh <hashlock> <maker> <taker> <token> <amount> <cancellation_timestamp> [salt]`

**Role in Tests**: Used by `stellar-cli.ts` to deploy Stellar escrows for cross-chain swaps

**Key Features**:
- Accepts all escrow parameters as command-line arguments
- Generates random salt if not provided
- Parses contract address from deployment output
- Creates detailed log files for debugging

#### `interact_escrow.sh`
**Purpose**: Comprehensive escrow interaction script for all escrow operations

**Usage**: 
```bash
./interact_escrow.sh [--source PROFILE] [--network NET] <command> <args>
```

**Commands**:
- `info <escrow>` - Get escrow information and immutables
- `withdraw <escrow> <secret>` - Withdraw from escrow using secret
- `cancel <escrow>` - Cancel escrow after timeout
- `fund <escrow> <maker> <amount> <token>` - Fund escrow with tokens
- `fund-auto <escrow> <maker>` - Auto-fund using escrow's immutable data

**Role in Tests**: Primary interface for escrow operations in the test suite

### LOP (Limit Order Protocol) Operations

#### `interact_lop.sh`
**Purpose**: Interface for interacting with the pre-deployed LOP contract

**Usage**: 
```bash
./interact_lop.sh [--source PROFILE] [--network NET] <command> <args>
```

**Commands**:
- `info <lop_contract>` - Get LOP contract information
- `fill-order <lop_contract> <order_json> <taker>` - Fill a limit order
- `cancel-order <lop_contract> <order_json>` - Cancel a limit order
- `get-order-state <lop_contract> <order_json>` - Check order status
- `get-current-price <lop_contract> <order_json>` - Get current Dutch auction price
- `create-order-json <output_file> [--dutch-auction]` - Create order template

**Role in Tests**: Used for LOP order creation and execution in cross-chain scenarios

**Note**: Works with the pre-deployed LOP contract at `CDLWW5OUQZWE76WLYGKN6TCOG2UKOZ4HTOU5UN6RMNTXOCMDVWHE5UO4`

### Factory and Deployment Scripts

#### `deploy_lop_parameterized.sh`
**Purpose**: Deploy LOP contracts via factory (not used in current tests)

**Status**: Present but not actively used since tests use pre-deployed LOP contract

#### `get_escrow_address.sh`
**Purpose**: Get deterministic escrow address without deploying

**Usage**: `./get_escrow_address.sh <salt>`

**Role**: Utility for address calculation and verification

#### `get_lop_address.sh`
**Purpose**: Get deterministic LOP contract address without deploying

**Usage**: `./get_lop_address.sh <salt> [--dutch-auction]`

**Role**: Utility for LOP address calculation

### Atomic Swap Orchestration

#### `atomic_swap.sh`
**Purpose**: Complete atomic swap orchestration script

**Usage**: `./atomic_swap.sh <lop_contract> <order_json_file> [options]`

**Features**:
- Deploys fresh escrow for each trade
- Funds escrow with required assets
- Fills order on existing LOP contract
- Provides withdrawal instructions
- Creates detailed execution logs

**Role**: Demonstrates complete atomic swap workflow

**Note**: This script showcases the full integration but is not directly used in the automated test suite

### Monitoring and Analysis

#### `monitor_dutch_auction.sh`
**Purpose**: Real-time monitoring of Dutch auction price changes

**Usage**: `./monitor_dutch_auction.sh <lop_contract> <order_json> [options]`

**Features**:
- Live price monitoring during auction
- Simulation mode for testing
- Progress tracking and status updates
- Configurable monitoring intervals

**Role**: Development and debugging tool for Dutch auction behavior

#### `lop_dutch.sh`
**Purpose**: Dutch auction price analysis and demonstration

**Usage**: `./lop_dutch.sh [order_file] [--current-time SEC]`

**Features**:
- Price progression analysis
- Current price calculation
- Auction state visualization
- Educational demonstrations

**Role**: Analysis and educational tool for understanding Dutch auction mechanics

### Utility Scripts

#### `build_order.sh`
**Purpose**: Build properly formatted LOP order JSON objects

**Usage**: `./build_order.sh --salt <u64> --maker G... [other params] [--out file.json]`

**Role**: Helper for creating valid order structures

## 🔄 Scripts Used in Test Suite

The following scripts are actively used by the `StellarCLI` wrapper in `tests/stellar-cli.ts`:

### Primary Scripts
1. **`deploy_escrow_parameterized.sh`** - Escrow deployment
2. **`interact_escrow.sh`** - All escrow operations (fund, withdraw, cancel, info)
3. **`interact_lop.sh`** - LOP order operations

### Integration Pattern
```typescript
// Example from stellar-cli.ts
async deployEscrow(params) {
    return this.executeScript('deploy_escrow_parameterized.sh', [
        params.hashlock,
        params.maker,
        params.taker,
        params.token,
        params.amount,
        params.cancellationTimestamp.toString()
    ])
}
```

## 🚫 Scripts Not Used in Current Tests

These scripts are part of the broader project but not directly exercised by `main.spec.ts`:

- `deploy_lop.sh` / `deploy_lop_parameterized.sh` - LOP deployment (using pre-deployed contract)
- `atomic_swap.sh` - Complete workflow (tests use individual components)
- `monitor_dutch_auction.sh` - Monitoring tools
- `lop_dutch.sh` - Analysis tools
- `interact_lop_factory.sh` - Factory management
- Various utility and address calculation scripts

## 🔧 Configuration and Environment

### Common Environment Variables
- `SOURCE_KEY` - Stellar account key for signing (default: "lion")
- `NETWORK` - Stellar network (default: "testnet")
- `FACTORY_ID` - Escrow factory contract address
- `LOP_FACTORY_ID` - LOP factory contract address

### Script Execution Environment
- All scripts expect to be run from the `scripts/` directory
- Scripts create timestamped log files for debugging
- Output parsing handles multiple response formats from Stellar CLI
- Error handling includes detailed failure reporting

## 📝 Output Parsing

Scripts use sophisticated parsing to extract:
- **Contract Addresses**: Multiple regex patterns for different output formats
- **Transaction Hashes**: Hex pattern matching
- **Balances**: Numeric extraction from various response formats
- **Event Data**: JSON and structured text parsing

## 🔍 Debugging and Logs

Each script execution creates:
- Timestamped log files (e.g., `deploy_escrow_20250802_130221.log`)
- Detailed parameter summaries
- Raw CLI output preservation
- Error context and troubleshooting information

## 🎯 Best Practices

When using these scripts:
1. Always check script exit codes for success/failure
2. Parse output programmatically rather than relying on human-readable text
3. Use environment variables for consistent configuration
4. Preserve log files for debugging complex interactions
5. Validate all input parameters before script execution

---

These scripts form the foundation of Stellar network interaction in the cross-chain atomic swap system, providing reliable and scriptable interfaces to Soroban smart contracts.