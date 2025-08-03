# Cross-Chain Resolver Example: Test Setup Guide

This guide will help you set up and run the cross-chain atomic swap tests between Ethereum and Stellar networks.

## Prerequisites

Before running the tests, ensure you have the following software installed:

### Required Software

1. **Node.js** (version 22 or higher)
   - Download from [nodejs.org](https://nodejs.org/)
   - Verify installation: `node --version`

2. **pnpm** (Package Manager)
   - Install globally: `npm install -g pnpm`
   - Verify installation: `pnpm --version`

3. **Foundry** (Ethereum Development Toolkit)
   - Install: `curl -L https://foundry.paradigm.xyz | bash`
   - Follow the installation instructions and run: `foundryup`
   - Verify installation: `forge --version`

4. **Stellar CLI**
   - Install following [Stellar CLI documentation](https://developers.stellar.org/docs/tools/developer-tools)
   - Verify installation: `stellar --version`

## Installation

1. **Clone the Repository**
   ```bash
   cd cross-chain-resolver-example
   ```

2. **Install Node.js Dependencies**
   ```bash
   pnpm install
   ```

3. **Install Contract Dependencies**
   ```bash
   forge install
   ```

4. **Make Scripts Executable**
   ```bash
   chmod +x scripts/*.sh
   ```

## Configuration

### Environment Variables

Create a `.env` file in the project root based on `.env.example`:

```bash
cp .env.example .env
```

Configure the following environment variables:

#### Ethereum Configuration
- **`SRC_CHAIN_RPC`**: Ethereum RPC URL for the source chain
  - Example: `https://eth.merkle.io`
  - Used for Ethereum mainnet fork in tests

- **`DST_CHAIN_RPC`**: BSC RPC URL (legacy, not used in current tests)
  - Example: `wss://bsc-rpc.publicnode.com`

- **`SRC_CHAIN_CREATE_FORK`**: Whether to create a local fork (default: `true`)
- **`DST_CHAIN_CREATE_FORK`**: Whether to create a destination fork (default: `true`)

#### Stellar Configuration
- **`STELLAR_NETWORK`**: Stellar network to use (default: `testnet`)
  - Options: `testnet`, `futurenet`, `mainnet`

- **`STELLAR_SOURCE_KEY`**: Stellar account key for signing transactions (default: `lion`)
  - This should be a key configured in your Stellar CLI
  - For testnet, you can use the default `lion` key 

### Example .env File
```env
SRC_CHAIN_RPC=https://eth.merkle.io
DST_CHAIN_RPC=wss://bsc-rpc.publicnode.com
SRC_CHAIN_CREATE_FORK=true
DST_CHAIN_CREATE_FORK=true
STELLAR_NETWORK=testnet
STELLAR_SOURCE_KEY=lion
```

## Stellar CLI Setup

### Configure Stellar CLI Network
```bash
stellar network add testnet \
  --rpc-url https://soroban-testnet.stellar.org:443 \
  --network-passphrase "Test SDF Network ; September 2015"
```

### Create or Import Test Account
```bash
# Generate a new test account
stellar keys generate lion --network testnet

# Or import an existing account
stellar keys add lion --secret-key <your-secret-key>
```

### Fund Test Account (Testnet Only)
```bash
stellar keys fund lion --network testnet
```

## Running Tests

### Execute All Tests
```bash
pnpm test
```

### Run with Specific RPC URLs
```bash
SRC_CHAIN_RPC=<your-eth-rpc> DST_CHAIN_RPC=<your-bsc-rpc> pnpm test
```

### Run with Debug Output
```bash
DEBUG=* pnpm test
```

## What Happens When Tests Run

1. **Anvil Fork Creation**: The test suite creates local Ethereum forks using the provided RPC URLs
2. **Contract Deployment**: Deploys EscrowFactory and Resolver contracts on the forked Ethereum network
3. **Account Setup**: Configures test accounts with USDC tokens and approvals
4. **Cross-Chain Tests**: Executes atomic swap scenarios between Ethereum and Stellar
5. **Stellar CLI Interaction**: Uses shell scripts to interact with pre-deployed Stellar contracts
6. **Balance Verification**: Confirms successful asset transfers or proper cancellations

## Test Accounts

The tests use predefined accounts with specific roles:

- **Owner/Factory Deployer**: `0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266`
- **User**: `0x70997970C51812dc3A010C7d01b50e0d17dc79C8`
- **Resolver**: `0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC`

## Troubleshooting

### Common Issues

1. **"Missing dependency" errors**
   - Ensure all prerequisites are installed and accessible in your PATH
   - Run `which stellar`, `which forge`, `which node` to verify installations

2. **RPC connection failures**
   - Verify your RPC URLs are accessible
   - Check if you need authentication tokens for your RPC providers
   - Try using public RPC endpoints for testing

3. **Stellar CLI errors**
   - Ensure your Stellar CLI is properly configured with network settings
   - Verify your test account has sufficient XLM balance for transactions
   - Check that the `lion` key exists: `stellar keys list`

4. **Permission denied on scripts**
   - Make scripts executable: `chmod +x scripts/*.sh`
   - Ensure you're running from the project root directory

5. **Test timeouts**
   - Increase Jest timeout if tests are running slowly
   - Check network connectivity to both Ethereum and Stellar networks

### Debug Commands

```bash
# Check Stellar CLI configuration
stellar config

# List available keys
stellar keys list

# Check account balance
stellar account --account <account-id> --network testnet

# Test script execution manually
./scripts/interact_escrow.sh info <escrow-address>
```

### Getting Help

- Check the main README.md for project overview
- Review SCRIPTS.md for detailed script documentation
- Ensure all environment variables are properly set
- Verify that pre-deployed contracts are accessible on your target networks