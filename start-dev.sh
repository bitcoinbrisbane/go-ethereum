#!/bin/bash
# Start geth in dev mode for testing
# This provides a private Ethereum test chain with instant mining

echo "Starting Geth in Dev Mode..."
echo ""
echo "Features:"
echo "  - Chain ID: 1337"
echo "  - Instant block mining (only when transactions are pending)"
echo "  - Pre-funded developer account"
echo "  - HTTP RPC available at: http://127.0.0.1:8545"
echo "  - All Ethereum hard forks activated from block 0"
echo ""
echo "WARNING: Data is stored in memory and will be lost on shutdown!"
echo ""

./build/bin/geth --dev \
  --http \
  --http.addr "127.0.0.1" \
  --http.port 8545 \
  --http.api eth,web3,net,debug,txpool,admin,miner \
  --http.corsdomain "*" \
  console
