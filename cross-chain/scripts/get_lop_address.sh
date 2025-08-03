#!/bin/bash

# Get LOP Address Script
# This script gets the deterministic address of a LOP contract without deploying it

# Factory contract ID
FACTORY_ID="CDLWW5OUQZWE76WLYGKN6TCOG2UKOZ4HTOU5UN6RMNTXOCMDVWHE5UO4"

# Configuration
SOURCE_KEY="lion"
NETWORK="testnet"

show_usage() {
  cat <<EOF
Usage: $0 <salt> [options]

Arguments:
  salt               32-byte hex salt (64 characters)

Options:
  --source PROFILE   Signing profile (default: $SOURCE_KEY)
  --network NET      Network (default: $NETWORK)
  --dutch-auction    Also get Dutch auction address
  --help|-h          Show this help

Examples:
  $0 a1b2c3d4e5f6789012345678901234567890abcdef1234567890abcdef123456
  $0 a1b2c3d4e5f6789012345678901234567890abcdef1234567890abcdef123456 --dutch-auction
  $0 --help
EOF
}

# Parse arguments
SHOW_DUTCH_AUCTION=false
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
    --dutch-auction)
      SHOW_DUTCH_AUCTION=true
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
      if [[ -z "${SALT:-}" ]]; then
        SALT="$1"
        shift
      else
        echo "Too many arguments"
        show_usage
        exit 1
      fi
      ;;
  esac
done

# Check if salt is provided
if [[ -z "${SALT:-}" ]]; then
    echo "Error: Salt is required"
    echo ""
    show_usage
    echo ""
    echo "Or generate a new salt:"
    NEW_SALT=$(openssl rand -hex 32)
    echo "New salt: $NEW_SALT"
    echo "Run: $0 $NEW_SALT"
    exit 1
fi

# Validate salt format
if [[ ${#SALT} -ne 64 ]]; then
    echo "Error: Salt must be exactly 64 hex characters (32 bytes)"
    exit 1
fi

if [[ ! "$SALT" =~ ^[0-9a-fA-F]+$ ]]; then
    echo "Error: Salt must contain only hex characters (0-9, a-f, A-F)"
    exit 1
fi

echo "Getting LOP contract address for salt: $SALT"
echo "Factory: $FACTORY_ID"
echo "Network: $NETWORK"
echo ""

# Get the deterministic LOP address
echo "🔍 Getting LOP address..."
LOP_ADDRESS=$(stellar contract invoke \
  --id $FACTORY_ID \
  --source $SOURCE_KEY \
  --network $NETWORK \
  -- get_lop_address \
  --salt $SALT)

echo "✅ LOP Contract Address:"
echo "   $LOP_ADDRESS"

# Get Dutch auction address if requested
if [[ "$SHOW_DUTCH_AUCTION" == "true" ]]; then
  echo ""
  echo "🔍 Getting associated Dutch auction address..."
  
  # The Dutch auction salt is derived from LOP salt using SHA256
  if command -v sha256sum >/dev/null 2>&1; then
    DUTCH_SALT=$(printf %s "$SALT" | xxd -r -p | sha256sum | awk '{print $1}')
  elif command -v shasum >/dev/null 2>&1; then
    DUTCH_SALT=$(printf %s "$SALT" | xxd -r -p | shasum -a 256 | awk '{print $1}')
  else
    echo "⚠️  Cannot compute Dutch auction salt (missing sha256sum/shasum)"
    DUTCH_SALT=""
  fi
  
  if [[ -n "$DUTCH_SALT" ]]; then
    DUTCH_AUCTION_ADDRESS=$(stellar contract invoke \
      --id $FACTORY_ID \
      --source $SOURCE_KEY \
      --network $NETWORK \
      -- get_dutch_auction_address \
      --salt $DUTCH_SALT)
    
    echo "✅ Dutch Auction Address:"
    echo "   $DUTCH_AUCTION_ADDRESS"
    echo ""
    echo "📝 Dutch auction salt (derived): $DUTCH_SALT"
  fi
fi

echo ""
echo "📋 Summary:"
echo "   LOP Salt:     $SALT"
echo "   LOP Address:  $LOP_ADDRESS"
if [[ "$SHOW_DUTCH_AUCTION" == "true" && -n "${DUTCH_AUCTION_ADDRESS:-}" ]]; then
  echo "   Dutch Salt:   $DUTCH_SALT"
  echo "   Dutch Addr:   $DUTCH_AUCTION_ADDRESS"
fi
echo ""
echo "💡 Note: These addresses will be the same every time you use the same salt."
echo "💡 To deploy LOP contract at this address, use: ./deploy_lop.sh --salt $SALT"