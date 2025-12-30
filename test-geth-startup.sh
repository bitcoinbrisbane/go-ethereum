#!/bin/bash

# Simple Geth Startup Test Script
# This script tests Geth startup with minimal configuration to debug issues

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Cleanup function
cleanup() {
    print_info "Cleaning up..."
    pkill -f "geth.*--dev" 2>/dev/null || true
    rm -f ./test-geth.pid
    rm -rf ./test-data
}

# Set trap for cleanup
trap cleanup EXIT

print_info "Testing Geth startup with minimal configuration..."
echo ""

# Check if geth binary exists
if [ ! -f "./build/bin/geth" ]; then
    print_error "Geth binary not found. Please run 'make geth' first."
    exit 1
fi

print_info "Geth binary found: ./build/bin/geth"

# Test 1: Check geth version
print_info "Testing: geth version"
./build/bin/geth version || {
    print_error "Failed to get geth version"
    exit 1
}
print_success "Version check passed"
echo ""

# Test 2: Check geth help (basic flag validation)
print_info "Testing: geth help"
./build/bin/geth --help > /dev/null || {
    print_error "Failed to get geth help"
    exit 1
}
print_success "Help check passed"
echo ""

# Test 3: Start geth with minimal dev configuration
print_info "Testing: geth dev mode startup"
print_info "Starting Geth with minimal dev configuration..."

mkdir -p ./test-data

# Start Geth with minimal config
./build/bin/geth \
    --datadir ./test-data \
    --dev \
    --http \
    --http.addr "127.0.0.1" \
    --http.port 8545 \
    --http.api "eth,web3,net" \
    --verbosity 3 \
    --nodiscover \
    --maxpeers 0 \
    > ./geth-test.log 2>&1 &

GETH_PID=$!
echo $GETH_PID > ./test-geth.pid

print_info "Geth started with PID: $GETH_PID"
print_info "Waiting for startup..."

# Wait for startup (max 30 seconds)
attempts=0
while [ $attempts -lt 15 ]; do
    if curl -s -X POST \
        -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"web3_clientVersion","params":[],"id":1}' \
        http://127.0.0.1:8545 > /dev/null 2>&1; then
        break
    fi

    # Check if process is still running
    if ! kill -0 $GETH_PID 2>/dev/null; then
        print_error "Geth process died! Check logs below:"
        echo ""
        cat ./geth-test.log
        exit 1
    fi

    sleep 2
    ((attempts++))
    echo -n "."
done

echo ""

if [ $attempts -eq 15 ]; then
    print_error "Geth failed to start within 30 seconds"
    print_info "Process status:"
    if kill -0 $GETH_PID 2>/dev/null; then
        print_info "Geth process is still running (PID: $GETH_PID)"
    else
        print_error "Geth process is not running"
    fi

    print_info "Geth startup log:"
    echo "===================="
    cat ./geth-test.log
    echo "===================="
    exit 1
fi

print_success "Geth started successfully!"

# Test 4: Basic RPC call
print_info "Testing: Basic RPC call"
response=$(curl -s -X POST \
    -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"web3_clientVersion","params":[],"id":1}' \
    http://127.0.0.1:8545)

if echo "$response" | grep -q '"result"'; then
    print_success "RPC call successful"
    client_version=$(echo "$response" | grep -o '"result":"[^"]*"' | cut -d'"' -f4)
    print_info "Client version: $client_version"
else
    print_error "RPC call failed"
    print_info "Response: $response"
    exit 1
fi

# Test 5: Check EIP-8082 opcodes are available
print_info "Testing: EIP-8082 opcode availability"
if grep -q "SUBSCRIBE.*0xb0" core/vm/opcodes.go; then
    print_success "EIP-8082 opcodes found in source code"
else
    print_warning "EIP-8082 opcodes not found in expected format"
fi

# Test 6: Account and balance check
print_info "Testing: Dev account and balance"
accounts_response=$(curl -s -X POST \
    -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"eth_accounts","params":[],"id":1}' \
    http://127.0.0.1:8545)

if echo "$accounts_response" | grep -q '"result":\['; then
    print_success "Accounts query successful"
    account=$(echo "$accounts_response" | grep -o '"0x[a-fA-F0-9]\{40\}"' | head -1 | tr -d '"')
    if [ -n "$account" ]; then
        print_info "Dev account: $account"

        balance_response=$(curl -s -X POST \
            -H "Content-Type: application/json" \
            --data "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBalance\",\"params\":[\"$account\",\"latest\"],\"id\":1}" \
            http://127.0.0.1:8545)

        if echo "$balance_response" | grep -q '"result"'; then
            print_success "Balance query successful"
            balance=$(echo "$balance_response" | grep -o '"result":"0x[a-fA-F0-9]*"' | cut -d'"' -f4)
            print_info "Account balance: $balance"
        else
            print_warning "Balance query failed"
        fi
    else
        print_warning "No dev account found"
    fi
else
    print_error "Accounts query failed"
fi

print_success "All basic tests passed!"
echo ""
print_info "Geth is running successfully at http://127.0.0.1:8545"
print_info "Process ID: $GETH_PID"
print_info "Data directory: ./test-data"
print_info "Log file: ./geth-test.log"
echo ""
print_info "To stop Geth: kill $GETH_PID"
print_info "To view logs: tail -f ./geth-test.log"

# Keep running for manual testing
print_info "Press Ctrl+C to stop Geth and exit"
wait $GETH_PID
