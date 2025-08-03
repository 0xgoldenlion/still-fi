#!/usr/bin/env bash
set -euo pipefail

# LOP + Escrow Atomic Swap Script
# This script deploys an escrow, funds it, and fills a LOP order atomically

# Factory address (only for escrow - LOP contract is already deployed)
ESCROW_FACTORY="CACURHRDVGNUCFSMDWTIF6TABC76LNTAQYSIVDJK34P43OYOGPSGYDSO"

# Defaults
SOURCE_KEY="${SOURCE_KEY:-lion}"
NETWORK="${NETWORK:-testnet}"

# Dependencies
need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1"; exit 1; }; }
need stellar; need openssl; need xxd; need jq

show_usage() {
  cat <<EOF
LOP + Escrow Atomic Swap Script
===============================

This script creates an atomic swap by:
1. Deploying a NEW escrow contract for this specific trade
2. Funding the escrow with the required taker asset amount
3. Filling an order on an EXISTING LOP contract

Usage:
  $0 <lop_contract> <order_json_file> [options]

Arguments:
  lop_contract       EXISTING LOP contract address (e.g., CDLWW5OUQZWE76WLYGKN6TCOG2UKOZ4HTOU5UN6RMNTXOCMDVWHE5UO4)
  order_json_file    JSON file containing the LOP order details

Options:
  --source PROFILE   Signing profile (default: $SOURCE_KEY)
  --network NET      Network (default: $NETWORK)
  --escrow-duration  Hours until escrow cancellation (default: 24)
  --dry-run          Show what would be done without executing
  --help|-h          Show this help

Example:
  $0 CDLWW5OUQZWE76WLYGKN6TCOG2UKOZ4HTOU5UN6RMNTXOCMDVWHE5UO4 example_order_native.json
  $0 CDLWW5OUQZWE76WLYGKN6TCOG2UKOZ4HTOU5UN6RMNTXOCMDVWHE5UO4 example_dutch_auction_native.json --escrow-duration 48

The script will:
- Parse the order to determine required amounts
- Deploy a NEW escrow for the taker asset amount (fresh contract per trade)
- Fund the escrow with the required taker asset
- Fill the order on the EXISTING LOP contract
- Provide withdrawal instructions for both parties

Note: Only the escrow is deployed fresh each time. The LOP contract is pre-deployed and reused.
EOF
}

is_contract_id() { [[ "${1:-}" =~ ^C[0-9A-Z]{55,60}$ ]]; }
is_gaddr() { [[ "${1:-}" =~ ^G[0-9A-Z]{55}$ ]]; }

resolve_native_token() {
  stellar contract id asset --network "$NETWORK" --asset native 2>/dev/null \
    | grep -oE 'C[0-9A-Z]{55,60}' | head -n1
}

generate_salt() {
  openssl rand -hex 32
}

generate_secret() {
  openssl rand -hex 32
}

hash_secret() {
  local secret="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    printf %s "$secret" | xxd -r -p | sha256sum | awk '{print $1}'
  else
    printf %s "$secret" | xxd -r -p | shasum -a 256 | awk '{print $1}'
  fi
}

parse_contract_address() {
  local raw_output="$1"
  local factory_id="$2"
  
  # Multiple strategies to extract contract address
  local address=""
  
  # Strategy 1: Parse event JSON
  address="$(echo "$raw_output" | awk -F'"address":"' '/"address":/ {split($2,a,"\""); print a[1]}' | tail -n1)"
  if is_contract_id "${address:-}"; then echo "$address"; return; fi
  
  # Strategy 2: Standalone quoted result
  address="$(echo "$raw_output" | sed -n 's/^"\(C[0-9A-Z]\{55,60\}\)"/\1/p' | tail -n1)"
  if is_contract_id "${address:-}"; then echo "$address"; return; fi
  
  # Strategy 3: Created from WASM
  address="$(echo "$raw_output" | awk '/Contract .* created from WASM/ {for(i=1;i<=NF;i++) if ($i ~ /^C[0-9A-Z]{55,60}$/) print $i}' | tail -n1)"
  if is_contract_id "${address:-}" && [ "$address" != "$factory_id" ]; then echo "$address"; return; fi
  
  # Strategy 4: Last C... that isn't factory
  address="$(echo "$raw_output" | grep -oE 'C[0-9A-Z]{55,60}' | grep -v "$factory_id" | tail -n1)"
  if is_contract_id "${address:-}"; then echo "$address"; return; fi
  
  echo ""
}

deploy_escrow() {
  local hashlock="$1"
  local maker="$2" 
  local taker="$3"
  local token="$4"
  local amount="$5"
  local cancellation_time="$6"
  local salt="$7"
  
  echo "🏗️  Deploying escrow contract..." >&2
  
  # Create immutables file
  local imm_file="$(mktemp -t immutables.XXXXXX.json)"
  cat > "$imm_file" <<EOF
{
  "hashlock": "$hashlock",
  "maker": "$maker",
  "taker": "$taker", 
  "token": "$token",
  "amount": "$amount",
  "cancellation_timestamp": $cancellation_time
}
EOF
  
  echo "  Immutables: $(cat "$imm_file")" >&2
  
  local raw_output
  raw_output="$(stellar contract invoke \
    --id "$ESCROW_FACTORY" \
    --source "$SOURCE_KEY" \
    --network "$NETWORK" \
    -- deploy_escrow \
    --immutables-file-path "$imm_file" \
    --salt "$salt" 2>&1)"
  
  rm -f "$imm_file"
  
  local escrow_address
  escrow_address="$(parse_contract_address "$raw_output" "$ESCROW_FACTORY")"
  
  if [[ -z "$escrow_address" ]]; then
    echo "❌ Failed to parse escrow address from output:" >&2
    echo "$raw_output" >&2
    exit 1
  fi
  
  echo "✅ Escrow deployed: $escrow_address" >&2
  echo "$escrow_address"
}

fund_escrow() {
  local escrow_address="$1"
  local funder="$2"
  local token="$3"
  local amount="$4"
  
  echo "💰 Funding escrow with $amount tokens..."
  
  stellar contract invoke \
    --id "$token" \
    --source "$SOURCE_KEY" \
    --network "$NETWORK" \
    -- transfer \
    --from "$funder" \
    --to "$escrow_address" \
    --amount "$amount"
    
  echo "✅ Escrow funded successfully"
}

fill_lop_order() {
  local lop_contract="$1"
  local order_file="$2"
  local taker="$3"
  
  echo "🔄 Filling LOP order..."
  
  stellar contract invoke \
    --id "$lop_contract" \
    --source "$SOURCE_KEY" \
    --network "$NETWORK" \
    -- fill_order \
    --order "$(cat "$order_file")" \
    --taker "$taker"
    
  echo "✅ LOP order filled successfully"
}

atomic_swap() {
  local lop_contract="$1"
  local order_file="$2"
  local escrow_duration_hours="$3"
  local dry_run="$4"
  
  echo "🎯 Starting LOP + Escrow Atomic Swap"
  echo "===================================="
  echo "LOP Contract (existing): $lop_contract"
  echo "Order File: $order_file"
  echo ""
  
  # Parse order details
  local order_data
  order_data="$(cat "$order_file")"
  
  local maker taker_asset taking_amount maker_asset making_amount
  maker="$(echo "$order_data" | jq -r '.maker')"
  taker_asset="$(echo "$order_data" | jq -r '.taker_asset')"
  taking_amount="$(echo "$order_data" | jq -r '.taking_amount')"
  maker_asset="$(echo "$order_data" | jq -r '.maker_asset')"
  making_amount="$(echo "$order_data" | jq -r '.making_amount')"
  
  # Current user acts as taker
  local current_user
  current_user="$(stellar keys address "$SOURCE_KEY" 2>/dev/null || echo "UNKNOWN")"
  
  echo "📋 Order Analysis:"
  echo "  Maker: $maker"
  echo "  Maker Asset: $maker_asset ($making_amount units)"
  echo "  Taker Asset: $taker_asset ($taking_amount units)"
  echo "  Current User (Taker): $current_user"
  
  # Calculate escrow parameters
  local cancellation_time
  cancellation_time="$(($(date +%s) + escrow_duration_hours * 3600))"
  
  local salt secret hashlock
  salt="$(generate_salt)"
  secret="$(generate_secret)"
  hashlock="$(hash_secret "$secret")"
  
  echo ""
  echo "🔐 Escrow Parameters (NEW escrow for this trade):"
  echo "  Salt: $salt"
  echo "  Secret: $secret"
  echo "  Hashlock: $hashlock"
  echo "  Cancellation: $cancellation_time ($(date -d "@$cancellation_time" 2>/dev/null || echo "Invalid"))"
  echo "  Duration: $escrow_duration_hours hours"
  
  if [[ "$dry_run" == "true" ]]; then
    echo ""
    echo "🔍 DRY RUN - Would execute:"
    echo "1. Deploy NEW escrow for $taking_amount units of $taker_asset"
    echo "2. Fund the new escrow from $current_user"
    echo "3. Fill order on EXISTING LOP contract: $lop_contract"
    echo "4. Maker gets $taking_amount of $taker_asset from escrow using secret"
    echo "5. Taker gets $making_amount of $maker_asset from LOP trade"
    echo ""
    echo "💡 Note: Each atomic swap creates a fresh escrow contract"
    echo "💡 Note: The LOP contract is reused across all trades"
    return
  fi
  
  echo ""
  echo "🚀 Executing atomic swap..."
  
  # Step 1: Deploy NEW escrow (fresh contract for this trade)
  local escrow_address
  escrow_address="$(deploy_escrow "$hashlock" "$current_user" "$maker" "$taker_asset" "$taking_amount" "$cancellation_time" "$salt")"
  
  # Step 2: Fund the new escrow
  fund_escrow "$escrow_address" "$current_user" "$taker_asset" "$taking_amount"
  
  # Step 3: Fill order on the EXISTING LOP contract
  fill_lop_order "$lop_contract" "$order_file" "$current_user"
  
  echo ""
  echo "🎉 ATOMIC SWAP COMPLETED!"
  echo "========================="
  echo ""
  echo "📋 Summary:"
  echo "  LOP Contract (existing): $lop_contract"
  echo "  Escrow Address (new): $escrow_address"
  echo "  Secret (for maker): $secret"
  echo "  Taker received: $making_amount units of $maker_asset"
  echo "  Maker can claim: $taking_amount units of $taker_asset"
  echo ""
  echo "📝 Next Steps:"
  echo ""
  echo "For MAKER ($maker):"
  echo "  Use this secret to withdraw from the NEW escrow:"
  echo "  ./scripts/interact_escrow.sh withdraw $escrow_address $secret"
  echo ""
  echo "For TAKER ($current_user):"
  echo "  Your tokens have been received automatically via LOP trade"
  echo ""
  echo "⚠️  Important:"
  echo "  • Share the secret with the maker: $secret"
  echo "  • Maker has $escrow_duration_hours hours to withdraw from escrow"
  echo "  • After cancellation time, taker can cancel escrow and recover funds"
  echo "  • The LOP trade is already complete and irreversible"
  echo ""
  
  # Save details to file
  local details_file="atomic_swap_$(date +%Y%m%d_%H%M%S).txt"
  cat > "$details_file" <<EOF
Atomic Swap Details
==================

LOP Contract (existing): $lop_contract
Escrow Address (new): $escrow_address
Order File: $order_file

Maker: $maker
Taker: $current_user

Maker Asset: $maker_asset ($making_amount units)
Taker Asset: $taker_asset ($taking_amount units)

Escrow Parameters:
- Salt: $salt
- Secret: $secret
- Hashlock: $hashlock
- Cancellation Time: $cancellation_time

Commands:
- Maker withdraw: ./scripts/interact_escrow.sh withdraw $escrow_address $secret
- Taker cancel (after timeout): ./scripts/interact_escrow.sh cancel $escrow_address
- Check escrow: ./scripts/interact_escrow.sh info $escrow_address
- Check LOP order state: ./interact_lop.sh get-order-state $lop_contract $order_file

Architecture:
- LOP Contract: Reused for all trades (shared infrastructure)
- Escrow Contract: Fresh deployment per atomic swap (isolated trades)
EOF
  
  echo "Details saved to: $details_file"
}

# Parse arguments
LOP_CONTRACT=""
ORDER_FILE=""
ESCROW_DURATION=24
DRY_RUN=false

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
    --escrow-duration)
      ESCROW_DURATION="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
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
  echo "Error: Both LOP contract and order file are required"
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

if ! [[ "$ESCROW_DURATION" =~ ^[0-9]+$ ]] || (( ESCROW_DURATION < 1 )); then
  echo "Error: Escrow duration must be a positive integer (hours)"
  exit 1
fi

# Execute atomic swap
atomic_swap "$LOP_CONTRACT" "$ORDER_FILE" "$ESCROW_DURATION" "$DRY_RUN"