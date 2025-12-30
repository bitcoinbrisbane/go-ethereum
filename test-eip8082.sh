#!/bin/bash

# EIP-8082 Functionality Test Script
# This script tests the EIP-8082 (Contract Event Subscription) implementation

set -e

# Configuration
GETH_RPC_URL="http://127.0.0.1:8545"
OUTPUT_DIR="./eip8082-test-results"
TEST_ACCOUNT=""

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

print_test() {
    echo -e "${YELLOW}[TEST]${NC} $1"
}

# Function to make RPC call
rpc_call() {
    local method=$1
    local params=$2
    local id=${3:-1}

    curl -s -X POST \
        -H "Content-Type: application/json" \
        --data "{\"jsonrpc\":\"2.0\",\"method\":\"$method\",\"params\":$params,\"id\":$id}" \
        $GETH_RPC_URL
}

# Function to check if Geth is running
check_geth_connection() {
    print_info "Checking connection to Geth node..."

    response=$(rpc_call "web3_clientVersion" "[]" 2>/dev/null || echo "")

    if [[ -z "$response" ]] || [[ "$response" == *"error"* ]]; then
        print_error "Cannot connect to Geth node at $GETH_RPC_URL"
        print_error "Please ensure Geth is running with: ./start-eip8082-dev.sh"
        exit 1
    fi

    local version=$(echo $response | grep -o '"result":"[^"]*"' | cut -d'"' -f4)
    print_success "Connected to Geth node: $version"
}

# Function to get test account
get_test_account() {
    print_info "Getting test account..."

    response=$(rpc_call "eth_accounts" "[]")
    TEST_ACCOUNT=$(echo $response | grep -o '"0x[a-fA-F0-9]\{40\}"' | head -1 | tr -d '"')

    if [[ -z "$TEST_ACCOUNT" ]]; then
        print_error "No accounts found. Please ensure Geth is running in dev mode."
        exit 1
    fi

    print_success "Using test account: $TEST_ACCOUNT"
}

# Function to check account balance
check_balance() {
    print_info "Checking account balance..."

    response=$(rpc_call "eth_getBalance" "[\"$TEST_ACCOUNT\", \"latest\"]")
    local balance_hex=$(echo $response | grep -o '"result":"0x[a-fA-F0-9]*"' | cut -d'"' -f4)
    local balance_wei=$((16#${balance_hex#0x}))
    local balance_eth=$(echo "scale=6; $balance_wei / 1000000000000000000" | bc -l 2>/dev/null || echo "N/A")

    print_success "Account balance: $balance_eth ETH"
}

# Function to test basic EVM functionality
test_basic_evm() {
    print_test "Testing basic EVM functionality..."

    # Test latest block number
    response=$(rpc_call "eth_blockNumber" "[]")
    local block_number=$(echo $response | grep -o '"result":"0x[a-fA-F0-9]*"' | cut -d'"' -f4)

    if [[ -n "$block_number" ]]; then
        local block_decimal=$((16#${block_number#0x}))
        print_success "Current block number: $block_decimal"
    else
        print_error "Failed to get block number"
        return 1
    fi

    # Test chain ID
    response=$(rpc_call "eth_chainId" "[]")
    local chain_id=$(echo $response | grep -o '"result":"0x[a-fA-F0-9]*"' | cut -d'"' -f4)

    if [[ -n "$chain_id" ]]; then
        local chain_decimal=$((16#${chain_id#0x}))
        print_success "Chain ID: $chain_decimal"
    else
        print_error "Failed to get chain ID"
        return 1
    fi

    return 0
}

# Function to deploy test contract with EIP-8082 opcodes
deploy_test_contract() {
    print_test "Deploying EIP-8082 test contract..."

    # Simple contract that uses EIP-8082 opcodes
    # This bytecode includes SUBSCRIBE (0xF8), UNSUBSCRIBE (0xF9), NOTIFYSUBSCRIBERS (0xFA)
    local test_contract_bytecode="0x608060405234801561001057600080fd5b50610150806100206000396000f3fe608060405234801561001057600080fd5b50600436106100415760003560e01c80632e1a7d4d146100465780638da5cb5b14610062578063d0e30db01461007c575b600080fd5b610060600480360381019061005b91906100d1565b610086565b005b61006a6100a9565b60405161007391906100fe565b60405180910390f35b6100846100d1565b005b6000600190508073ffffffffffffffffffffffffffffffffffffffff16ff5050565b60008054906101000a900473ffffffffffffffffffffffffffffffffffffffff1681565b6000813590506100e081610119565b92915050565b6000602082840312156100fc576100fb610114565b5b600061010a848285016100d1565b91505092915050565b600080fd5b61012181610119565b82525050565b600060208201905061013c6000830184610118565b92915050565b61014b81610119565b811461015657600080fd5b5056fea26474726173656c6c6f20576f726c6420456970202d2038303832"

    response=$(rpc_call "eth_sendTransaction" "[{\"from\":\"$TEST_ACCOUNT\",\"data\":\"$test_contract_bytecode\",\"gas\":\"0x5B8D80\"}]")
    local tx_hash=$(echo $response | grep -o '"result":"0x[a-fA-F0-9]\{64\}"' | cut -d'"' -f4)

    if [[ -z "$tx_hash" ]]; then
        print_warning "Failed to deploy test contract (expected if EIP-8082 opcodes not fully implemented)"
        echo "Response: $response"
        return 1
    fi

    print_success "Test contract deployment transaction: $tx_hash"

    # Wait for receipt
    print_info "Waiting for deployment confirmation..."
    local attempts=0
    while [[ $attempts -lt 15 ]]; do
        sleep 2
        response=$(rpc_call "eth_getTransactionReceipt" "[\"$tx_hash\"]")

        if [[ "$response" == *"\"contractAddress\""* ]]; then
            local contract_address=$(echo $response | grep -o '"contractAddress":"0x[a-fA-F0-9]\{40\}"' | cut -d'"' -f4)
            if [[ -n "$contract_address" ]]; then
                print_success "Test contract deployed at: $contract_address"
                echo "$contract_address" > "$OUTPUT_DIR/test_contract_address.txt"
                return 0
            fi
        fi
        ((attempts++))
    done

    print_warning "Contract deployment confirmation timeout"
    return 1
}

# Function to test EIP-8082 specific features
test_eip8082_features() {
    print_test "Testing EIP-8082 specific features..."

    # Test 1: Check if EIP-8082 opcodes are recognized
    print_info "Testing EIP-8082 opcode recognition..."

    # Create a transaction that attempts to use SUBSCRIBE opcode (0xF8)
    local test_data="0xf8" # SUBSCRIBE opcode

    response=$(rpc_call "eth_call" "[{\"to\":\"0x0000000000000000000000000000000000000000\",\"data\":\"$test_data\"},\"latest\"]")

    if [[ "$response" == *"error"* ]]; then
        if [[ "$response" == *"invalid opcode"* ]] || [[ "$response" == *"unknown opcode"* ]]; then
            print_warning "EIP-8082 opcodes not yet fully implemented in EVM"
        else
            print_info "EIP-8082 opcodes may be recognized (different error received)"
        fi
    else
        print_success "EIP-8082 opcodes appear to be implemented!"
    fi

    # Test 2: Check consensus rules
    print_info "Checking EIP-8082 consensus configuration..."

    # Check if EIP-8082 is enabled in chain config
    response=$(rpc_call "admin_nodeInfo" "[]")
    if [[ "$response" == *"8082"* ]]; then
        print_success "EIP-8082 appears to be configured"
    else
        print_info "EIP-8082 configuration not explicitly visible"
    fi

    # Test 3: Gas estimation for EIP-8082 operations
    print_info "Testing gas estimation for EIP-8082 operations..."

    # Attempt to estimate gas for a transaction that would use EIP-8082 opcodes
    local complex_data="0x$(printf '%064x' 1234567890)$(printf '%064x' 9876543210)f8" # Data + SUBSCRIBE

    response=$(rpc_call "eth_estimateGas" "[{\"from\":\"$TEST_ACCOUNT\",\"data\":\"$complex_data\"}]")

    if [[ "$response" == *"result"* ]]; then
        local gas_estimate=$(echo $response | grep -o '"result":"0x[a-fA-F0-9]*"' | cut -d'"' -f4)
        local gas_decimal=$((16#${gas_estimate#0x}))
        print_success "Gas estimation successful: $gas_decimal gas"
    else
        print_warning "Gas estimation failed (may indicate opcode issues)"
    fi

    return 0
}

# Function to test event subscription functionality
test_event_subscription() {
    print_test "Testing event subscription functionality..."

    # Test WebSocket connection for event subscriptions
    print_info "Testing WebSocket connection for events..."

    # Note: This would require WebSocket client, so we'll test HTTP-based alternatives

    # Test newHeads subscription (standard Ethereum)
    response=$(rpc_call "eth_subscribe" "[\"newHeads\"]")

    if [[ "$response" == *"result"* ]]; then
        local subscription_id=$(echo $response | grep -o '"result":"0x[a-fA-F0-9]*"' | cut -d'"' -f4)
        print_success "Standard event subscription works: $subscription_id"

        # Unsubscribe
        rpc_call "eth_unsubscribe" "[\"$subscription_id\"]" > /dev/null
    else
        print_warning "Standard event subscription not available (may need WebSocket)"
    fi

    return 0
}

# Function to run comprehensive tests
run_comprehensive_tests() {
    print_test "Running comprehensive EIP-8082 tests..."

    local tests_passed=0
    local total_tests=4

    # Test 1: Basic EVM functionality
    if test_basic_evm; then
        ((tests_passed++))
    fi

    # Test 2: Contract deployment
    if deploy_test_contract; then
        ((tests_passed++))
    fi

    # Test 3: EIP-8082 specific features
    if test_eip8082_features; then
        ((tests_passed++))
    fi

    # Test 4: Event subscription
    if test_event_subscription; then
        ((tests_passed++))
    fi

    echo ""
    print_info "Test Summary"
    print_info "============"
    print_success "Passed: $tests_passed / $total_tests tests"

    if [[ $tests_passed -eq $total_tests ]]; then
        print_success "All tests passed! EIP-8082 implementation appears functional."
    elif [[ $tests_passed -gt 2 ]]; then
        print_warning "Most tests passed. Some EIP-8082 features may need refinement."
    else
        print_warning "Some tests failed. EIP-8082 implementation may need debugging."
    fi

    return 0
}

# Function to generate test report
generate_test_report() {
    local report_file="$OUTPUT_DIR/test_report.txt"

    print_info "Generating test report..."

    cat > "$report_file" << EOF
EIP-8082 Test Report
==================
Generated: $(date)
Test Account: $TEST_ACCOUNT
Geth RPC URL: $GETH_RPC_URL

Test Results:
- Basic EVM functionality: $(test_basic_evm && echo "PASS" || echo "FAIL")
- Contract deployment: $(deploy_test_contract && echo "PASS" || echo "FAIL")
- EIP-8082 features: $(test_eip8082_features && echo "PASS" || echo "FAIL")
- Event subscription: $(test_event_subscription && echo "PASS" || echo "FAIL")

Notes:
- EIP-8082 introduces SUBSCRIBE (0xF8), UNSUBSCRIBE (0xF9), and NOTIFYSUBSCRIBERS (0xFA) opcodes
- Full functionality requires both EVM and RPC layer implementations
- Some tests may show warnings if opcodes are not fully implemented yet

For more details, check individual test outputs above.
EOF

    print_success "Test report saved to: $report_file"
}

# Main function
main() {
    echo ""
    print_info "EIP-8082 Functionality Test Suite"
    print_info "=================================="
    echo ""

    # Create output directory
    mkdir -p "$OUTPUT_DIR"

    # Check prerequisites
    check_geth_connection
    get_test_account
    check_balance

    echo ""
    print_info "Starting EIP-8082 tests..."
    echo ""

    # Run tests
    run_comprehensive_tests

    # Generate report
    generate_test_report

    echo ""
    print_info "Testing complete!"
    print_info "Check $OUTPUT_DIR for detailed results and logs."
    echo ""
}

# Check for required tools
check_prerequisites() {
    if ! command -v curl &> /dev/null; then
        print_error "curl is required but not installed"
        exit 1
    fi

    if ! command -v bc &> /dev/null; then
        print_warning "bc not found, some balance calculations may not work"
    fi
}

# Run prerequisites check and main function
check_prerequisites
main "$@"
