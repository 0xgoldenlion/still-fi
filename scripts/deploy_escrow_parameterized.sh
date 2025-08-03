#!/usr/bin/env bash
set -euo pipefail

#############################################
# Usage and argument parsing
#############################################
usage() {
    echo "Usage: $0 <hashlock> <maker> <taker> <token> <amount> <cancellation_timestamp> [salt]"
    echo "Example: $0 abc123... GD4X... GD4X... CDLZ... 9000000 1754184950 [optional_salt]"
    exit 1
}

if [ $# -lt 6 ] || [ $# -gt 7 ]; then
    usage
fi

HASH="$1"
MAKER_ADDRESS="$2"
TAKER_ADDRESS="$3"
TOKEN_ADDRESS="$4"
AMOUNT="$5"
CANCELLATION_TIMESTAMP="$6"
SALT="${7:-$(openssl rand -hex 32)}"  # Use provided salt or generate one

#############################################
# Config (from environment or defaults)
#############################################
FACTORY_ID="${FACTORY_ID:-CACURHRDVGNUCFSMDWTIF6TABC76LNTAQYSIVDJK34P43OYOGPSGYDSO}"
SOURCE_KEY="${SOURCE_KEY:-lion}"
NETWORK="${NETWORK:-testnet}"

#############################################
# Deps
#############################################
need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1" >&2; exit 1; }; }
need stellar; need openssl

echo "Deploying escrow with parameters:"
echo "  Hashlock: $HASH"
echo "  Maker: $MAKER_ADDRESS"
echo "  Taker: $TAKER_ADDRESS"
echo "  Token: $TOKEN_ADDRESS"
echo "  Amount: $AMOUNT"
echo "  Cancellation timestamp: $CANCELLATION_TIMESTAMP"
echo "  Salt: $SALT"

#############################################
# Build immutables JSON
#############################################
IMM_FILE="$(mktemp -t immutables.XXXXXX.json)"
trap 'rm -f "$IMM_FILE"' EXIT

cat >"$IMM_FILE" <<EOF
{
  "hashlock": "$HASH",
  "maker": "$MAKER_ADDRESS",
  "taker": "$TAKER_ADDRESS",
  "token": "$TOKEN_ADDRESS",
  "amount": "$AMOUNT",
  "cancellation_timestamp": $CANCELLATION_TIMESTAMP
}
EOF

#############################################
# Invoke and capture output
#############################################
LOG_FILE="deploy_escrow_$(date +%Y%m%d_%H%M%S).log"
echo "Deploying escrow via factory... (logging to $LOG_FILE)"

set +e
RAW="$(
  stellar contract invoke \
    --id "$FACTORY_ID" \
    --source "$SOURCE_KEY" \
    --network "$NETWORK" \
    -- deploy_escrow \
    --immutables-file-path "$IMM_FILE" \
    --salt "$SALT" 2>&1 | tee "$LOG_FILE"
)"
STATUS=${PIPESTATUS[0]}
set -e

echo
echo "----- Raw CLI output -----"
echo "$RAW"
echo "-------------------------"
echo

if [ $STATUS -ne 0 ]; then
  echo "❌ Deployment failed (exit $STATUS)."
  exit $STATUS
fi

#############################################
# Extract escrow address
#############################################
is_contract_id() { [[ "$1" =~ ^C[0-9A-Z]{55,60}$ ]]; }

ESCROW_ADDRESS=""

# Parse the event JSON: … = {"address":"C…"}
if [ -z "$ESCROW_ADDRESS" ]; then
  CAND="$(echo "$RAW" \
    | awk -F'"address":"' '/deploy_escrow/ && /"address":/ {split($2,a,"\""); print a[1]}' \
    | tail -n1)"
  if is_contract_id "${CAND:-}"; then ESCROW_ADDRESS="$CAND"; fi
fi

# Parse a standalone quoted result line: "C…"
if [ -z "$ESCROW_ADDRESS" ]; then
  CAND="$(echo "$RAW" | sed -n 's/^"\(C[0-9A-Z]\{55,60\}\)"/\1/p' | tail -n1)"
  if is_contract_id "${CAND:-}"; then ESCROW_ADDRESS="$CAND"; fi
fi

# Factory event fallback
if [ -z "$ESCROW_ADDRESS" ]; then
  CAND="$(echo "$RAW" \
    | awk '/raised event/ && /deploy_escrow/ {for(i=1;i<=NF;i++) if ($i ~ /^C[0-9A-Z]{55,60}$/) print $i}' \
    | tail -n1)"
  if is_contract_id "${CAND:-}"; then ESCROW_ADDRESS="$CAND"; fi
fi

# "created from WASM" line
if [ -z "$ESCROW_ADDRESS" ]; then
  CAND="$(echo "$RAW" \
    | awk '/Contract .* created from WASM/ {for(i=1;i<=NF;i++) if ($i ~ /^C[0-9A-Z]{55,60}$/) print $i}' \
    | tail -n1)"
  if is_contract_id "${CAND:-}" && [ "$CAND" != "$FACTORY_ID" ] && [ "$CAND" != "$TOKEN_ADDRESS" ]; then
    ESCROW_ADDRESS="$CAND"
  fi
fi

# Arrow line: … → C…
if [ -z "$ESCROW_ADDRESS" ]; then
  CAND="$(echo "$RAW" \
    | awk -F'→ ' '/→/ {print $2}' | awk '{print $1}' \
    | grep -E '^C[0-9A-Z]{55,60}$' | grep -v -e "$FACTORY_ID" -e "$TOKEN_ADDRESS" \
    | tail -n1)"
  if is_contract_id "${CAND:-}"; then ESCROW_ADDRESS="$CAND"; fi
fi

# Last C… that isn't factory/token
if [ -z "$ESCROW_ADDRESS" ]; then
  CAND="$(echo "$RAW" \
    | grep -oE 'C[0-9A-Z]{55,60}' \
    | grep -v -e "$FACTORY_ID" -e "$TOKEN_ADDRESS" \
    | tail -n1)"
  if is_contract_id "${CAND:-}"; then ESCROW_ADDRESS="$CAND"; fi
fi

# Output the contract address (this will be captured by the calling code)
echo "\"${ESCROW_ADDRESS:-}\""

echo "✅ Escrow deployed at: ${ESCROW_ADDRESS:-unknown}" >&2
echo "Salt: $SALT" >&2
echo "Hash: $HASH" >&2
echo "Log file: $LOG_FILE" >&2