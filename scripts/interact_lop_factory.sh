#!/usr/bin/env bash
set -euo pipefail

# LOP Factory Management Script
# Interact with the LOP factory contract for management operations

# Factory contract ID
FACTORY_ID="CDLWW5OUQZWE76WLYGKN6TCOG2UKOZ4HTOU5UN6RMNTXOCMDVWHE5UO4"

# Defaults
SOURCE_KEY="${SOURCE_KEY:-lion}"
NETWORK="${NETWORK:-testnet}"

# --- helpers ---
need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1"; exit 1; }; }
need stellar

is_contract_id() { [[ "${1:-}" =~ ^C[0-9A-Z]{55,60}$ ]]; }
is_gaddr()       { [[ "${1:-}" =~ ^G[0-9A-Z]{55}$ ]]; }
is_hex64()       { [[ "${1:-}" =~ ^[0-9a-fA-F]{64}$ ]]; }

show_usage() {
  cat <<EOF
Usage:
  $0 [--source PROFILE] [--network {testnet|futurenet|mainnet}] <command> <args>

Flags (optional):
  --source   Signing profile/key (default: lion)
  --network  Network to use (default: testnet)

Commands:
  info                              Get factory information
  get-lop-wasm-hash                Get current LOP WASM hash
  get-dutch-auction-wasm-hash      Get current Dutch auction WASM hash
  get-admin                        Get factory admin address
  update-lop-wasm <new_hash>       Update LOP WASM hash (admin only)
  update-dutch-wasm <new_hash>     Update Dutch auction WASM hash (admin only)
  deploy-standalone-dutch <salt>   Deploy standalone Dutch auction contract

Examples:
  $0 info
  $0 get-lop-wasm-hash
  $0 update-lop-wasm b5f8b3315108593e18dbcd4a3fc36c40d4b4ba5b335ccc23de9d7ce1ce47ff02
  $0 deploy-standalone-dutch a1b2c3d4e5f6789012345678901234567890abcdef1234567890abcdef123456
EOF
}

# --- parse flags ---
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
    echo "🏭 LOP Factory Information"
    echo "Factory Address: $FACTORY_ID"
    echo "Network: $NETWORK"
    echo ""
    
    echo "📋 Admin:"
    stellar contract invoke \
      --id "$FACTORY_ID" \
      --source "$SOURCE_KEY" \
      --network "$NETWORK" \
      -- get_admin
    
    echo ""
    echo "📦 LOP WASM Hash:"
    stellar contract invoke \
      --id "$FACTORY_ID" \
      --source "$SOURCE_KEY" \
      --network "$NETWORK" \
      -- get_lop_wasm_hash
    
    echo ""
    echo "🎯 Dutch Auction WASM Hash:"
    stellar contract invoke \
      --id "$FACTORY_ID" \
      --source "$SOURCE_KEY" \
      --network "$NETWORK" \
      -- get_dutch_auction_wasm_hash
    ;;

  get-lop-wasm-hash)
    echo "Getting LOP WASM hash..."
    stellar contract invoke \
      --id "$FACTORY_ID" \
      --source "$SOURCE_KEY" \
      --network "$NETWORK" \
      -- get_lop_wasm_hash
    ;;

  get-dutch-auction-wasm-hash)
    echo "Getting Dutch auction WASM hash..."
    stellar contract invoke \
      --id "$FACTORY_ID" \
      --source "$SOURCE_KEY" \
      --network "$NETWORK" \
      -- get_dutch_auction_wasm_hash
    ;;

  get-admin)
    echo "Getting factory admin address..."
    stellar contract invoke \
      --id "$FACTORY_ID" \
      --source "$SOURCE_KEY" \
      --network "$NETWORK" \
      -- get_admin
    ;;

  update-lop-wasm)
    if [[ $# -lt 1 ]]; then echo "update-lop-wasm requires <new_hash>"; exit 1; fi
    NEW_HASH="$1"
    is_hex64 "$NEW_HASH" || { echo "WASM hash must be 64 hex characters"; exit 1; }
    
    echo "Updating LOP WASM hash to: $NEW_HASH"
    echo "⚠️  This requires admin authorization!"
    stellar contract invoke \
      --id "$FACTORY_ID" \
      --source "$SOURCE_KEY" \
      --network "$NETWORK" \
      -- update_lop_wasm_hash \
      --new_wasm_hash "$NEW_HASH"
    ;;

  update-dutch-wasm)
    if [[ $# -lt 1 ]]; then echo "update-dutch-wasm requires <new_hash>"; exit 1; fi
    NEW_HASH="$1"
    is_hex64 "$NEW_HASH" || { echo "WASM hash must be 64 hex characters"; exit 1; }
    
    echo "Updating Dutch auction WASM hash to: $NEW_HASH"
    echo "⚠️  This requires admin authorization!"
    stellar contract invoke \
      --id "$FACTORY_ID" \
      --source "$SOURCE_KEY" \
      --network "$NETWORK" \
      -- update_dutch_auction_wasm_hash \
      --new_wasm_hash "$NEW_HASH"
    ;;

  deploy-standalone-dutch)
    if [[ $# -lt 1 ]]; then echo "deploy-standalone-dutch requires <salt>"; exit 1; fi
    SALT="$1"
    [[ ${#SALT} -eq 64 ]] || { echo "Salt must be 64 hex characters"; exit 1; }
    
    echo "Deploying standalone Dutch auction contract with salt: $SALT"
    DUTCH_ADDRESS=$(stellar contract invoke \
      --id "$FACTORY_ID" \
      --source "$SOURCE_KEY" \
      --network "$NETWORK" \
      -- deploy_dutch_auction \
      --salt "$SALT")
    
    echo "✅ Deployed Dutch auction contract:"
    echo "   Address: $DUTCH_ADDRESS"
    echo "   Salt: $SALT"
    ;;

  *)
    echo "Unknown command: $COMMAND"; show_usage; exit 1 ;;
esac