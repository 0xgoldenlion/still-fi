# Soroban Escrow Contract

A Hash Time Lock Contract (HTLC) implementation on Soroban that enables secure, conditional token transfers between two parties using cryptographic hash locks and time-based cancellations.

## Overview

The Soroban Escrow Contract is a trustless escrow system that allows:
- **Maker**: Deposits tokens into the escrow with a hash lock
- **Taker**: Can withdraw tokens by providing the correct secret (preimage)
- **Time-based cancellation**: Maker can reclaim tokens after a specified timestamp if not withdrawn

## Features

- ✅ Hash-locked withdrawals (HTLC)
- ✅ Time-based cancellation mechanism
- ✅ Support for any Soroban token
- ✅ Immutable contract parameters for security
- ✅ Authorization checks for all operations

## Contract Structure

### Data Types

```rust
pub struct Immutables {
    pub hashlock: BytesN<32>,        // SHA-256 hash of the secret
    pub maker: Address,              // Address that deposits tokens
    pub taker: Address,              // Address that can withdraw tokens
    pub token: Address,              // Token contract address
    pub amount: i128,                // Amount of tokens escrowed
    pub cancellation_timestamp: u64, // Unix timestamp after which maker can cancel
}
```

### Main Functions

- `initialize(immutables: Immutables)` - Initialize the escrow (called once after deployment)
- `withdraw(secret: BytesN<32>)` - Withdraw tokens by providing the secret (taker only)
- `cancel()` - Cancel escrow and return tokens to maker (after cancellation time)
- `get_immutables()` - Get the immutable parameters of the escrow

## Building the Contract

### Prerequisites

- Rust (latest stable version)
- Soroban CLI
- Stellar CLI

### Build Steps

```bash
# Navigate to the contract directory
cd soroban-escrow

# Build the contract
make build

# Or build directly with cargo
cargo build --target wasm32-unknown-unknown --release
```

The compiled WASM file will be located at:
```
target/wasm32-unknown-unknown/release/soroban_escrow_contract.wasm
```

## Deployment and Usage

### 1. Deploy the Contract

```bash
# Deploy to testnet
stellar contract deploy \
  --wasm target/wasm32-unknown-unknown/release/soroban_escrow_contract.wasm \
  --source YOUR_SECRET_KEY \
  --network testnet
```

### 2. Initialize the Escrow

The contract must be initialized immediately after deployment with the immutable parameters:

```bash
stellar contract invoke \
  --id CONTRACT_ID \
  --source DEPLOYER_SECRET_KEY \
  --network testnet \
  -- initialize \
  --immutables '{
    "hashlock": "YOUR_32_BYTE_HASH",
    "maker": "MAKER_ADDRESS",
    "taker": "TAKER_ADDRESS", 
    "token": "TOKEN_CONTRACT_ADDRESS",
    "amount": "1000000000",
    "cancellation_timestamp": "1703980800"
  }'
```

### 3. Fund the Escrow

The maker needs to transfer tokens to the escrow contract:

```bash
stellar contract invoke \
  --id TOKEN_CONTRACT_ID \
  --source MAKER_SECRET_KEY \
  --network testnet \
  -- transfer \
  --from MAKER_ADDRESS \
  --to ESCROW_CONTRACT_ADDRESS \
  --amount 1000000000
```

### 4. Withdraw (Taker)

The taker can withdraw by providing the correct secret:

```bash
stellar contract invoke \
  --id ESCROW_CONTRACT_ID \
  --source TAKER_SECRET_KEY \
  --network testnet \
  -- withdraw \
  --secret YOUR_32_BYTE_SECRET
```

### 5. Cancel (Maker, after timeout)

If the taker doesn't withdraw before the cancellation timestamp, the maker can cancel:

```bash
stellar contract invoke \
  --id ESCROW_CONTRACT_ID \
  --source MAKER_SECRET_KEY \
  --network testnet \
  -- cancel
```

## Example Workflow

```bash
# 1. Generate a secret and its hash
SECRET="2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a"
HASH=$(echo -n $SECRET | sha256sum | cut -d' ' -f1)

# 2. Deploy and initialize escrow
stellar contract deploy --wasm escrow.wasm --network testnet
stellar contract invoke --id $CONTRACT_ID -- initialize --immutables '{...}'

# 3. Maker funds the escrow
stellar contract invoke --id $TOKEN_ID -- transfer --from $MAKER --to $CONTRACT_ID --amount 1000

# 4. Share the hash with taker (keep secret private)
echo "Hash: $HASH"

# 5. Taker withdraws using the secret
stellar contract invoke --id $CONTRACT_ID -- withdraw --secret $SECRET
```

## Security Considerations

- **One-time use**: Each escrow can only be used once
- **Immutable parameters**: Cannot be changed after initialization
- **Hash verification**: Only the correct secret will unlock the funds
- **Time limits**: Maker can always reclaim after timeout
- **Authorization**: All operations require proper signatures

## Error Codes

- `AlreadyInitialized` (1): Contract is already initialized
- `NotInitialized` (2): Contract not yet initialized  
- `InvalidSecret` (3): Provided secret doesn't match hash
- `NotAuthorized` (4): Caller not authorized for this operation
- `TimePredicateNotMet` (5): Time conditions not satisfied
- `NegativeAmount` (6): Invalid negative amount

## Testing

Run the test suite:

```bash
make test
```

## Use Cases

- **Atomic swaps**: Cross-chain or cross-asset swaps
- **Payment channels**: Conditional payments
- **Betting/gambling**: Trustless wagers
- **Service payments**: Pay on delivery/completion
- **Dispute resolution**: Time-locked settlements

## License

This project is licensed under the Apache License 2.0.