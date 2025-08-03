#!/usr/bin/env bash
set -euo pipefail

# Build a SorobanLOP::Order JSON object.
# i128 fields MUST be strings in JSON.

usage() {
  cat <<'EOF'
Usage:
  build_order.sh \
    --salt <u64> \
    --maker G... \
    --receiver <G... or contract C...> \
    --maker-asset C... \
    --taker-asset C... \
    --making "<i128 string>" \
    --taking "<i128 string>" \
    --maker-traits <u64> \
    --auction-start <u64> \
    --auction-end <u64> \
    --taking-start "<i128 string>" \
    --taking-end "<i128 string>" \
    [--out /path/order.json]

Notes:
  - For a regular (non-dutch) order, set maker-traits=0 and auction fields can be 0.
  - For dutch, set maker-traits=1 (IS_DUTCH_AUCTION) and fill auction fields.
  - i128 values (making/taking/taking-start/taking-end) must be quoted strings.
EOF
}

OUT=""
# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --salt) SALT="$2"; shift 2;;
    --maker) MAKER="$2"; shift 2;;
    --receiver) RECEIVER="$2"; shift 2;;
    --maker-asset) MAKER_ASSET="$2"; shift 2;;
    --taker-asset) TAKER_ASSET="$2"; shift 2;;
    --making) MAKING="$2"; shift 2;;
    --taking) TAKING="$2"; shift 2;;
    --maker-traits) MAKER_TRAITS="$2"; shift 2;;
    --auction-start) AU_START="$2"; shift 2;;
    --auction-end) AU_END="$2"; shift 2;;
    --taking-start) TK_START="$2"; shift 2;;
    --taking-end) TK_END="$2"; shift 2;;
    --out) OUT="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1"; usage; exit 1;;
  esac
done

# Basic validation
req() { test -n "${!1:-}" || { echo "Missing --$2"; exit 1; }; }
for k in SALT MAKER RECEIVER MAKER_ASSET TAKER_ASSET MAKING TAKING MAKER_TRAITS AU_START AU_END TK_START TK_END; do
  req "$k" "$(echo "$k" | tr 'A-Z_' 'a-z-')"
done

JSON=$(cat <<EOF
{
  "salt": $SALT,
  "maker": "$MAKER",
  "receiver": "$RECEIVER",
  "maker_asset": "$MAKER_ASSET",
  "taker_asset": "$TAKER_ASSET",
  "making_amount": "$MAKING",
  "taking_amount": "$TAKING",
  "maker_traits": $MAKER_TRAITS,
  "auction_start_time": $AU_START,
  "auction_end_time": $AU_END,
  "taking_amount_start": "$TK_START",
  "taking_amount_end": "$TK_END"
}
EOF
)

if [[ -n "$OUT" ]]; then
  printf '%s\n' "$JSON" > "$OUT"
  echo "$OUT"
else
  printf '%s\n' "$JSON"
fi
