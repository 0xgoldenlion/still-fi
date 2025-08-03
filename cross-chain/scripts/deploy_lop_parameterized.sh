#!/usr/bin/env bash
set -euo pipefail

#############################################
# Usage and argument parsing
#############################################
usage() {
    echo "Usage: $0 <admin_address> [salt]"
    echo "Example: $0 GD4X... [optional_salt]"
    exit 1
}

if [ $# -lt 1 ] || [ $# -gt 2 ]; then
    usage
fi

ADMIN_ADDRESS="$1"
SALT="${2:-$(openssl rand -hex 32)}"  # Use provided salt or generate one

#############################################
# Config (from environment or defaults)
#############################################
FACTORY_ID="${LOP_FACTORY_ID:-CDLWW5OUQZWE76WLYGKN6TCOG2UKOZ4HTOU5UN6RMNTXOCMDVWHE5UO4}"
SOURCE_KEY="${SOURCE_KEY:-lion}"
NETWORK="${NETWORK:-testnet}"

#############################################
# Deps
#############################################
need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1" >&2; exit 1; }; }
need stellar; need openssl

is_contract_id() { [[ "$1" =~ ^C[0-9A-Z]{55,60}$ ]]; }

echo "Deploying LOP with parameters:"
echo "  Admin: $ADMIN_ADDRESS"
echo "  Salt: $SALT"
echo "  Factory: $FACTORY_ID"

#############################################
# Deploy LOP contract via factory
#############################################
LOG_FILE="deploy_lop_$(date +%Y%m%d_%H%M%S).log"
echo "Deploying LOP contract via factory... (logging to $LOG_FILE)"

set +e
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
echo "----- Raw CLI output -----"
echo "$RAW"
echo "-------------------------"
echo

if [ $STATUS -ne 0 ]; then
  echo "❌ Deployment failed (exit $STATUS)."
  exit $STATUS
fi

#############################################
# Extract LOP address
#############################################
LOP_ADDRESS=""

# Parse the event JSON: … = {"address":"C…"}
if [ -z "$LOP_ADDRESS" ]; then
  CAND="$(echo "$RAW" \
    | awk -F'"address":"' '/deploy_lop/ && /"address":/ {split($2,a,"\""); print a[1]}' \
    | tail -n1)"
  if is_contract_id "${CAND:-}"; then LOP_ADDRESS="$CAND"; fi
fi

# Parse a standalone quoted result line: "C…"
if [ -z "$LOP_ADDRESS" ]; then
  CAND="$(echo "$RAW" | sed -n 's/^"\(C[0-9A-Z]\{55,60\}\)"/\1/p' | tail -n1)"
  if is_contract_id "${CAND:-}"; then LOP_ADDRESS="$CAND"; fi
fi

# Factory event fallback
if [ -z "$LOP_ADDRESS" ]; then
  CAND="$(echo "$RAW" \
    | awk '/raised event/ && /deploy_lop/ {for(i=1;i<=NF;i++) if ($i ~ /^C[0-9A-Z]{55,60}$/) print $i}' \
    | tail -n1)"
  if is_contract_id "${CAND:-}"; then LOP_ADDRESS="$CAND"; fi
fi

# "created from WASM" line
if [ -z "$LOP_ADDRESS" ]; then
  CAND="$(echo "$RAW" \
    | awk '/Contract .* created from WASM/ {for(i=1;i<=NF;i++) if ($i ~ /^C[0-9A-Z]{55,60}$/) print $i}' \
    | tail -n1)"
  if is_contract_id "${CAND:-}" && [ "$CAND" != "$FACTORY_ID" ]; then
    LOP_ADDRESS="$CAND"
  fi
fi

# Arrow line: … → C…
if [ -z "$LOP_ADDRESS" ]; then
  CAND="$(echo "$RAW" \
    | awk -F'→ ' '/→/ {print $2}' | awk '{print $1}' \
    | grep -E '^C[0-9A-Z]{55,60}$' | grep -v "$FACTORY_ID" \
    | tail -n1)"
  if is_contract_id "${CAND:-}"; then LOP_ADDRESS="$CAND"; fi
fi

# Last C… that isn't factory
if [ -z "$LOP_ADDRESS" ]; then
  CAND="$(echo "$RAW" \
    | grep -oE 'C[0-9A-Z]{55,60}' \
    | grep -v "$FACTORY_ID" \
    | tail -n1)"
  if is_contract_id "${CAND:-}"; then LOP_ADDRESS="$CAND"; fi
fi

# Output the contract address (this will be captured by the calling code)
echo "\"${LOP_ADDRESS:-}\""

echo "✅ LOP deployed at: ${LOP_ADDRESS:-unknown}" >&2
echo "Salt: $SALT" >&2
echo "Admin: $ADMIN_ADDRESS" >&2
echo "Log file: $LOG_FILE" >&2