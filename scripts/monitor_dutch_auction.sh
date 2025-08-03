#!/usr/bin/env bash
set -euo pipefail

# Dutch Auction Price Monitor
# This script shows how the price changes during a Dutch auction

# Defaults
SOURCE_KEY="${SOURCE_KEY:-lion}"
NETWORK="${NETWORK:-testnet}"
LOP_CONTRACT=""
ORDER_FILE=""
INTERVAL=10  # seconds between checks
DURATION=3600  # total monitoring duration in seconds

show_usage() {
  cat <<EOF
Usage: $0 <lop_contract> <order_json_file> [options]

Arguments:
  lop_contract       LOP contract address
  order_json_file    Dutch auction order JSON file

Options:
  --source PROFILE   Signing profile (default: $SOURCE_KEY)
  --network NET      Network (default: $NETWORK)
  --interval SEC     Check interval in seconds (default: $INTERVAL)
  --duration SEC     Total monitoring duration (default: $DURATION)
  --simulate         Simulate price changes without real contract calls
  --help|-h          Show this help

Examples:
  $0 CLOP... example_dutch_auction_native.json
  $0 CLOP... example_dutch_auction_native.json --interval 5 --duration 1800
  $0 CLOP... example_dutch_auction_native.json --simulate
EOF
}

is_contract_id() { [[ "${1:-}" =~ ^C[0-9A-Z]{55,60}$ ]]; }

get_current_timestamp() {
  date +%s
}

format_price() {
  local price="$1"
  local decimals="${2:-7}"
  
  # Convert from smallest units to human readable
  if (( decimals > 0 )); then
    local divisor=$((10**decimals))
    echo "scale=4; $price / $divisor" | bc -l
  else
    echo "$price"
  fi
}

simulate_dutch_auction_price() {
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

monitor_auction() {
  local use_simulation="$1"
  
  # Parse order details
  local making_amount=$(jq -r '.making_amount' "$ORDER_FILE")
  local start_price=$(jq -r '.taking_amount_start' "$ORDER_FILE")
  local end_price=$(jq -r '.taking_amount_end' "$ORDER_FILE")
  local start_time=$(jq -r '.auction_start_time' "$ORDER_FILE")
  local end_time=$(jq -r '.auction_end_time' "$ORDER_FILE")
  
  echo "🎯 Dutch Auction Price Monitor"
  echo "==============================="
  echo "Making Amount: $(format_price "$making_amount") XLM"
  echo "Start Price: $(format_price "$start_price") USDC"
  echo "End Price: $(format_price "$end_price") USDC"
  echo "Start Time: $start_time ($(date -d "@$start_time" 2>/dev/null || echo "Invalid"))"
  echo "End Time: $end_time ($(date -d "@$end_time" 2>/dev/null || echo "Invalid"))"
  echo "Duration: $((end_time - start_time)) seconds"
  echo ""
  
  if [[ "$use_simulation" == "true" ]]; then
    echo "📊 SIMULATION MODE - Price changes over time:"
    echo "=============================================="
    
    # Show price changes every 10% of auction duration
    local total_duration=$((end_time - start_time))
    local step=$((total_duration / 10))
    
    for i in {0..10}; do
      local time_point=$((start_time + i * step))
      local current_price=$(simulate_dutch_auction_price "$making_amount" "$start_price" "$end_price" "$start_time" "$end_time" "$time_point")
      local progress=$((i * 10))
      
      echo "Time: $(date -d "@$time_point" '+%H:%M:%S' 2>/dev/null || echo "N/A") | Progress: ${progress}% | Price: $(format_price "$current_price") USDC"
    done
    return
  fi
  
  echo "📊 LIVE MONITORING - Press Ctrl+C to stop"
  echo "=========================================="
  printf "%-20s %-15s %-15s %-10s %-15s\n" "Time" "Current Price" "XLM/USDC Rate" "Progress" "Status"
  echo "--------------------------------------------------------------------------------"
  
  local start_monitor_time=$(get_current_timestamp)
  local end_monitor_time=$((start_monitor_time + DURATION))
  
  while (( $(get_current_timestamp) < end_monitor_time )); do
    local current_time=$(get_current_timestamp)
    local timestamp=$(date '+%H:%M:%S')
    
    # Get current price from contract
    local current_price=""
    if stellar contract invoke \
      --id "$LOP_CONTRACT" \
      --source "$SOURCE_KEY" \
      --network "$NETWORK" \
      -- get_current_price \
      --order "$(cat "$ORDER_FILE")" &>/dev/null; then
      
      current_price=$(stellar contract invoke \
        --id "$LOP_CONTRACT" \
        --source "$SOURCE_KEY" \
        --network "$NETWORK" \
        -- get_current_price \
        --order "$(cat "$ORDER_FILE")" 2>/dev/null | grep -o '[0-9]*' | head -1)
    fi
    
    if [[ -z "$current_price" ]]; then
      current_price="N/A"
      rate="N/A"
      status="ERROR"
    else
      # Calculate XLM/USDC rate
      local rate=$(echo "scale=4; $current_price / $making_amount" | bc -l)
      
      # Calculate progress
      local progress="N/A"
      local status="PENDING"
      
      if (( current_time < start_time )); then
        status="PENDING"
        progress="0%"
      elif (( current_time >= end_time )); then
        status="ENDED"
        progress="100%"
      else
        local elapsed=$((current_time - start_time))
        local total=$((end_time - start_time))
        progress="$((elapsed * 100 / total))%"
        status="ACTIVE"
      fi
    fi
    
    printf "%-20s %-15s %-15s %-10s %-15s\n" \
      "$timestamp" \
      "$(format_price "${current_price:-0}")" \
      "${rate:-N/A}" \
      "$progress" \
      "$status"
    
    sleep "$INTERVAL"
  done
}

# Parse arguments
USE_SIMULATION=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --source)
      SOURCE_KEY="$2"
      shift 2
      ;;
    --network)
      NETWORK="$2"
      shift 2
      ;;
    --interval)
      INTERVAL="$2"
      shift 2
      ;;
    --duration)
      DURATION="$2"
      shift 2
      ;;
    --simulate)
      USE_SIMULATION=true
      shift
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
      if [[ -z "$LOP_CONTRACT" ]]; then
        LOP_CONTRACT="$1"
      elif [[ -z "$ORDER_FILE" ]]; then
        ORDER_FILE="$1"
      else
        echo "Too many arguments"
        show_usage
        exit 1
      fi
      shift
      ;;
  esac
done

# Validate arguments
if [[ -z "$LOP_CONTRACT" || -z "$ORDER_FILE" ]]; then
  echo "Error: Both LOP contract address and order file are required"
  show_usage
  exit 1
fi

if ! is_contract_id "$LOP_CONTRACT"; then
  echo "Error: Invalid LOP contract address: $LOP_CONTRACT"
  exit 1
fi

if [[ ! -f "$ORDER_FILE" ]]; then
  echo "Error: Order file not found: $ORDER_FILE"
  exit 1
fi

# Check if bc is available for calculations
if ! command -v bc >/dev/null 2>&1; then
  echo "Error: 'bc' calculator is required but not installed"
  exit 1
fi

# Check if jq is available for JSON parsing
if ! command -v jq >/dev/null 2>&1; then
  echo "Error: 'jq' is required but not installed"
  exit 1
fi

# Start monitoring
monitor_auction "$USE_SIMULATION"