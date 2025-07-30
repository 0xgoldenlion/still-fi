# Soroban Escrow System

This repository contains a complete escrow system built on Soroban (Stellar smart contracts) with the following components:

## Project Structure

```text
.
├── contracts/
│   ├── hello-world/           # Simple "Hello World" example contract
│   ├── soroban-escrow/        # Hash Time Lock Contract (HTLC) escrow
│   └── soroban-escrow-factory/ # Factory for deploying escrow contracts
├── Cargo.toml                 # Workspace configuration
└── README.md
```

## Contracts Overview

### 1. Hello World Contract (`contracts/hello-world/`)
A simple example contract that demonstrates basic Soroban functionality.

**Features:**
- Basic greeting functionality
- Example of Soroban contract structure

### 2. Soroban Escrow Contract (`contracts/soroban-escrow/`)
A Hash Time Lock Contract (HTLC) implementation that enables secure escrow transactions.

**Features:**
- **Hash-locked withdrawals**: Funds can only be withdrawn by providing the correct secret
- **Time-based cancellation**: Maker can reclaim funds after a specified timestamp
- **Token agnostic**: Works with any Stellar token
- **Immutable parameters**: All escrow terms are set at initialization and cannot be changed

**Key Functions:**
- `initialize(immutables)` - Set up the escrow with all parameters
- `withdraw(secret)` - Taker withdraws funds by providing the correct secret
- `cancel()` - Maker reclaims funds after cancellation timestamp
- `get_immutables()` - View escrow parameters

### 3. Soroban Escrow Factory Contract (`contracts/soroban-escrow-factory/`)
A factory contract that deploys and manages escrow contracts with deterministic addresses.

**Features:**
- **Deterministic deployment**: Predict escrow addresses before deployment
- **WASM management**: Admin can update the escrow contract WASM
- **Batch operations**: Deploy multiple escrow contracts efficiently

**Key Functions:**
- `initialize(admin, escrow_wasm_hash)` - Initialize factory with admin and escrow WASM
- `deploy_escrow(immutables, salt)` - Deploy a new escrow contract
- `get_escrow_address(salt)` - Get deterministic address without deploying
- `update_escrow_wasm_hash(new_wasm_hash)` - Update escrow WASM (admin only)

## Building Contracts

Build all contracts:
```bash
stellar contract build
```

Build a specific contract:
```bash
cd contracts/soroban-escrow
stellar contract build
```

## Testing Contracts

Run all tests:
```bash
cargo test
```

Test a specific contract:
```bash
cd contracts/soroban-escrow
cargo test
```

Test with verbose output:
```bash
cargo test -- --nocapture
```

## Deploying Contracts

### Prerequisites
1. Install Stellar CLI
2. Configure network and identity:
```bash
stellar network add testnet \
  --rpc-url https://soroban-testnet.stellar.org:443 \
  --network-passphrase "Test SDF Network ; September 2015"

stellar keys generate alice --network testnet
```

### Deploy Escrow Contract
```bash
stellar contract deploy \
  --wasm target/wasm32-unknown-unknown/release/soroban_escrow_contract.wasm \
  --source alice \
  --network testnet \
  --alias escrow
```

### Deploy Factory Contract
```bash
stellar contract deploy \
  --wasm target/wasm32-unknown-unknown/release/soroban_escrow_factory_contract.wasm \
  --source alice \
  --network testnet \
  --alias escrow_factory
```

### Deploy Hello World Contract
```bash
stellar contract deploy \
  --wasm target/wasm32-unknown-unknown/release/hello_world.wasm \
  --source alice \
  --network testnet \
  --alias hello_world
```

## Interacting with Contracts

### Hello World Contract

Say hello:
```bash
stellar contract invoke \
  --id hello_world \
  --source alice \
  --network testnet \
  -- \
  hello \
  --to "World"
```

### Escrow Factory Contract

#### 1. Initialize Factory
First, get the escrow contract WASM hash:
```bash
stellar contract install \
  --wasm target/wasm32-unknown-unknown/release/soroban_escrow_contract.wasm \
  --source alice \
  --network testnet
```

Initialize the factory with the WASM hash:
```bash
stellar contract invoke \
  --id escrow_factory \
  --source alice \
  --network testnet \
  -- \
  initialize \
  --admin GXXXXX... \
  --escrow_wasm_hash WASM_HASH_HERE
```

#### 2. Deploy Escrow via Factory
```bash
stellar contract invoke \
  --id escrow_factory \
  --source alice \
  --network testnet \
  -- \
  deploy_escrow \
  --immutables '{"hashlock":"HASH_HERE","maker":"MAKER_ADDRESS","taker":"TAKER_ADDRESS","token":"TOKEN_ADDRESS","amount":"1000","cancellation_timestamp":"1234567890"}' \
  --salt SALT_BYTES_HERE
```

#### 3. Get Escrow Address (Prediction)
```bash
stellar contract invoke \
  --id escrow_factory \
  --source alice \
  --network testnet \
  -- \
  get_escrow_address \
  --salt SALT_BYTES_HERE
```

### Escrow Contract

#### 1. Initialize Escrow (if deployed directly)
```bash
stellar contract invoke \
  --id escrow \
  --source alice \
  --network testnet \
  -- \
  initialize \
  --immutables '{"hashlock":"SECRET_HASH","maker":"MAKER_ADDRESS","taker":"TAKER_ADDRESS","token":"TOKEN_ADDRESS","amount":"1000","cancellation_timestamp":"1234567890"}'
```

#### 2. Withdraw Funds (Taker)
```bash
stellar contract invoke \
  --id escrow \
  --source taker \
  --network testnet \
  -- \
  withdraw \
  --secret SECRET_BYTES_HERE
```

#### 3. Cancel Escrow (Maker)
```bash
stellar contract invoke \
  --id escrow \
  --source maker \
  --network testnet \
  -- \
  cancel
```

#### 4. View Escrow Details
```bash
stellar contract invoke \
  --id escrow \
  --source alice \
  --network testnet \
  -- \
  get_immutables
```

## Example Escrow Flow

Here's a complete example of creating and using an escrow:

### 1. Create Secret and Hash
```bash
# Generate a secret (32 bytes)
SECRET="0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef"

# Hash the secret (you'll need to do this programmatically)
SECRET_HASH="RESULTING_HASH_HERE"
```

### 2. Deploy Escrow
```bash
stellar contract invoke \
  --id escrow_factory \
  --source alice \
  --network testnet \
  -- \
  deploy_escrow \
  --immutables "{
    \"hashlock\":\"$SECRET_HASH\",
    \"maker\":\"MAKER_ADDRESS\",
    \"taker\":\"TAKER_ADDRESS\",
    \"token\":\"TOKEN_ADDRESS\",
    \"amount\":\"1000\",
    \"cancellation_timestamp\":\"$(date -d '+1 hour' +%s)\"
  }" \
  --salt "UNIQUE_SALT_HERE"
```

### 3. Fund Escrow
Transfer tokens to the deployed escrow address.

### 4. Withdraw (Happy Path)
```bash
stellar contract invoke \
  --id ESCROW_ADDRESS \
  --source taker \
  --network testnet \
  -- \
  withdraw \
  --secret $SECRET
```

### 5. Cancel (Timeout Path)
Wait for cancellation timestamp, then:
```bash
stellar contract invoke \
  --id ESCROW_ADDRESS \
  --source maker \
  --network testnet \
  -- \
  cancel
```

## Development

### Adding New Contracts
1. Create a new directory in `contracts/`
2. Add a `Cargo.toml` file with workspace dependencies
3. Implement your contract in `src/lib.rs`
4. Add tests in `src/test.rs`
5. Update the workspace `Cargo.toml` to include the new contract

### Running in Different Networks
Replace `testnet` with your target network:
- `testnet` - Stellar testnet
- `mainnet` - Stellar mainnet
- `local` - Local development network

## Security Considerations

### Escrow Contract
- **Secret Management**: Keep secrets secure until ready to withdraw
- **Time Windows**: Ensure sufficient time for legitimate withdrawals
- **Token Approvals**: Verify token contracts before creating escrows
- **Amount Validation**: The contract validates non-negative amounts

### Factory Contract
- **Admin Control**: Factory admin can update escrow WASM
- **Salt Uniqueness**: Use unique salts to avoid deployment conflicts
- **WASM Verification**: Verify escrow WASM before setting in factory

## License

This project is licensed under the MIT License.