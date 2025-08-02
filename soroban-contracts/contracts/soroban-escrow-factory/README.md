# Soroban Escrow Factory Contract

A factory contract for deploying and managing Soroban Escrow contracts with deterministic addresses. This factory enables efficient deployment of multiple escrow instances while maintaining predictable contract addresses.

## Overview

The Soroban Escrow Factory provides:
- **Deterministic deployment**: Deploy escrow contracts with predictable addresses
- **Centralized management**: Single point for deploying and tracking escrow contracts
- **Upgradeable WASM**: Admin can update the escrow contract implementation
- **Gas efficiency**: Reuse uploaded WASM bytecode for multiple deployments

## Features

- ✅ Deploy multiple escrow contracts with unique salts
- ✅ Predict escrow addresses before deployment
- ✅ Admin-controlled escrow WASM hash updates
- ✅ Event emission for deployment tracking
- ✅ Built-in authorization and access controls

## Contract Structure

### Main Functions

- `initialize(admin: Address, escrow_wasm_hash: BytesN<32>)` - Initialize factory with admin and escrow WASM
- `deploy_escrow(immutables: Immutables, salt: BytesN<32>)` - Deploy new escrow contract
- `get_escrow_address(salt: BytesN<32>)` - Get deterministic address without deploying
- `update_escrow_wasm_hash(new_wasm_hash: BytesN<32>)` - Update escrow WASM (admin only)
- `get_escrow_wasm_hash()` - Get current escrow WASM hash
- `get_admin()` - Get admin address

## Building the Factory

### Prerequisites

- Rust (latest stable version)
- Soroban CLI
- Stellar CLI
- Built escrow contract WASM

### Build Steps

```bash
# First, build the escrow contract dependency
cd ../soroban-escrow
make build

# Then build the factory
cd ../soroban-escrow-factory
make build

# Or build directly with cargo
cargo build --target wasm32-unknown-unknown --release
```

The compiled WASM file will be located at:
```
target/wasm32-unknown-unknown/release/soroban_escrow_factory.wasm
```

## Deployment and Setup

### 1. Upload Escrow Contract WASM

First, upload the escrow contract WASM to get its hash:

```bash
# Upload escrow WASM to get hash
ESCROW_WASM_HASH=$(stellar contract install \
  --wasm ../soroban-escrow/target/wasm32-unknown-unknown/release/soroban_escrow_contract.wasm \
  --source YOUR_SECRET_KEY \
  --network testnet)

echo "Escrow WASM Hash: $ESCROW_WASM_HASH"
```

### 2. Deploy Factory Contract

```bash
# Deploy the factory contract
FACTORY_CONTRACT_ID=$(stellar contract deploy \
  --wasm target/wasm32-unknown-unknown/release/soroban_escrow_factory.wasm \
  --source YOUR_SECRET_KEY \
  --network testnet)

echo "Factory Contract ID: $FACTORY_CONTRACT_ID"
```

### 3. Initialize the Factory

Initialize the factory with admin address and escrow WASM hash:

```bash
stellar contract invoke \
  --id $FACTORY_CONTRACT_ID \
  --source YOUR_SECRET_KEY \
  --network testnet \
  -- initialize \
  --admin YOUR_ADDRESS \
  --escrow_wasm_hash $ESCROW_WASM_HASH
```

## Using the Factory

### 1. Deploy an Escrow Contract

```bash
# Generate a unique salt (32 bytes)
SALT=$(openssl rand -hex 32)

# Deploy escrow via factory
stellar contract invoke \
  --id $FACTORY_CONTRACT_ID \
  --source YOUR_SECRET_KEY \
  --network testnet \
  -- deploy_escrow \
  --immutables '{
    "hashlock": "YOUR_32_BYTE_HASH",
    "maker": "MAKER_ADDRESS", 
    "taker": "TAKER_ADDRESS",
    "token": "TOKEN_CONTRACT_ADDRESS",
    "amount": "1000000000",
    "cancellation_timestamp": "1703980800"
  }' \
  --salt $SALT
```

### 2. Predict Escrow Address

Get the address of an escrow before deploying it:

```bash
stellar contract invoke \
  --id $FACTORY_CONTRACT_ID \
  --source YOUR_SECRET_KEY \
  --network testnet \
  -- get_escrow_address \
  --salt $SALT
```

### 3. Update Escrow WASM (Admin Only)

If you need to upgrade the escrow contract implementation:

```bash
# Upload new escrow WASM
NEW_ESCROW_WASM_HASH=$(stellar contract install \
  --wasm new_escrow_contract.wasm \
  --source ADMIN_SECRET_KEY \
  --network testnet)

# Update factory to use new WASM
stellar contract invoke \
  --id $FACTORY_CONTRACT_ID \
  --source ADMIN_SECRET_KEY \
  --network testnet \
  -- update_escrow_wasm_hash \
  --new_wasm_hash $NEW_ESCROW_WASM_HASH
```

## Complete Example Workflow

Here's a complete example of setting up and using the factory:

```bash
#!/bin/bash

# Configuration
ADMIN_SECRET="YOUR_ADMIN_SECRET_KEY"
USER_SECRET="USER_SECRET_KEY"
NETWORK="testnet"

# 1. Upload escrow contract WASM
echo "Uploading escrow WASM..."
ESCROW_WASM_HASH=$(stellar contract install \
  --wasm ../soroban-escrow/target/wasm32-unknown-unknown/release/soroban_escrow_contract.wasm \
  --source $ADMIN_SECRET \
  --network $NETWORK)

# 2. Deploy factory contract
echo "Deploying factory contract..."
FACTORY_ID=$(stellar contract deploy \
  --wasm target/wasm32-unknown-unknown/release/soroban_escrow_factory.wasm \
  --source $ADMIN_SECRET \
  --network $NETWORK)

# 3. Initialize factory
echo "Initializing factory..."
stellar contract invoke \
  --id $FACTORY_ID \
  --source $ADMIN_SECRET \
  --network $NETWORK \
  -- initialize \
  --admin "ADMIN_ADDRESS" \
  --escrow_wasm_hash $ESCROW_WASM_HASH

# 4. Generate secret and hash for escrow
SECRET=$(openssl rand -hex 32)
HASH=$(echo -n $SECRET | xxd -r -p | sha256sum | cut -d' ' -f1)
SALT=$(openssl rand -hex 32)

# 5. Deploy escrow contract
echo "Deploying escrow contract..."
ESCROW_ADDRESS=$(stellar contract invoke \
  --id $FACTORY_ID \
  --source $USER_SECRET \
  --network $NETWORK \
  -- deploy_escrow \
  --immutables "{
    \"hashlock\": \"$HASH\",
    \"maker\": \"MAKER_ADDRESS\",
    \"taker\": \"TAKER_ADDRESS\", 
    \"token\": \"TOKEN_ADDRESS\",
    \"amount\": \"1000000000\",
    \"cancellation_timestamp\": \"$(date -d '+1 day' +%s)\"
  }" \
  --salt $SALT)

echo "Escrow deployed at: $ESCROW_ADDRESS"
echo "Secret (keep safe): $SECRET"
echo "Hash: $HASH"
```

## Deterministic Addresses

The factory uses Soroban's deterministic deployment feature. For the same factory contract and salt, you'll always get the same escrow address:

```
escrow_address = hash(factory_address + salt + escrow_wasm_hash)
```

This enables:
- **Predictable addresses**: Know escrow address before deployment
- **Cross-chain coordination**: Same addresses on different networks
- **State channels**: Off-chain address computation

## Admin Functions

### Check Factory Status

```bash
# Get current admin
stellar contract invoke \
  --id $FACTORY_CONTRACT_ID \
  --network testnet \
  -- get_admin

# Get current escrow WASM hash
stellar contract invoke \
  --id $FACTORY_CONTRACT_ID \
  --network testnet \
  -- get_escrow_wasm_hash
```

### Transfer Admin Rights

To transfer admin rights, deploy a new factory or implement an admin transfer function in a future version.

## Error Codes

- `NotInitialized` (1): Factory not yet initialized
- `AlreadyInitialized` (2): Factory already initialized
- `NotAuthorized` (3): Caller not authorized (admin only function)
- `DeploymentFailed` (4): Escrow deployment or initialization failed

## Events

The factory emits the following events:

- `deploy_escrow`: Emitted when an escrow is successfully deployed
  - Data: `escrow_address`

## Gas Optimization

The factory pattern provides several gas optimizations:
- **Shared WASM**: Upload escrow WASM once, deploy many times
- **No constructor args**: Deploys contracts without constructor parameters
- **Batch operations**: Can deploy multiple escrows in a single transaction

## Security Considerations

- **Admin privileges**: Admin can update escrow WASM, affecting future deployments
- **Salt uniqueness**: Use unique salts to avoid deployment conflicts
- **WASM verification**: Verify escrow WASM hash before updating
- **Access control**: Only admin can update critical factory parameters

## Testing

Run the test suite:

```bash
make test
```

## Use Cases

- **DEX protocols**: Deploy escrow contracts for atomic swaps
- **Payment processors**: Create escrows for conditional payments
- **Gaming platforms**: Deploy escrows for wagers and tournaments
- **Service marketplaces**: Create escrows for service payments
- **Cross-chain bridges**: Deploy escrows for asset transfers

## Integration with Frontend

Example JavaScript integration:

```javascript
import { Contract, Keypair } from '@stellar/stellar-sdk';

const factory = new Contract(FACTORY_CONTRACT_ID);

// Deploy new escrow
async function deployEscrow(immutables, salt) {
  const tx = factory.call('deploy_escrow', immutables, salt);
  // Sign and submit transaction
  return await submitTransaction(tx);
}

// Get escrow address
async function getEscrowAddress(salt) {
  return await factory.call('get_escrow_address', salt);
}
```

## License

This project is licensed under the Apache License 2.0.