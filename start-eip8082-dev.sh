#!/bin/bash

# Enhanced Geth startup script with EIP-8082 (Contract Event Subscription) enabled
# This script starts a single-node development blockchain with all necessary configurations

set -e

# Configuration
CHAIN_ID=1337
HTTP_PORT=8545
WS_PORT=8546
DATA_DIR="./dev-data"
LOG_LEVEL=3

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to cleanup on exit
cleanup() {
    print_info "Shutting down Geth..."
    if [[ -n $GETH_PID ]]; then
        kill $GETH_PID 2>/dev/null || true
        wait $GETH_PID 2>/dev/null || true
    fi
    exit 0
}

# Set trap for cleanup
trap cleanup SIGINT SIGTERM

# Check if geth binary exists
if [ ! -f "./build/bin/geth" ]; then
    print_error "Geth binary not found. Please run 'make geth' first."
    exit 1
fi

# Create data directory if it doesn't exist
mkdir -p "$DATA_DIR"

print_info "Starting Geth with EIP-8082 (Contract Event Subscription) support..."
echo ""
print_info "Configuration:"
print_info "  - Chain ID: $CHAIN_ID"
print_info "  - HTTP RPC: http://127.0.0.1:$HTTP_PORT"
print_info "  - WebSocket: ws://127.0.0.1:$WS_PORT"
print_info "  - Data Directory: $DATA_DIR"
print_info "  - EIP-8082 Features:"
print_info "    * SUBSCRIBE opcode (0xF8)"
print_info "    * UNSUBSCRIBE opcode (0xF9)"
print_info "    * NOTIFYSUBSCRIBERS opcode (0xFA)"
echo ""
print_warning "Data will persist in $DATA_DIR directory"
print_info "Press Ctrl+C to stop the node"
echo ""

# Start Geth with comprehensive configuration
./build/bin/geth \
    --datadir "$DATA_DIR" \
    --networkid $CHAIN_ID \
    --dev \
    --dev.period 1 \
    --http \
    --http.addr "0.0.0.0" \
    --http.port $HTTP_PORT \
    --http.api "eth,web3,net,debug,txpool,admin,miner,personal" \
    --http.corsdomain "*" \
    --http.vhosts "*" \
    --ws \
    --ws.addr "0.0.0.0" \
    --ws.port $WS_PORT \
    --ws.api "eth,web3,net,debug,txpool,admin,miner,personal" \
    --ws.origins "*" \
    --rpc.gascap 50000000 \
    --rpc.txfeecap 0 \
    --mine \
    --miner.gasprice 1000000000 \
    --verbosity $LOG_LEVEL \
    --gcmode archive \
    --syncmode full \
    --allow-insecure-unlock \
    --nodiscover \
    --maxpeers 0 \
    console &

# Store the PID for cleanup
GETH_PID=$!

print_success "Geth started successfully with PID: $GETH_PID"
print_info "Node is ready for EIP-8082 contract deployment and testing"
print_info ""
print_info "Useful commands:"
print_info "  - Check accounts: eth.accounts"
print_info "  - Get balance: web3.fromWei(eth.getBalance(eth.accounts[0]), 'ether')"
print_info "  - Test EIP-8082: Deploy contracts using deploy-eip8082-contracts.sh"
echo ""

# Wait for Geth process
wait $GETH_PID
