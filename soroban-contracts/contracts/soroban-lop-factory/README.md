# Soroban LOP Factory Contract

The LOP Factory is a factory contract that deploys and manages LOP (Limit Order Protocol) and Dutch auction contracts on Stellar.

## Contract Overview

This factory contract allows you to:
- Deploy LOP contracts with deterministic addresses
- Deploy Dutch auction contracts with deterministic addresses
- Predict contract addresses before deployment
- Manage WASM hashes for both contract types

## Deployment Information

### Factory Contract
- **Address**: `CDDPCTEKTGLMIJ2SGTDS6TWBWPK4LB47BGQHPIHX3AWCLQUNPE2B2LBY`
- **Alias**: `lop_factory`
- **Network**: Testnet
- **Deployed with**: `alice` source

### WASM Hashes
- **LOP Contract WASM Hash**: `b5f8b3315108593e18dbcd4a3fc36c40d4b4ba5b335ccc23de9d7ce1ce47ff02`
- **Dutch Auction Contract WASM Hash**: `0107b76b96aa652f3b5b47789d14a55fe3779938c55dfcde759c1b3a81ebddf8`

### Admin
- **Admin Address**: `GD4XRIZEWF7AI5XT5VOQFCGIZO3IYYJL6AORSUECCXSZTE3OBVWW74LA`

## Deployed Contract Examples

### LOP Contract
- **Salt**: `0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20`
- **Address**: `CDLWW5OUQZWE76WLYGKN6TCOG2UKOZ4HTOU5UN6RMNTXOCMDVWHE5UO4`
- **Associated Dutch Auction**: `CCHJNUGLRSGAOQM3UVBMLIVZERVNMCU6RLKRNIF2QYTZBEOQZ5PYTDYP` (auto-deployed)

### Standalone Dutch Auction Contract
- **Salt**: `0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f30`
- **Address**: `CAGW56C5VZBICKPHYITFBXAK2QM7TSMHCAMS73AK4QM7TSMHCAMS73AK4QM3VMDZJLATPDEA`

## Usage

### 1. Initialize the Factory (Already Done)
```bash
stellar contract invoke \
  --id lop_factory \
  --source lion \
  --network testnet \
  -- initialize \
  --admin GD4XRIZEWF7AI5XT5VOQFCGIZO3IYYJL6AORSUECCXSZTE3OBVWW74LA \
  --lop_wasm_hash b5f8b3315108593e18dbcd4a3fc36c40d4b4ba5b335ccc23de9d7ce1ce47ff02 \
  --dutch_auction_wasm_hash 0107b76b96aa652f3b5b47789d14a55fe3779938c55dfcde759c1b3a81ebddf8
```

### 2. Predict Contract Addresses
```bash
# Get LOP address before deployment
stellar contract invoke \
  --id lop_factory \
  --source lion \
  --network testnet \
  -- get_lop_address \
  --salt YOUR_SALT_HERE

# Get Dutch auction address before deployment
stellar contract invoke \
  --id lop_factory \
  --source lion \
  --network testnet \
  -- get_dutch_auction_address \
  --salt YOUR_SALT_HERE
```

### 3. Deploy LOP Contract
```bash
stellar contract invoke \
  --id lop_factory \
  --source lion \
  --network testnet \
  -- deploy_lop \
  --salt YOUR_UNIQUE_SALT \
  --admin YOUR_ADMIN_ADDRESS
```

**Note**: When you deploy a LOP contract, it automatically deploys an associated Dutch auction contract with a derived salt (SHA256 of the LOP salt).

### 4. Deploy Standalone Dutch Auction Contract
```bash
stellar contract invoke \
  --id lop_factory \
  --source lion \
  --network testnet \
  -- deploy_dutch_auction \
  --salt YOUR_UNIQUE_SALT
```

### 5. Query Factory Information
```bash
# Get current WASM hashes
stellar contract invoke \
  --id lop_factory \
  --source lion \
  --network testnet \
  -- get_lop_wasm_hash

stellar contract invoke \
  --id lop_factory \
  --source lion \
  --network testnet \
  -- get_dutch_auction_wasm_hash

# Get admin address
stellar contract invoke \
  --id lop_factory \
  --source lion \
  --network testnet \
  -- get_admin
```

### 6. Update WASM Hashes (Admin Only)
```bash
# Update LOP WASM hash
stellar contract invoke \
  --id lop_factory \
  --source lion \
  --network testnet \
  -- update_lop_wasm_hash \
  --new_wasm_hash NEW_HASH

# Update Dutch auction WASM hash
stellar contract invoke \
  --id lop_factory \
  --source lion \
  --network testnet \
  -- update_dutch_auction_wasm_hash \
  --new_wasm_hash NEW_HASH
```

## Important Notes

1. **Deterministic Addresses**: The factory uses deterministic deployment, so the same salt will always produce the same contract address.

2. **Salt Requirements**: 
   - Use unique salts for different contracts
   - Salts must be 32 bytes (64 hex characters)
   - Use different salts for LOP and Dutch auction deployments to avoid conflicts

3. **LOP-Dutch Auction Relationship**: 
   - Each LOP contract has an associated Dutch auction contract
   - The Dutch auction salt is derived from the LOP salt using SHA256
   - This ensures each LOP instance has its own dedicated Dutch auction

4. **Authorization**: Only the admin can update WASM hashes

## Contract Structure

```
Factory Contract
├── Deploy LOP Contract
│   └── Auto-deploy Dutch Auction (with derived salt)
└── Deploy Standalone Dutch Auction Contract
```

## Development

### Build
```bash
cd contracts/soroban-lop-factory
cargo build --target wasm32v1-none --release
```

### Test
```bash
cargo test
```

### Deploy New Version
```bash
stellar contract deploy \
  --wasm target/wasm32v1-none/release/soroban_lop_factory_contract.wasm \
  --source your_source \
  --network testnet \
  --alias your_alias
```

## Links

- [Factory Contract on Stellar Expert](https://stellar.expert/explorer/testnet/contract/CDDPCTEKTGLMIJ2SGTDS6TWBWPK4LB47BGQHPIHX3AWCLQUNPE2B2LBY)
- [Example LOP Contract](https://stellar.expert/explorer/testnet/contract/CDLWW5OUQZWE76WLYGKN6TCOG2UKOZ4HTOU5UN6RMNTXOCMDVWHE5UO4)
- [Example Dutch Auction Contract](https://stellar.expert/explorer/testnet/contract/CAGW56C5VZBICKPHYITFBXAK2QM7TSMHCAMS73AK4QM3VMDZJLATPDEA)