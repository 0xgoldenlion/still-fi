#!/bin/bash

# Get Escrow Address Script
# This script gets the deterministic address of an escrow without deploying it

# Factory contract ID
FACTORY_ID="CACURHRDVGNUCFSMDWTIF6TABC76LNTAQYSIVDJK34P43OYOGPSGYDSO"

# Configuration
SOURCE_KEY="lion"
NETWORK="testnet"

# Check if salt is provided as argument
if [ $# -eq 0 ]; then
    echo "Usage: $0 <salt>"
    echo "Example: $0 a1b2c3d4e5f6789012345678901234567890abcdef1234567890abcdef123456"
    echo ""
    echo "Or generate a new salt:"
    NEW_SALT=$(openssl rand -hex 32)
    echo "New salt: $NEW_SALT"
    echo "Run: $0 $NEW_SALT"
    exit 1
fi

SALT=$1

echo "Getting escrow address for salt: $SALT"

# Get the deterministic address
ESCROW_ADDRESS=$(stellar contract invoke \
  --id $FACTORY_ID \
  --source $SOURCE_KEY \
  --network $NETWORK \
  -- get_escrow_address \
  --salt $SALT)

echo ""
echo "✅ Escrow address for salt '$SALT':"
echo "Address: $ESCROW_ADDRESS"
echo ""
echo "Note: This address will be the same every time you use this salt."
echo "To deploy an escrow at this address, use: ./deploy_escrow.sh with the same salt"