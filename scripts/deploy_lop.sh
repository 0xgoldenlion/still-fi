#!/usr/bin/env bash
set -euo pipefail

#############################################
# Config
#############################################
FACTORY_ID="CDLWW5OUQZWE76WLYGKN6TCOG2UKOZ4HTOU5UN6RMNTXOCMDVWHE5UO4"
SOURCE_KEY="lion"
NETWORK="testnet"

ADMIN_ADDRESS="GD4XRIZEWF7AI5XT5VOQFCGIZO3IYYJL6AORSUECCXSZTE3OBVWW74LA"

#############################################
# Deps
#############################################
need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1" >&2; exit 1; }; }
need stellar; need openssl
if ! command -v sha256sum >/dev/null 2>&1 && ! command -v shasum >/dev/null 2>&1; then
  echo "Missing dependency: sha256sum or shasum" >&2; exit 1
fi

#############################################
# Functions
#############################################
is_contract_id() { [[ "$1" =~ ^C[0-9A-Z]{55,60}$ ]]; }

show_usage() {
  cat <<EOF
Usage:
  $0 [options]

Options:
  --salt SALT        Use specific salt (32-byte hex), otherwise generates random
  --admin ADDRESS    Admin address for the LOP contract (default: $ADMIN_ADDRESS)
  --source PROFILE   Signing profile (default: $SOURCE_KEY)
  --network NET      Network (default: $NETWORK)
  --help|-h          Show this help

Examples:
  $0
  $0 --salt a1b2c3d4e5f6789012345678901234567890abcdef1234567890abcdef123456
  $0 --admin GNEW... --source alice --network futurenet
EOF
}

#############################################
# Parse arguments
#############################################
SALT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --salt)
      SALT="$2"
      [[ ${#SALT} -eq 64 ]] || { echo "Salt must be 32 bytes (64 hex chars)"; exit 1; }
      shift 2
      ;;
    --admin)
      ADMIN_ADDRESS="$2"
      shift 2
      ;;
    --source)
      SOURCE_KEY="$2"
      shift 2
      ;;
    --network)
      NETWORK="$2"
      shift 2
      ;;
    --help|-h)
      show_usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      show_usage
      exit 1
      ;;
  esac
done

#############################################
# Generate salt if not provided
#############################################
if [[ -z "$SALT" ]]; then
  SALT="$(openssl rand -hex 32)"
  echo "Generated salt: $SALT"
else
  echo "Using provided salt: $SALT"
fi

echo "Admin address: $ADMIN_ADDRESS"
echo "Factory ID: $FACTORY_ID"
echo "Source: $SOURCE_KEY"
echo "Network: $NETWORK"

#############################################
# Deploy LOP contract via factory
#############################################
LOG_FILE="deploy_lop_$(date +%Y%m%d_%H%M%S).log"
echo "Deploying LOP contract via factory... (logging to $LOG_FILE)"

set +e
# Capture combined stdout+stderr and also tee to a file
RAW="$(
  stellar contract invoke \
    --id "$FACTORY_ID" \
    --source "$SOURCE_KEY" \
    --network "$NETWORK" \
    -- deploy_lop \
    --salt "$SALT" \
    --admin "$ADMIN_ADDRESS" 2>&1 | tee "$LOG_FILE"
)"
STATUS=${PIPESTATUS[0]}
set -e

echo
echo "----- Raw CLI combined output (also in $LOG_FILE) -----"
echo "$RAW"
echo "------------------------------------------------------"
echo

if [ $STATUS -ne 0 ]; then
  echo "❌ Deployment failed (exit $STATUS)."
  echo "Salt: $SALT"
  exit $STATUS
fi

#############################################
# Extract LOP address (similar to escrow script logic)
#############################################
LOP_ADDRESS=""

# 0A) Parse the event JSON: ... = {"address":"C..."}
if [ -z "$LOP_ADDRESS" ]; then
  CAND="$(echo "$RAW" \
    | awk -F'"address":"' '/deploy_lop/ && /"address":/ {split($2,a,"\""); print a[1]}' \
    | tail -n1)"
  if is_contract_id "${CAND:-}"; then LOP_ADDRESS="$CAND"; fi
fi

# 0B) Parse a standalone quoted result line: "C..."
if [ -z "$LOP_ADDRESS" ]; then
  CAND="$(echo "$RAW" | sed -n 's/^"\(C[0-9A-Z]\{55,60\}\)"/\1/p' | tail -n1)"
  if is_contract_id "${CAND:-}"; then LOP_ADDRESS="$CAND"; fi
fi

# 1) Factory event (string form) fallback
if [ -z "$LOP_ADDRESS" ]; then
  CAND="$(echo "$RAW" \
    | awk '/raised event/ && /deploy_lop/ {for(i=1;i<=NF;i++) if ($i ~ /^C[0-9A-Z]{55,60}$/) print $i}' \
    | tail -n1)"
  if is_contract_id "${CAND:-}"; then LOP_ADDRESS="$CAND"; fi
fi

# 2) "created from WASM" line
if [ -z "$LOP_ADDRESS" ]; then
  CAND="$(echo "$RAW" \
    | awk '/Contract .* created from WASM/ {for(i=1;i<=NF;i++) if ($i ~ /^C[0-9A-Z]{55,60}$/) print $i}' \
    | tail -n1)"
  if is_contract_id "${CAND:-}" && [ "$CAND" != "$FACTORY_ID" ]; then
    LOP_ADDRESS="$CAND"
  fi
fi

# 3) Arrow line: ... → C...
if [ -z "$LOP_ADDRESS" ]; then
  CAND="$(echo "$RAW" \
    | awk -F'→ ' '/→/ {print $2}' | awk '{print $1}' \
    | grep -E '^C[0-9A-Z]{55,60}$' | grep -v "$FACTORY_ID" \
    | tail -n1)"
  if is_contract_id "${CAND:-}"; then LOP_ADDRESS="$CAND"; fi
fi

# 4) Last C... that isn't factory
if [ -z "$LOP_ADDRESS" ]; then
  CAND="$(echo "$RAW" \
    | grep -oE 'C[0-9A-Z]{55,60}' \
    | grep -v "$FACTORY_ID" \
    | tail -n1)"
  if is_contract_id "${CAND:-}"; then LOP_ADDRESS="$CAND"; fi
fi

echo "✅ Parsed LOP address: ${LOP_ADDRESS:-unknown}"
echo "Salt: $SALT"
echo "Admin: $ADMIN_ADDRESS"
echo "Log file: $LOG_FILE"

#############################################
# Get Dutch auction address
#############################################
if [[ -n "$LOP_ADDRESS" && "$LOP_ADDRESS" != "unknown" ]]; then
  echo ""
  echo "Getting associated Dutch auction contract address..."
  DUTCH_AUCTION_ADDRESS="$(
    stellar contract invoke \
      --id "$LOP_ADDRESS" \
      --source "$SOURCE_KEY" \
      --network "$NETWORK" \
      -- get_dutch_auction_contract 2>/dev/null || echo "failed"
  )"
  
  if [[ "$DUTCH_AUCTION_ADDRESS" != "failed" ]]; then
    echo "✅ Dutch auction address: $DUTCH_AUCTION_ADDRESS"
  else
    echo "⚠️  Could not retrieve Dutch auction address"
  fi
fi

#############################################
# Save a summary file
#############################################
OUT_FILE="lop_deployment_details.txt"
cat > "$OUT_FILE" <<EOF
LOP Contract Address: ${LOP_ADDRESS:-unknown}
Dutch Auction Address: ${DUTCH_AUCTION_ADDRESS:-unknown}
Salt: $SALT
Admin: $ADMIN_ADDRESS
Factory: $FACTORY_ID
Network: $NETWORK
Source: $SOURCE_KEY

Deployment log: $LOG_FILE
EOF

echo ""
echo "Details saved to $OUT_FILE"

#############################################
# Show usage examples
#############################################
if [[ -n "$LOP_ADDRESS" && "$LOP_ADDRESS" != "unknown" ]]; then
  echo ""
  echo "🎉 Deployment successful!"
  echo ""
  echo "Next steps:"
  echo "1. Create an order JSON file:"
  echo "   ./interact_lop.sh create-order-json my_order.json"
  echo ""
  echo "2. Get contract info:"
  echo "   ./interact_lop.sh info $LOP_ADDRESS"
  echo ""
  echo "3. Fill an order:"
  echo "   ./interact_lop.sh fill-order $LOP_ADDRESS my_order.json GTAKER_ADDRESS"
  echo ""
  echo "4. Cancel an order:"
  echo "   ./interact_lop.sh cancel-order $LOP_ADDRESS my_order.json"
fi