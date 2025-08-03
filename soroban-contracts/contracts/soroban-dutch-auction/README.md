# Soroban Dutch Auction Contract

A Dutch auction pricing mechanism implementation on Soroban that provides linear price interpolation for time-based auctions. This contract calculates current prices for Dutch auctions where the price decreases linearly over time.

## Overview

The Soroban Dutch Auction contract provides:
- **Linear price interpolation**: Calculate current auction prices based on time
- **Bidirectional calculations**: Calculate both taking and making amounts
- **Time-based pricing**: Automatic price adjustments based on auction duration
- **Arithmetic safety**: Overflow protection and validation

## Features

- ✅ Linear Dutch auction price calculation
- ✅ Time-based price interpolation
- ✅ Bidirectional amount calculations (taking/making)
- ✅ Comprehensive input validation
- ✅ Arithmetic overflow protection
- ✅ Pure calculation functions (no state storage)

## How Dutch Auctions Work

In a Dutch auction:
1. **Starting price**: High initial price that decreases over time
2. **Ending price**: Lower final price at auction end
3. **Linear decrease**: Price drops linearly between start and end times
4. **First bid wins**: First bidder at current price gets the item

## Contract Structure

### Main Functions

- `calculate_taking_amount()` - Calculate current price the taker must pay
- `calculate_making_amount()` - Calculate current amount the maker receives

### Price Calculation Logic

```
current_price = start_price - (price_difference × time_elapsed / total_duration)
```

Where:
- `price_difference = start_price - end_price`
- `time_elapsed = current_time - auction_start_time`
- `total_duration = auction_end_time - auction_start_time`

## Building the Contract

### Prerequisites

- Rust (latest stable version)
- Soroban CLI
- Stellar CLI

### Build Steps

```bash
# Navigate to the contract directory
cd soroban-dutch-auction

# Build the contract
make build

# Or build directly with cargo
cargo build --target wasm32-unknown-unknown --release
```

The compiled WASM file will be located at:
```
target/wasm32-unknown-unknown/release/soroban_dutch_auction_contract.wasm
```

## Deployment and Usage

### 1. Deploy the Contract

```bash
# Deploy to testnet
stellar contract deploy \
  --wasm target/wasm32-unknown-unknown/release/soroban_dutch_auction_contract.wasm \
  --source YOUR_SECRET_KEY \
  --network testnet
```

### 2. Calculate Taking Amount (Price Taker Pays)

```bash
stellar contract invoke \
  --id CONTRACT_ID \
  --source YOUR_SECRET_KEY \
  --network testnet \
  -- calculate_taking_amount \
  --making_amount 1000 \
  --taking_amount_start 5000 \
  --taking_amount_end 2000 \
  --auction_start_time 1703980800 \
  --auction_end_time 1703984400
```

### 3. Calculate Making Amount (Amount Maker Receives)

```bash
stellar contract invoke \
  --id CONTRACT_ID \
  --source YOUR_SECRET_KEY \
  --network testnet \
  -- calculate_making_amount \
  --taking_amount 3000 \
  --making_amount_start 500 \
  --making_amount_end 1000 \
  --auction_start_time 1703980800 \
  --auction_end_time 1703984400
```

## Detailed Function Reference

### `calculate_taking_amount`

Calculates how much the taker must pay at the current time.

**Parameters:**
- `making_amount: i128` - Amount the maker is offering
- `taking_amount_start: i128` - Initial price (higher)
- `taking_amount_end: i128` - Final price (lower)
- `auction_start_time: u64` - Unix timestamp when auction starts
- `auction_end_time: u64` - Unix timestamp when auction ends

**Returns:** `i128` - Current taking amount

**Behavior:**
- Before auction starts: Returns `taking_amount_start`
- After auction ends: Returns `taking_amount_end`
- During auction: Returns linearly interpolated price

### `calculate_making_amount`

Calculates how much the maker receives based on the taker's payment.

**Parameters:**
- `taking_amount: i128` - Amount the taker is paying
- `making_amount_start: i128` - Initial making amount (lower)
- `making_amount_end: i128` - Final making amount (higher)
- `auction_start_time: u64` - Unix timestamp when auction starts
- `auction_end_time: u64` - Unix timestamp when auction ends

**Returns:** `i128` - Current making amount

## Example Scenarios

### 1. NFT Dutch Auction

```bash
# NFT starting at 10 XLM, ending at 1 XLM over 1 hour
# Current time: 30 minutes into auction

stellar contract invoke \
  --id CONTRACT_ID \
  --network testnet \
  -- calculate_taking_amount \
  --making_amount 1 \
  --taking_amount_start 100000000 \  # 10 XLM (7 decimals)
  --taking_amount_end 10000000 \     # 1 XLM
  --auction_start_time 1703980800 \
  --auction_end_time 1703984400

# Expected result: ~55000000 (5.5 XLM) at 50% time elapsed
```

### 2. Token Sale Dutch Auction

```bash
# Token sale: 1000 tokens starting at 5 USDC each, ending at 2 USDC each

stellar contract invoke \
  --id CONTRACT_ID \
  --network testnet \
  -- calculate_taking_amount \
  --making_amount 10000000000 \      # 1000 tokens (7 decimals)
  --taking_amount_start 50000000000 \ # 5000 USDC total (7 decimals)
  --taking_amount_end 20000000000 \   # 2000 USDC total
  --auction_start_time 1703980800 \
  --auction_end_time 1703987200      # 2 hour auction
```

## Error Handling

### Error Codes

- `InvalidTimeRange` (1): `auction_end_time <= auction_start_time`
- `AuctionNotStarted` (2): Current time before auction start (unused in current logic)
- `InvalidAmountRange` (3): Invalid price range configuration
- `ArithmeticOverflow` (4): Calculation would cause integer overflow

### Validation Rules

1. **Time Range**: End time must be after start time
2. **Taking Amount Range**: Start amount must be higher than end amount
3. **Making Amount Range**: Start amount must be lower than end amount
4. **Arithmetic Safety**: All calculations checked for overflow

## Integration with LOP (Limit Order Protocol)

The Dutch auction contract is designed to work with the LOP contract:

```rust
// In LOP contract
let dutch_auction_client = dutch_auction::Client::new(&env, &dutch_auction_contract);
let current_price = dutch_auction_client.calculate_taking_amount(
    &order.making_amount,
    &order.taking_amount_start,
    &order.taking_amount_end,
    &order.auction_start_time,
    &order.auction_end_time,
);
```

## Testing

Run the test suite:

```bash
make test
```

The contract includes comprehensive tests covering:
- Basic price calculations
- Edge cases (before start, after end)
- Invalid inputs and error conditions
- Arithmetic overflow scenarios
- Linear interpolation accuracy

## Mathematical Examples

### Linear Interpolation Formula

For a 2-hour auction (7200 seconds) after 1 hour (3600 seconds):

```
Progress = 3600 / 7200 = 0.5 (50%)

If start_price = 1000 and end_price = 200:
price_difference = 1000 - 200 = 800
current_price = 1000 - (800 × 0.5) = 600
```

### Precision Considerations

- All calculations use integer arithmetic
- Division happens last to minimize precision loss
- Large numbers may cause overflow (protected by error handling)

## Gas Optimization

The contract is optimized for efficiency:
- **Pure functions**: No storage reads/writes
- **Minimal calculations**: Direct mathematical operations
- **Early returns**: Avoid calculations when possible
- **Integer arithmetic**: No floating-point operations

## Use Cases

### 1. DEX Order Books
- Dynamic pricing for limit orders
- Time-based price discovery
- Automated market making

### 2. NFT Marketplaces
- Dutch auction NFT sales
- Price discovery for unique assets
- Fair launch mechanisms

### 3. Token Sales
- ICO/IDO price mechanisms
- Fair token distribution
- Anti-frontrunning measures

### 4. Liquidation Systems
- Gradual price reduction for liquidations
- Risk management in DeFi protocols
- Collateral auction mechanisms

## Advanced Usage

### Custom Time Windows

```bash
# Short auction: 15 minutes
AUCTION_DURATION=900  # 15 minutes in seconds
START_TIME=$(date +%s)
END_TIME=$((START_TIME + AUCTION_DURATION))

stellar contract invoke \
  --id CONTRACT_ID \
  --network testnet \
  -- calculate_taking_amount \
  --making_amount 1000 \
  --taking_amount_start 5000 \
  --taking_amount_end 2000 \
  --auction_start_time $START_TIME \
  --auction_end_time $END_TIME
```

### Integration with Frontend

```javascript
// JavaScript integration example
import { Contract } from '@stellar/stellar-sdk';

const dutchAuction = new Contract(DUTCH_AUCTION_CONTRACT_ID);

async function getCurrentPrice(auctionParams) {
  const result = await dutchAuction.call(
    'calculate_taking_amount',
    auctionParams.makingAmount,
    auctionParams.takingAmountStart,
    auctionParams.takingAmountEnd,
    auctionParams.auctionStartTime,
    auctionParams.auctionEndTime
  );
  return result;
}

// Update UI with current price every second
setInterval(async () => {
  const currentPrice = await getCurrentPrice(auctionParams);
  updatePriceDisplay(currentPrice);
}, 1000);
```

## Security Considerations

- **Time manipulation**: Resistant to block timestamp manipulation within reasonable bounds
- **Integer overflow**: All arithmetic operations are checked
- **Input validation**: Comprehensive parameter validation
- **Pure functions**: No state modification reduces attack surface

## Performance Characteristics

- **Gas cost**: Low, constant-time operations
- **Scalability**: No storage usage, highly scalable
- **Latency**: Fast calculations, suitable for real-time pricing

## License

This project is licensed under the Apache License 2.0.