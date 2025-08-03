#!/usr/bin/env bash
set -euo pipefail

# LOP Dutch Auction Demo Script
# Shows how Dutch auction prices work with real examples

# Check dependencies
need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1"; exit 1; }; }
need bc; need jq

show_usage() {
  cat <<EOF
Usage: $0 [order_file] [options]

Arguments:
  order_file         Dutch auction order JSON file (optional)

Options:
  --current-time SEC Unix timestamp to simulate (default: now)
  --help|-h          Show this help

Examples:
  $0
  $0 example_dutch_auction_native.json
  $0 example_dutch_auction_native.json --current-time 1722601800
EOF
}

# Default order if none provided
create_demo_order() {
  cat <<EOF
{
  "salt": 67890,
  "maker": "GD4XRIZEWF7AI5XT5VOQFCGIZO3IYYJL6AORSUECCXSZTE3OBVWW74LA",
  "receiver": "GD4XRIZEWF7AI5XT5VOQFCGIZO3IYYJL6AORSUECCXSZTE3OBVWW74LA",
  "maker_asset": "CDLZFC3SYJYDZT7K67VZ75HPJVIEUVNIXF47ZG2FB2RMQQVU2HHGCYSC",
  "taker_asset": "CBIELTK6YBZJU5UP2WWQEUCYKLPU6AUNZ2BQ4WWFEIE3USCIHMXQDAMA",
  "making_amount": "10000000",
  "taking_amount": "0",
  "maker_traits": 1,
  "auction_start_time": 1722600000,
  "auction_end_time": 1722603600,
  "taking_amount_start": "50000000",
  "taking_amount_end": "20000000"
}
EOF
}

calculate_dutch_price() {
  local making_amount="$1"
  local start_price="$2"
  local end_price="$3"
  local start_time="$4"
  local end_time="$5"
  local current_time="$6"
  
  if (( current_time < start_time )); then
    echo "$start_price"
    return
  fi
  
  if (( current_time >= end_time )); then
    echo "$end_price"
    return
  fi
  
  # Linear interpolation
  local time_elapsed=$((current_time - start_time))
  local total_duration=$((end_time - start_time))
  local price_diff=$((end_price - start_price))
  
  local current_price=$((start_price + (time_elapsed * price_diff / total_duration)))
  echo "$current_price"
}

format_amount() {
  local amount="$1"
  local decimals="${2:-7}"
  
  if (( decimals > 0 )); then
    local divisor=$((10**decimals))
    echo "scale=4; $amount / $divisor" | bc -l
  else
    echo "$amount"
  fi
}

demo_dutch_auction() {
  local order_data="$1"
  local current_time="$2"
  
  # Parse order
  local making_amount=$(echo "$order_data" | jq -r '.making_amount')
  local start_price=$(echo "$order_data" | jq -r '.taking_amount_start')
  local end_price=$(echo "$order_data" | jq -r '.taking_amount_end')
  local start_time=$(echo "$order_data" | jq -r '.auction_start_time')
  local end_time=$(echo "$order_data" | jq -r '.auction_end_time')
  local maker_traits=$(echo "$order_data" | jq -r '.maker_traits')
  
  echo "🎯 Dutch Auction Price Analysis"
  echo "================================"
  echo ""
  
  # Order details
  echo "📋 Order Details:"
  echo "  Making Amount: $(format_amount "$making_amount") XLM"
  echo "  Starting Price: $(format_amount "$start_price") USDC (when auction begins)"
  echo "  Ending Price: $(format_amount "$end_price") USDC (when auction ends)"
  echo "  Auction Start: $start_time ($(date -d "@$start_time" 2>/dev/null || echo "Invalid date"))"
  echo "  Auction End: $end_time ($(date -d "@$end_time" 2>/dev/null || echo "Invalid date"))"
  echo "  Duration: $((end_time - start_time)) seconds ($(($(($end_time - $start_time)) / 60)) minutes)"
  echo "  Maker Traits: $maker_traits ($([ "$maker_traits" -eq 1 ] && echo "Dutch Auction Enabled" || echo "Regular Order"))"
  echo ""
  
  # Price progression
  echo "📊 Price Progression Over Time:"
  echo "Time Point          | Progress | Price (USDC)     | XLM/USDC Rate"
  echo "--------------------------------------------------------------------"
  
  # Show 11 points (0%, 10%, 20%, ..., 100%)
  for i in {0..10}; do
    local progress=$((i * 10))
    local time_point=$((start_time + (end_time - start_time) * i / 10))
    local price=$(calculate_dutch_price "$making_amount" "$start_price" "$end_price" "$start_time" "$end_time" "$time_point")
    local rate=$(echo "scale=4; $price / $making_amount" | bc -l)
    local time_str="$(date -d "@$time_point" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "Invalid")"
    
    printf "%-19s | %3d%%     | %15s | %s\n" \
      "$time_str" \
      "$progress" \
      "$(format_amount "$price")" \
      "$rate"
  done
  
  echo ""
  
  # Current price analysis
  echo "🕒 Current Time Analysis:"
  echo "  Current Time: $current_time ($(date -d "@$current_time" 2>/dev/null || echo "Invalid date"))"
  
  local current_price=$(calculate_dutch_price "$making_amount" "$start_price" "$end_price" "$start_time" "$end_time" "$current_time")
  local current_rate=$(echo "scale=4; $current_price / $making_amount" | bc -l)
  
  if (( current_time < start_time )); then
    echo "  Status: ⏳ AUCTION NOT STARTED"
    echo "  Price: $(format_amount "$current_price") USDC (starting price)"
    echo "  Time until start: $((start_time - current_time)) seconds"
  elif (( current_time >= end_time )); then
    echo "  Status: 🏁 AUCTION ENDED"
    echo "  Price: $(format_amount "$current_price") USDC (final price)"
    echo "  Time since end: $((current_time - end_time)) seconds"
  else
    local elapsed=$((current_time - start_time))
    local total=$((end_time - start_time))
    local progress_pct=$((elapsed * 100 / total))
    
    echo "  Status: 🔥 AUCTION ACTIVE"
    echo "  Progress: $progress_pct% complete"
    echo "  Current Price: $(format_amount "$current_price") USDC"
    echo "  Current Rate: $current_rate USDC per XLM"
    echo "  Time remaining: $((end_time - current_time)) seconds"
    echo "  Price decrease rate: $(echo "scale=8; ($start_price - $end_price) / $total" | bc -l) USDC per second"
  fi
  
  echo ""
  echo "💡 Key Insights:"
  echo "  • Price starts high and decreases linearly over time"
  echo "  • Total price drop: $(format_amount $((start_price - end_price))) USDC"
  echo "  • Percentage drop: $(echo "scale=2; ($start_price - $end_price) * 100 / $start_price" | bc -l)%"
  echo "  • Best for maker: Fill at start ($(format_amount "$start_price") USDC)"
  echo "  • Best for taker: Fill at end ($(format_amount "$end_price") USDC)"
}

# Parse arguments
ORDER_FILE=""
CURRENT_TIME=$(date +%s)

while [[ $# -gt 0 ]]; do
  case "$1" in
    --current-time)
      CURRENT_TIME="$2"
      shift 2
      ;;
    --help|-h)
      show_usage
      exit 0
      ;;
    -*)
      echo "Unknown option: $1"
      show_usage
      exit 1
      ;;
    *)
      ORDER_FILE="$1"
      shift
      ;;
  esac
done

# Get order data
if [[ -n "$ORDER_FILE" && -f "$ORDER_FILE" ]]; then
  ORDER_DATA=$(cat "$ORDER_FILE")
  echo "Using order file: $ORDER_FILE"
else
  ORDER_DATA=$(create_demo_order)
  echo "Using demo order (no file specified)"
fi

echo ""
demo_dutch_auction "$ORDER_DATA" "$CURRENT_TIME"
