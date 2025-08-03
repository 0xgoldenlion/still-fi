#!/usr/bin/env bash
set -euo pipefail

#############################################
# Config
#############################################
FACTORY_ID="CACURHRDVGNUCFSMDWTIF6TABC76LNTAQYSIVDJK34P43OYOGPSGYDSO"
SOURCE_KEY="lion"
NETWORK="testnet"

MAKER_ADDRESS="GD4XRIZEWF7AI5XT5VOQFCGIZO3IYYJL6AORSUECCXSZTE3OBVWW74LA"
TAKER_ADDRESS="GD4XRIZEWF7AI5XT5VOQFCGIZO3IYYJL6AORSUECCXSZTE3OBVWW74LA"

# XLM has 7 decimals: 10 XLM -> 100000000
AMOUNT="9000000"            # i128 as STRING
CANCELLATION_TIMESTAMP=1754184950

#############################################
# Deps
#############################################
need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1" >&2; exit 1; }; }
need stellar; need openssl; need xxd
if ! command -v sha256sum >/dev/null 2>&1 && ! command -v shasum >/dev/null 2>&1; then
  echo "Missing dependency: sha256sum or shasum" >&2; exit 1
fi

#############################################
# Resolve native XLM SAC on testnet
#############################################
TOKEN_ADDRESS="$(
  stellar contract id asset --network "$NETWORK" --asset native 2>/dev/null \
  | grep -oE 'C[0-9A-Z]{55,60}' | head -n1
)"
[ -n "${TOKEN_ADDRESS:-}" ] || { echo "Failed to resolve native XLM SAC"; exit 1; }
echo "Native XLM token (SAC): $TOKEN_ADDRESS"

#############################################
# Salt / secret / hashlock
#############################################
SALT="$(openssl rand -hex 32)"
SECRET="$(openssl rand -hex 32)"
if command -v sha256sum >/dev/null 2>&1; then
  HASH="$(printf %s "$SECRET" | xxd -r -p | sha256sum | awk '{print $1}')"
else
  HASH="$(printf %s "$SECRET" | xxd -r -p | shasum -a 256 | awk '{print $1}')"
fi

echo "Salt: $SALT"
echo "Secret (keep safe): $SECRET"
echo "Hashlock: $HASH"
echo "Cancellation timestamp: $CANCELLATION_TIMESTAMP"

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
# Invoke (VERBOSE) and capture ALL output
# We save a timestamped log AND keep the combined output in a variable.
#############################################
LOG_FILE="deploy_escrow_$(date +%Y%m%d_%H%M%S).log"
echo "Deploying escrow via factory... (logging to $LOG_FILE)"

set +e
# Capture combined stdout+stderr and also tee to a file (preserving order)
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
echo "----- Raw CLI combined output (also in $LOG_FILE) -----"
echo "$RAW"
echo "------------------------------------------------------"
echo

if [ $STATUS -ne 0 ]; then
  echo "❌ Deployment failed (exit $STATUS)."
  echo "Salt: $SALT"
  echo "Hash: $HASH"
  exit $STATUS
fi

#############################################
# Extract escrow address (robust, multi-strategy)
#############################################
is_contract_id() { [[ "$1" =~ ^C[0-9A-Z]{55,60}$ ]]; }

ESCROW_ADDRESS=""

# 0A) Parse the event JSON: … = {"address":"C…"}
if [ -z "$ESCROW_ADDRESS" ]; then
  CAND="$(echo "$RAW" \
    | awk -F'"address":"' '/deploy_escrow/ && /"address":/ {split($2,a,"\""); print a[1]}' \
    | tail -n1)"
  if is_contract_id "${CAND:-}"; then ESCROW_ADDRESS="$CAND"; fi
fi

# 0B) Parse a standalone quoted result line: "C…"
if [ -z "$ESCROW_ADDRESS" ]; then
  CAND="$(echo "$RAW" | sed -n 's/^"\(C[0-9A-Z]\{55,60\}\)"/\1/p' | tail -n1)"
  if is_contract_id "${CAND:-}"; then ESCROW_ADDRESS="$CAND"; fi
fi

# 1) Factory event (string form) fallback
if [ -z "$ESCROW_ADDRESS" ]; then
  CAND="$(echo "$RAW" \
    | awk '/raised event/ && /deploy_escrow/ {for(i=1;i<=NF;i++) if ($i ~ /^C[0-9A-Z]{55,60}$/) print $i}' \
    | tail -n1)"
  if is_contract_id "${CAND:-}"; then ESCROW_ADDRESS="$CAND"; fi
fi

# 2) "created from WASM" line
if [ -z "$ESCROW_ADDRESS" ]; then
  CAND="$(echo "$RAW" \
    | awk '/Contract .* created from WASM/ {for(i=1;i<=NF;i++) if ($i ~ /^C[0-9A-Z]{55,60}$/) print $i}' \
    | tail -n1)"
  if is_contract_id "${CAND:-}" && [ "$CAND" != "$FACTORY_ID" ] && [ "$CAND" != "$TOKEN_ADDRESS" ]; then
    ESCROW_ADDRESS="$CAND"
  fi
fi

# 3) Arrow line: … → C…
if [ -z "$ESCROW_ADDRESS" ]; then
  CAND="$(echo "$RAW" \
    | awk -F'→ ' '/→/ {print $2}' | awk '{print $1}' \
    | grep -E '^C[0-9A-Z]{55,60}$' | grep -v -e "$FACTORY_ID" -e "$TOKEN_ADDRESS" \
    | tail -n1)"
  if is_contract_id "${CAND:-}"; then ESCROW_ADDRESS="$CAND"; fi
fi

# 4) Last C… that isn’t factory/token
if [ -z "$ESCROW_ADDRESS" ]; then
  CAND="$(echo "$RAW" \
    | grep -oE 'C[0-9A-Z]{55,60}' \
    | grep -v -e "$FACTORY_ID" -e "$TOKEN_ADDRESS" \
    | tail -n1)"
  if is_contract_id "${CAND:-}"; then ESCROW_ADDRESS="$CAND"; fi
fi

echo "✅ Parsed escrow address: ${ESCROW_ADDRESS:-unknown}"
echo "Salt: $SALT"
echo "Secret: $SECRET"
echo "Hash: $HASH"
echo "Log file: $LOG_FILE"

#############################################
# Save a summary file
#############################################
OUT_FILE="escrow_details.txt"
cat > "$OUT_FILE" <<EOF
Escrow Address: ${ESCROW_ADDRESS:-unknown}
Salt: $SALT
Secret: $SECRET
Hash: $HASH
Maker: $MAKER_ADDRESS
Taker: $TAKER_ADDRESS
Token (native XLM SAC): $TOKEN_ADDRESS
Amount (i128 string): $AMOUNT
Cancellation Timestamp (u64): $CANCELLATION_TIMESTAMP

Immutables JSON:
$(cat "$IMM_FILE")

Full CLI log saved at: $LOG_FILE
EOF

echo "Details saved to $OUT_FILE"
