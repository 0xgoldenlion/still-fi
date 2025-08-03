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

parse_token_from_raw() {
  # read from stdin; match "token":"C..."
  cat | sed -n 's/.*"token"[^C]*\(C[0-9A-Z]\{55,60\}\).*/\1/p'
}
parse_amount_from_raw() {
  # read from stdin; prefer typed '"amount"sym: 123i128', fallback JSON "amount":"123"
  local input typed
  input="$(cat)"
  typed="$(echo "$input" | sed -n 's/.*"amount"sym:[[:space:]]*\([0-9]\+\)i128.*/\1/p' | tail -n1)"
  if [[ -n "$typed" ]]; then
    echo "$typed"
  else
    echo "$input" | sed -n 's/.*"amount"[[:space:]]*:[[:space:]]*"\([0-9]\+\)".*/\1/p' | tail -n1
  fi
}

show_usage() {
  cat <<EOF
Usage:
  $0 [--source PROFILE] [--network {testnet|futurenet|mainnet}] <command> <args>

Flags (optional):
  --source   Signing profile/key (default: lion)
  --network  Network to use (default: testnet)

Commands:
  info <escrow>
  withdraw <escrow> <secret-hex-64>
  cancel <escrow>
  fund <escrow> <maker_addr_G...> <amount_int> <token_id|native>
  fund-auto <escrow> <maker_addr_G...>   (reads amount+token from get_immutables)

Examples:
  $0 info CABC...
  $0 --source maker --network testnet fund-auto CABC... GMAKER...
  $0 fund CABC... GMAKER... 100000000 native
EOF
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
if [[ $# -lt 2 ]]; then show_usage; exit 1; fi
COMMAND="$1"; shift
ESCROW_ADDRESS="$1"; shift

case "$COMMAND" in
  info)
    echo "Getting information for escrow $ESCROW_ADDRESS (source=$SOURCE_KEY, net=$NETWORK)..."
    stellar contract invoke \
      --id "$ESCROW_ADDRESS" \
      --source "$SOURCE_KEY" \
      --network "$NETWORK" \
      -- get_immutables
    ;;

  withdraw)
    if [[ $# -lt 1 ]]; then echo "withdraw requires <secret-hex-64>"; exit 1; fi
    SECRET="$1"
    is_hex64 "$SECRET" || { echo "Secret must be 32-byte hex (64 hex chars)"; exit 1; }
    echo "Withdrawing from $ESCROW_ADDRESS..."
    stellar contract invoke \
      --id "$ESCROW_ADDRESS" \
      --source "$SOURCE_KEY" \
      --network "$NETWORK" \
      -- withdraw \
      --secret "$SECRET"
    ;;

  cancel)
    echo "Cancelling $ESCROW_ADDRESS..."
    stellar contract invoke \
      --id "$ESCROW_ADDRESS" \
      --source "$SOURCE_KEY" \
      --network "$NETWORK" \
      -- cancel
    ;;

  fund)
    if [[ $# -lt 3 ]]; then echo "fund requires <maker_addr> <amount> <token_id|native>"; exit 1; fi
    MAKER_ADDR="$1"; AMOUNT="$2"; TOKEN_IN="$3"
    is_gaddr "$MAKER_ADDR" || { echo "Invalid maker address: $MAKER_ADDR"; exit 1; }
    [[ "$AMOUNT" =~ ^[0-9]+$ ]] || { echo "Amount must be an integer in base units"; exit 1; }
    if [[ "$TOKEN_IN" == "native" ]]; then
      TOKEN_ADDRESS="$(resolve_native_token)"; [[ -n "$TOKEN_ADDRESS" ]] || { echo "Failed to resolve native token"; exit 1; }
    else
      TOKEN_ADDRESS="$TOKEN_IN"; is_contract_id "$TOKEN_ADDRESS" || { echo "Invalid token id: $TOKEN_ADDRESS"; exit 1; }
    fi
    echo "Funding $ESCROW_ADDRESS with $AMOUNT from $MAKER_ADDR via $TOKEN_ADDRESS (source=$SOURCE_KEY, net=$NETWORK)..."
    stellar contract invoke \
      --id "$TOKEN_ADDRESS" \
      --source "$SOURCE_KEY" \
      --network "$NETWORK" \
      -- transfer \
      --from "$MAKER_ADDR" \
      --to "$ESCROW_ADDRESS" \
      --amount "$AMOUNT"
    ;;

  fund-auto)
    if [[ $# -lt 1 ]]; then echo "fund-auto requires <maker_addr>"; exit 1; fi
    MAKER_ADDR="$1"
    is_gaddr "$MAKER_ADDR" || { echo "Invalid maker address: $MAKER_ADDR"; exit 1; }

    echo "Reading immutables (source=$SOURCE_KEY, net=$NETWORK)..."
    RAW="$(stellar -q contract invoke \
            --id "$ESCROW_ADDRESS" \
            --source "$SOURCE_KEY" \
            --network "$NETWORK" \
            -- get_immutables 2>/dev/null || true)"
    if [[ -z "$RAW" ]]; then
      RAW="$(stellar contract invoke \
              --id "$ESCROW_ADDRESS" \
              --source "$SOURCE_KEY" \
              --network "$NETWORK" \
              -- get_immutables 2>&1 || true)"
    fi
    echo "$RAW"

    if command -v jq >/dev/null 2>&1; then
      TOKEN_ADDRESS="$(echo "$RAW" | jq -r '..|.token? // empty' | head -n1)"
      AMOUNT="$(echo "$RAW" | jq -r '..|.amount? // empty' | head -n1)"
    else
      TOKEN_ADDRESS="$(echo "$RAW" | parse_token_from_raw | head -n1)"
      AMOUNT="$(echo "$RAW" | parse_amount_from_raw | head -n1)"
    fi

    is_contract_id "$TOKEN_ADDRESS" || { echo "Failed to parse token from immutables"; exit 1; }
    [[ "$AMOUNT" =~ ^[0-9]+$ ]] || { echo "Failed to parse amount from immutables"; exit 1; }

    echo "Funding $ESCROW_ADDRESS with $AMOUNT from $MAKER_ADDR via $TOKEN_ADDRESS..."
    stellar contract invoke \
      --id "$TOKEN_ADDRESS" \
      --source "$SOURCE_KEY" \
      --network "$NETWORK" \
      -- transfer \
      --from "$MAKER_ADDR" \
      --to "$ESCROW_ADDRESS" \
      --amount "$AMOUNT"
    ;;

  *)
    echo "Unknown command: $COMMAND"; show_usage; exit 1 ;;
esac
