#!/usr/bin/env bash
set -euo pipefail

# Defaults (can be overridden by flags or env)
SOURCE_KEY="${SOURCE_KEY:-lion}"
NETWORK="${NETWORK:-testnet}"

# --- helpers ---
need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1"; exit 1; }; }
need stellar; need grep; need awk; need sed

is_contract_id() { [[ "${1:-}" =~ ^C[0-9A-Z]{55,60}$ ]]; }
is_gaddr()       { [[ "${1:-}" =~ ^G[0-9A-Z]{55}$ ]]; }
is_hex64()       { [[ "${1:-}" =~ ^[0-9a-fA-F]{64}$ ]]; }

resolve_native_token() {
  stellar contract id asset --network "$NETWORK" --asset native 2>/dev/null \
    | grep -oE 'C[0-9A-Z]{55,60}' | head -n1
}

show_usage() {
  cat <<EOF
Usage:
  $0 [--source PROFILE] [--network {testnet|futurenet|mainnet}] <command> <args>

Flags (optional):
  --source   Signing profile/key (default: lion)
  --network  Network to use (default: testnet)

Commands:
  info <lop_contract>
  fill-order <lop_contract> <order_json_file> <taker_address>
  cancel-order <lop_contract> <order_json_file>
  get-order-state <lop_contract> <order_json_file>
  get-current-price <lop_contract> <order_json_file>
  get-admin <lop_contract>
  get-dutch-auction <lop_contract>
  create-order-json <output_file> [--dutch-auction]

Examples:
  $0 info CLOP...
  $0 --source maker --network testnet fill-order CLOP... order.json GTAKER...
  $0 cancel-order CLOP... order.json
  $0 create-order-json my_order.json --dutch-auction
EOF
}

create_order_template() {
  local output_file="$1"
  local is_dutch_auction="${2:-false}"
  
  if [[ "$is_dutch_auction" == "true" ]]; then
    cat > "$output_file" <<EOF
{
  "salt": 1,
  "maker": "GMAKER_ADDRESS_HERE",
  "receiver": "GRECEIVER_ADDRESS_HERE",
  "maker_asset": "CTOKEN_A_ADDRESS_HERE",
  "taker_asset": "CTOKEN_B_ADDRESS_HERE", 
  "making_amount": "1000",
  "taking_amount": "0",
  "maker_traits": 1,
  "auction_start_time": 1000,
  "auction_end_time": 2000,
  "taking_amount_start": "3000",
  "taking_amount_end": "1500"
}
EOF
    echo "Created Dutch auction order template: $output_file"
    echo "Note: maker_traits=1 enables Dutch auction mode"
  else
    cat > "$output_file" <<EOF
{
  "salt": 1,
  "maker": "GMAKER_ADDRESS_HERE",
  "receiver": "GRECEIVER_ADDRESS_HERE", 
  "maker_asset": "CTOKEN_A_ADDRESS_HERE",
  "taker_asset": "CTOKEN_B_ADDRESS_HERE",
  "making_amount": "1000",
  "taking_amount": "2000",
  "maker_traits": 0,
  "auction_start_time": 0,
  "auction_end_time": 0,
  "taking_amount_start": "0",
  "taking_amount_end": "0"
}
EOF
    echo "Created regular order template: $output_file"
    echo "Note: maker_traits=0 for regular orders"
  fi
}

# --- parse flags (stop at first non-flag) ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --source)  SOURCE_KEY="$2"; shift 2 ;;
    --network) NETWORK="$2"; shift 2 ;;
    --help|-h) show_usage; exit 0 ;;
    --) shift; break ;;
    -* ) echo "Unknown flag: $1"; show_usage; exit 1 ;;
    *  ) break ;;
  esac
done

# --- parse command ---
if [[ $# -lt 1 ]]; then show_usage; exit 1; fi
COMMAND="$1"; shift

case "$COMMAND" in
  info)
    if [[ $# -lt 1 ]]; then echo "info requires <lop_contract>"; exit 1; fi
    LOP_ADDRESS="$1"
    is_contract_id "$LOP_ADDRESS" || { echo "Invalid LOP contract address: $LOP_ADDRESS"; exit 1; }
    
    echo "Getting LOP contract information..."
    echo "Contract: $LOP_ADDRESS"
    echo ""
    
    echo "Admin:"
    stellar contract invoke \
      --id "$LOP_ADDRESS" \
      --source "$SOURCE_KEY" \
      --network "$NETWORK" \
      -- get_admin
    
    echo -e "\nDutch Auction Contract:"
    stellar contract invoke \
      --id "$LOP_ADDRESS" \
      --source "$SOURCE_KEY" \
      --network "$NETWORK" \
      -- get_dutch_auction_contract
    ;;

  fill-order)
    if [[ $# -lt 3 ]]; then echo "fill-order requires <lop_contract> <order_json_file> <taker_address>"; exit 1; fi
    LOP_ADDRESS="$1"; ORDER_FILE="$2"; TAKER_ADDRESS="$3"
    is_contract_id "$LOP_ADDRESS" || { echo "Invalid LOP contract address: $LOP_ADDRESS"; exit 1; }
    is_gaddr "$TAKER_ADDRESS" || { echo "Invalid taker address: $TAKER_ADDRESS"; exit 1; }
    [[ -f "$ORDER_FILE" ]] || { echo "Order file not found: $ORDER_FILE"; exit 1; }
    
    echo "Filling order from $ORDER_FILE with taker $TAKER_ADDRESS..."
    
    # Parse JSON and create Stellar CLI arguments
    ORDER_JSON=$(cat "$ORDER_FILE")
    
    stellar contract invoke \
      --id "$LOP_ADDRESS" \
      --source "$SOURCE_KEY" \
      --network "$NETWORK" \
      -- fill_order \
      --order "$(cat "$ORDER_FILE")" \
      --taker "$TAKER_ADDRESS"
    ;;

  cancel-order)
    if [[ $# -lt 2 ]]; then echo "cancel-order requires <lop_contract> <order_json_file>"; exit 1; fi
    LOP_ADDRESS="$1"; ORDER_FILE="$2"
    is_contract_id "$LOP_ADDRESS" || { echo "Invalid LOP contract address: $LOP_ADDRESS"; exit 1; }
    [[ -f "$ORDER_FILE" ]] || { echo "Order file not found: $ORDER_FILE"; exit 1; }
    
    echo "Cancelling order from $ORDER_FILE..."
    stellar contract invoke \
      --id "$LOP_ADDRESS" \
      --source "$SOURCE_KEY" \
      --network "$NETWORK" \
      -- cancel_order \
      --order "$(cat "$ORDER_FILE")"
    ;;

  get-order-state)
    if [[ $# -lt 2 ]]; then echo "get-order-state requires <lop_contract> <order_json_file>"; exit 1; fi
    LOP_ADDRESS="$1"; ORDER_FILE="$2"
    is_contract_id "$LOP_ADDRESS" || { echo "Invalid LOP contract address: $LOP_ADDRESS"; exit 1; }
    [[ -f "$ORDER_FILE" ]] || { echo "Order file not found: $ORDER_FILE"; exit 1; }
    
    echo "Getting order state for order in $ORDER_FILE..."
    stellar contract invoke \
      --id "$LOP_ADDRESS" \
      --source "$SOURCE_KEY" \
      --network "$NETWORK" \
      -- get_order_state \
      --order "$(cat "$ORDER_FILE")"
    ;;

  get-current-price)
    if [[ $# -lt 2 ]]; then echo "get-current-price requires <lop_contract> <order_json_file>"; exit 1; fi
    LOP_ADDRESS="$1"; ORDER_FILE="$2"
    is_contract_id "$LOP_ADDRESS" || { echo "Invalid LOP contract address: $LOP_ADDRESS"; exit 1; }
    [[ -f "$ORDER_FILE" ]] || { echo "Order file not found: $ORDER_FILE"; exit 1; }
    
    echo "Getting current price for order in $ORDER_FILE..."
    stellar contract invoke \
      --id "$LOP_ADDRESS" \
      --source "$SOURCE_KEY" \
      --network "$NETWORK" \
      -- get_current_price \
      --order "$(cat "$ORDER_FILE")"
    ;;

  get-admin)
    if [[ $# -lt 1 ]]; then echo "get-admin requires <lop_contract>"; exit 1; fi
    LOP_ADDRESS="$1"
    is_contract_id "$LOP_ADDRESS" || { echo "Invalid LOP contract address: $LOP_ADDRESS"; exit 1; }
    
    stellar contract invoke \
      --id "$LOP_ADDRESS" \
      --source "$SOURCE_KEY" \
      --network "$NETWORK" \
      -- get_admin
    ;;

  get-dutch-auction)
    if [[ $# -lt 1 ]]; then echo "get-dutch-auction requires <lop_contract>"; exit 1; fi
    LOP_ADDRESS="$1"
    is_contract_id "$LOP_ADDRESS" || { echo "Invalid LOP contract address: $LOP_ADDRESS"; exit 1; }
    
    stellar contract invoke \
      --id "$LOP_ADDRESS" \
      --source "$SOURCE_KEY" \
      --network "$NETWORK" \
      -- get_dutch_auction_contract
    ;;

  create-order-json)
    if [[ $# -lt 1 ]]; then echo "create-order-json requires <output_file>"; exit 1; fi
    OUTPUT_FILE="$1"; shift
    
    IS_DUTCH_AUCTION="false"
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --dutch-auction) IS_DUTCH_AUCTION="true"; shift ;;
        *) echo "Unknown option: $1"; exit 1 ;;
      esac
    done
    
    create_order_template "$OUTPUT_FILE" "$IS_DUTCH_AUCTION"
    ;;

  *)
    echo "Unknown command: $COMMAND"; show_usage; exit 1 ;;
esac