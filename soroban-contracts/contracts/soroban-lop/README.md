# Soroban LOP (Limit Order Protocol) Contract

A comprehensive Limit Order Protocol implementation on Soroban that enables decentralized trading with support for both regular fixed-price orders and Dutch auction orders with dynamic pricing.

## Overview

The Soroban LOP contract provides:
- **Limit orders**: Create and fill fixed-price trading orders
- **Dutch auction integration**: Support for time-based dynamic pricing
- **Order management**: Full lifecycle management (create, fill, cancel)
- **Flexible trading**: Support for any Stellar tokens
- **Authorization system**: Secure multi-party order execution

## Features

- ✅ Fixed-price limit orders
- ✅ Dutch auction orders with dynamic pricing
- ✅ Order state management (Active, Filled, Cancelled)
- ✅ Secure authorization for makers and takers
- ✅ Flexible receiver designation
- ✅ Order hash-based tracking
- ✅ Event emission for order lifecycle
- ✅ Integration with Dutch auction contract

## How It Works

### Order Types

1. **Regular Orders**: Fixed exchange rate between two tokens
2. **Dutch Auction Orders**: Price decreases over time until filled

### Order Lifecycle

1. **Creation**: Order parameters are defined off-chain
2. **Submission**: Taker submits order to be filled
3. **Validation**: Contract validates order state and authorization
4. **Execution**: Tokens are exchanged between maker and taker/receiver
5. **Completion**: Order marked as filled, events emitted

## Contract Structure

### Core Data Types

```rust
pub struct Order {
    pub salt: u64,                    // Unique order identifier
    pub maker: Address,               // Order creator
    pub receiver: Address,            // Token recipient (can be taker)
    pub maker_asset: Address,         // Token maker is selling
    pub taker_asset: Address,         // Token maker wants to receive
    pub making_amount: i128,          // Amount maker is selling
    pub taking_amount: i128,          // Amount maker wants (fixed orders)
    pub maker_traits: u64,            // Order flags (Dutch auction, etc.)
    // Dutch auction parameters
    pub auction_start_time: u64,      // Auction start timestamp
    pub auction_end_time: u64,        // Auction end timestamp
    pub taking_amount_start: i128,    // Initial taking amount (high)
    pub taking_amount_end: i128,      // Final taking amount (low)
}
```

### Order States

- `Active`: Order can be filled
- `Filled`: Order has been executed
- `Cancelled`: Order was cancelled by maker

### Maker Traits Flags

- `IS_DUTCH_AUCTION` (1 << 0): Enable Dutch auction pricing
- `UNWRAP_WETH` (1 << 1): Reserved for future use
- `ALLOW_PARTIAL_FILLS` (1 << 2): Reserved for future use

## Building the Contract

### Prerequisites

- Rust (latest stable version)
- Soroban CLI
- Stellar CLI
- Built Dutch auction contract

### Build Steps

```bash
# First ensure Dutch auction contract is built
cd ../soroban-dutch-auction
make build

# Build the LOP contract
cd ../soroban-lop
make build

# Or build directly with cargo
cargo build --target wasm32-unknown-unknown --release
```

The compiled WASM file will be located at:
```
target/wasm32-unknown-unknown/release/soroban_lop_contract.wasm
```

## Deployment and Setup

### 1. Deploy Dutch Auction Contract (if not already deployed)

```bash
DUTCH_AUCTION_ID=$(stellar contract deploy \
  --wasm ../soroban-dutch-auction/target/wasm32-unknown-unknown/release/soroban_dutch_auction_contract.wasm \
  --source YOUR_SECRET_KEY \
  --network testnet)
```

### 2. Deploy LOP Contract

```bash
LOP_CONTRACT_ID=$(stellar contract deploy \
  --wasm target/wasm32-unknown-unknown/release/soroban_lop_contract.wasm \
  --source YOUR_SECRET_KEY \
  --network testnet)
```

### 3. Initialize LOP Contract

```bash
stellar contract invoke \
  --id $LOP_CONTRACT_ID \
  --source YOUR_SECRET_KEY \
  --network testnet \
  -- initialize \
  --admin YOUR_ADMIN_ADDRESS \
  --dutch_auction_contract $DUTCH_AUCTION_ID
```

## Usage Examples

### 1. Create and Fill a Regular Order

```bash
# Define order parameters
SALT=12345
MAKER_ADDRESS="GXXXXX..."
RECEIVER_ADDRESS="GYYYYY..."
TOKEN_A_ADDRESS="CAAAAA..."
TOKEN_B_ADDRESS="CBBBBB..."
MAKING_AMOUNT=1000000000    # 100 tokens (7 decimals)
TAKING_AMOUNT=2000000000    # 200 tokens (7 decimals)

# Fill the order (called by taker)
stellar contract invoke \
  --id $LOP_CONTRACT_ID \
  --source TAKER_SECRET_KEY \
  --network testnet \
  -- fill_order \
  --order '{
    "salt": '$SALT',
    "maker": "'$MAKER_ADDRESS'",
    "receiver": "'$RECEIVER_ADDRESS'",
    "maker_asset": "'$TOKEN_A_ADDRESS'",
    "taker_asset": "'$TOKEN_B_ADDRESS'",
    "making_amount": "'$MAKING_AMOUNT'",
    "taking_amount": "'$TAKING_AMOUNT'",
    "maker_traits": "0",
    "auction_start_time": "0",
    "auction_end_time": "0",
    "taking_amount_start": "0",
    "taking_amount_end": "0"
  }' \
  --taker TAKER_ADDRESS
```

### 2. Create and Fill a Dutch Auction Order

```bash
# Dutch auction parameters
AUCTION_START=$(date +%s)
AUCTION_END=$((AUCTION_START + 3600))  # 1 hour auction
TAKING_AMOUNT_START=5000000000         # Starting at 500 tokens
TAKING_AMOUNT_END=2000000000           # Ending at 200 tokens
MAKER_TRAITS=1                         # IS_DUTCH_AUCTION flag

# Fill Dutch auction order
stellar contract invoke \
  --id $LOP_CONTRACT_ID \
  --source TAKER_SECRET_KEY \
  --network testnet \
  -- fill_order \
  --order '{
    "salt": '$SALT',
    "maker": "'$MAKER_ADDRESS'",
    "receiver": "'$RECEIVER_ADDRESS'",
    "maker_asset": "'$TOKEN_A_ADDRESS'",
    "taker_asset": "'$TOKEN_B_ADDRESS'",
    "making_amount": "'$MAKING_AMOUNT'",
    "taking_amount": "0",
    "maker_traits": "'$MAKER_TRAITS'",
    "auction_start_time": "'$AUCTION_START'",
    "auction_end_time": "'$AUCTION_END'",
    "taking_amount_start": "'$TAKING_AMOUNT_START'",
    "taking_amount_end": "'$TAKING_AMOUNT_END'"
  }' \
  --taker TAKER_ADDRESS
```

### 3. Check Current Dutch Auction Price

```bash
stellar contract invoke \
  --id $LOP_CONTRACT_ID \
  --network testnet \
  -- get_current_price \
  --order '{
    "salt": '$SALT',
    "maker": "'$MAKER_ADDRESS'",
    "receiver": "'$RECEIVER_ADDRESS'",
    "maker_asset": "'$TOKEN_A_ADDRESS'",
    "taker_asset": "'$TOKEN_B_ADDRESS'",
    "making_amount": "'$MAKING_AMOUNT'",
    "taking_amount": "0",
    "maker_traits": "'$MAKER_TRAITS'",
    "auction_start_time": "'$AUCTION_START'",
    "auction_end_time": "'$AUCTION_END'",
    "taking_amount_start": "'$TAKING_AMOUNT_START'",
    "taking_amount_end": "'$TAKING_AMOUNT_END'"
  }'
```

### 4. Cancel an Order

```bash
# Only the maker can cancel their order
stellar contract invoke \
  --id $LOP_CONTRACT_ID \
  --source MAKER_SECRET_KEY \
  --network testnet \
  -- cancel_order \
  --order '{...}' # Same order structure as above
```

### 5. Check Order State

```bash
stellar contract invoke \
  --id $LOP_CONTRACT_ID \
  --network testnet \
  -- get_order_state \
  --order '{...}' # Same order structure as above

# Returns: "Active", "Filled", or "Cancelled"
```

## Detailed Function Reference

### `initialize(admin: Address, dutch_auction_contract: Address)`

Initialize the LOP contract with admin and Dutch auction contract addresses.

**Authorization:** None required (one-time setup)
**Parameters:**
- `admin`: Administrator address
- `dutch_auction_contract`: Address of deployed Dutch auction contract

### `fill_order(order: Order, taker: Address)`

Fill a limit order or Dutch auction order.

**Authorization:** Requires both maker and taker authorization
**Parameters:**
- `order`: Complete order structure
- `taker`: Address of the order taker

**Process:**
1. Validates order state (must be Active)
2. Calculates current price (fixed or Dutch auction)
3. Executes token transfers
4. Updates order state to Filled
5. Emits order_filled event

### `cancel_order(order: Order)`

Cancel an active order.

**Authorization:** Requires maker authorization
**Parameters:**
- `order`: Order to cancel

**Process:**
1. Validates caller is the maker
2. Checks order is not already filled/cancelled
3. Updates order state to Cancelled
4. Emits order_cancelled event

### `get_order_state(order: Order) -> OrderState`

Get the current state of an order.

**Authorization:** None required (read-only)
**Returns:** Active, Filled, or Cancelled

### `get_current_price(order: Order) -> i128`

Get the current taking amount for an order.

**Authorization:** None required (read-only)
**Returns:** 
- Fixed amount for regular orders
- Time-adjusted amount for Dutch auction orders

## Order Hash Calculation

Orders are identified by a hash of key parameters:
- Salt (uniqueness)
- Making amount
- Taking amount
- Maker traits

This ensures each order has a unique identifier while allowing off-chain order creation.

## Token Requirements

Before filling orders, ensure:

1. **Maker has sufficient balance** of maker_asset
2. **Taker has sufficient balance** of taker_asset
3. **Both parties have authorized** the LOP contract
4. **Tokens exist and are valid** Stellar assets

```bash
# Example: Authorize LOP contract to spend tokens
stellar contract invoke \
  --id TOKEN_CONTRACT_ID \
  --source MAKER_SECRET_KEY \
  --network testnet \
  -- approve \
  --from MAKER_ADDRESS \
  --spender $LOP_CONTRACT_ID \
  --amount 1000000000
```

## Advanced Usage

### Creating Orders Off-Chain

Orders can be created and signed off-chain, then submitted by any taker:

```javascript
// JavaScript example for order creation
const order = {
  salt: Math.floor(Math.random() * 1000000),
  maker: makerKeypair.publicKey(),
  receiver: receiverAddress,
  maker_asset: tokenA.contractId,
  taker_asset: tokenB.contractId,
  making_amount: "1000000000",
  taking_amount: "2000000000",
  maker_traits: "0", // Regular order
  auction_start_time: "0",
  auction_end_time: "0",
  taking_amount_start: "0",
  taking_amount_end: "0"
};

// Sign and distribute order for filling
```

### Dutch Auction Price Monitoring

```bash
#!/bin/bash
# Monitor Dutch auction price changes

ORDER_JSON='{"salt": 12345, ...}' # Your order JSON

while true; do
  PRICE=$(stellar contract invoke \
    --id $LOP_CONTRACT_ID \
    --network testnet \
    -- get_current_price \
    --order "$ORDER_JSON")
  
  echo "Current price: $PRICE"
  sleep 10
done
```

### Batch Order Operations

Multiple orders can be processed in sequence or parallel using scripts.

## Error Handling

### Error Codes

- `NotInitialized` (1): Contract not initialized
- `AlreadyInitialized` (2): Contract already initialized
- `NotAuthorized` (3): Insufficient authorization
- `OrderAlreadyFilled` (4): Order was already filled
- `OrderCancelled` (5): Order was cancelled
- `InsufficientBalance` (6): Insufficient token balance
- `InvalidOrder` (7): Order parameters invalid
- `DutchAuctionError` (8): Dutch auction calculation failed
- `TransferFailed` (9): Token transfer failed

### Common Issues

1. **Authorization failures**: Ensure both maker and taker authorize the contract
2. **Insufficient balances**: Check token balances before filling orders
3. **Invalid order state**: Orders can only be filled once
4. **Dutch auction errors**: Verify auction time parameters

## Integration with dApps

### Frontend Integration

```javascript
import { Contract, Keypair } from '@stellar/stellar-sdk';

const lopContract = new Contract(LOP_CONTRACT_ID);

class OrderBook {
  async fillOrder(order, takerKeypair) {
    const tx = lopContract.call('fill_order', order, takerKeypair.publicKey());
    tx.sign(takerKeypair);
    return await submitTransaction(tx);
  }

  async getOrderState(order) {
    return await lopContract.call('get_order_state', order);
  }

  async getCurrentPrice(order) {
    return await lopContract.call('get_current_price', order);
  }
}
```

### Market Making

```javascript
// Automated market maker example
class MarketMaker {
  async createSpreadOrders(tokenA, tokenB, spread) {
    const buyOrder = {
      // Buy tokenA with tokenB at lower price
      salt: generateSalt(),
      maker: this.keypair.publicKey(),
      receiver: this.keypair.publicKey(),
      maker_asset: tokenB.contractId,
      taker_asset: tokenA.contractId,
      making_amount: "1000000000",
      taking_amount: "950000000", // 5% below market
      maker_traits: "0"
    };

    const sellOrder = {
      // Sell tokenA for tokenB at higher price
      salt: generateSalt(),
      maker: this.keypair.publicKey(),
      receiver: this.keypair.publicKey(),
      maker_asset: tokenA.contractId,
      taker_asset: tokenB.contractId,
      making_amount: "1000000000",
      taking_amount: "1050000000", // 5% above market
      maker_traits: "0"
    };

    // Submit orders to the network
    await this.submitOrder(buyOrder);
    await this.submitOrder(sellOrder);
  }
}
```

## Security Considerations

- **Order uniqueness**: Use unique salts to prevent order replay
- **Authorization**: Always verify proper authorization before operations
- **Token approvals**: Ensure contracts have necessary token permissions
- **Front-running**: Consider using Dutch auctions for fair price discovery
- **MEV protection**: Order design helps mitigate some MEV strategies

## Performance and Gas Optimization

- **Order hashing**: Efficient hash-based order identification
- **Persistent storage**: TTL management for order states
- **Minimal storage**: Only essential data stored on-chain
- **Batch operations**: Support for multiple orders in single transaction

## Use Cases

### 1. Decentralized Exchange (DEX)
- Order book implementation
- Automated market making
- Cross-asset trading

### 2. DeFi Protocols
- Liquidation mechanisms
- Yield farming strategies
- Asset management

### 3. NFT Trading
- Fixed-price NFT sales
- Dutch auction NFT drops
- Collection trading

### 4. Token Sales
- ICO/IDO mechanisms
- Fair launch protocols
- Community token distribution

## Testing

Run the comprehensive test suite:

```bash
make test
```

Tests cover:
- Order creation and filling
- Dutch auction price calculations
- Order cancellation
- State management
- Error conditions
- Authorization scenarios

## Integration with Factory

The LOP contract is designed to work with the LOP Factory for easy deployment:

```bash
# Deploy via factory
stellar contract invoke \
  --id LOP_FACTORY_ID \
  --source YOUR_SECRET_KEY \
  --network testnet \
  -- deploy_lop \
  --salt UNIQUE_SALT \
  --admin ADMIN_ADDRESS
```

## License

This project is licensed under the Apache License 2.0.