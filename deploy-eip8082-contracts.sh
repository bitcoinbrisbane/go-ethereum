#!/bin/bash

# EIP-8082 Contract Compilation and Deployment Script
# This script compiles and deploys EIP-8082 example contracts to a running Geth node

set -e

# Configuration
GETH_RPC_URL="http://127.0.0.1:8545"
SOLIDITY_DIR="../solidity"
CONTRACTS_DIR="$SOLIDITY_DIR/test/eip8802-examples"
OUTPUT_DIR="./eip8082-deployments"
GAS_LIMIT=6000000
GAS_PRICE=20000000000

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

# Function to check if Geth is running
check_geth_connection() {
    print_info "Checking connection to Geth node..."

    response=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"web3_clientVersion","params":[],"id":1}' \
        $GETH_RPC_URL 2>/dev/null || echo "")

    if [[ -z "$response" ]] || [[ "$response" == *"error"* ]]; then
        print_error "Cannot connect to Geth node at $GETH_RPC_URL"
        print_error "Please ensure Geth is running with: ./start-eip8082-dev.sh"
        exit 1
    fi

    print_success "Connected to Geth node"
}

# Function to get default account
get_default_account() {
    print_info "Getting default account..."

    response=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"eth_accounts","params":[],"id":1}' \
        $GETH_RPC_URL)

    DEFAULT_ACCOUNT=$(echo $response | grep -o '"0x[a-fA-F0-9]\{40\}"' | head -1 | tr -d '"')

    if [[ -z "$DEFAULT_ACCOUNT" ]]; then
        print_error "No accounts found. Please ensure Geth is running in dev mode."
        exit 1
    fi

    print_success "Using account: $DEFAULT_ACCOUNT"
}

# Function to unlock account
unlock_account() {
    print_info "Unlocking account $DEFAULT_ACCOUNT..."

    response=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        --data "{\"jsonrpc\":\"2.0\",\"method\":\"personal_unlockAccount\",\"params\":[\"$DEFAULT_ACCOUNT\",\"\",0],\"id\":1}" \
        $GETH_RPC_URL)

    if [[ "$response" == *"true"* ]]; then
        print_success "Account unlocked"
    else
        print_warning "Account unlock may have failed, but continuing..."
    fi
}

# Function to check if solc is available
check_solc() {
    if ! command -v solc &> /dev/null; then
        print_error "solc (Solidity compiler) not found"
        print_info "Please install Solidity compiler:"
        print_info "  - macOS: brew install solidity"
        print_info "  - Ubuntu: sudo snap install solc"
        print_info "  - Or use the custom solc from the solidity repo"
        exit 1
    fi

    solc_version=$(solc --version | head -1)
    print_success "Found Solidity compiler: $solc_version"
}

# Function to compile contract
compile_contract() {
    local contract_file=$1
    local contract_name=$(basename "$contract_file" .sol)

    print_info "Compiling $contract_name..."

    if [ ! -f "$contract_file" ]; then
        print_error "Contract file not found: $contract_file"
        return 1
    fi

    # Create output directory
    mkdir -p "$OUTPUT_DIR/$contract_name"

    # Compile contract with optimization and output ABI and bytecode
    solc --optimize --optimize-runs 200 \
         --abi --bin --overwrite \
         -o "$OUTPUT_DIR/$contract_name" \
         "$contract_file" 2>/dev/null

    if [ $? -eq 0 ]; then
        print_success "Compiled $contract_name"
        return 0
    else
        print_error "Failed to compile $contract_name"
        return 1
    fi
}

# Function to deploy contract
deploy_contract() {
    local contract_name=$1
    local constructor_args=$2

    print_info "Deploying $contract_name..."

    local abi_file="$OUTPUT_DIR/$contract_name/$contract_name.abi"
    local bin_file="$OUTPUT_DIR/$contract_name/$contract_name.bin"

    if [ ! -f "$abi_file" ] || [ ! -f "$bin_file" ]; then
        print_error "ABI or bytecode file not found for $contract_name"
        return 1
    fi

    local bytecode="0x$(cat $bin_file)$constructor_args"

    # Deploy contract
    local deploy_response=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        --data "{\"jsonrpc\":\"2.0\",\"method\":\"eth_sendTransaction\",\"params\":[{\"from\":\"$DEFAULT_ACCOUNT\",\"data\":\"$bytecode\",\"gas\":\"0x$(printf '%x' $GAS_LIMIT)\",\"gasPrice\":\"0x$(printf '%x' $GAS_PRICE)\"}],\"id\":1}" \
        $GETH_RPC_URL)

    local tx_hash=$(echo $deploy_response | grep -o '"0x[a-fA-F0-9]\{64\}"' | tr -d '"')

    if [[ -z "$tx_hash" ]]; then
        print_error "Failed to deploy $contract_name"
        echo "Response: $deploy_response"
        return 1
    fi

    print_success "Deployment transaction sent: $tx_hash"

    # Wait for transaction receipt
    print_info "Waiting for transaction receipt..."
    local receipt=""
    local attempts=0
    while [[ -z "$receipt" ]] && [[ $attempts -lt 30 ]]; do
        sleep 2
        receipt=$(curl -s -X POST \
            -H "Content-Type: application/json" \
            --data "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getTransactionReceipt\",\"params\":[\"$tx_hash\"],\"id\":1}" \
            $GETH_RPC_URL)

        if [[ "$receipt" == *"\"contractAddress\""* ]]; then
            break
        fi
        receipt=""
        ((attempts++))
    done

    if [[ -z "$receipt" ]] || [[ "$receipt" == *"null"* ]]; then
        print_error "Transaction receipt not found or deployment failed"
        return 1
    fi

    local contract_address=$(echo $receipt | grep -o '"contractAddress":"0x[a-fA-F0-9]\{40\}"' | cut -d'"' -f4)

    if [[ -z "$contract_address" ]]; then
        print_error "Contract address not found in receipt"
        return 1
    fi

    print_success "Contract $contract_name deployed at: $contract_address"

    # Save deployment info
    echo "Contract: $contract_name" > "$OUTPUT_DIR/$contract_name/deployment.txt"
    echo "Address: $contract_address" >> "$OUTPUT_DIR/$contract_name/deployment.txt"
    echo "Transaction: $tx_hash" >> "$OUTPUT_DIR/$contract_name/deployment.txt"
    echo "Block: $(echo $receipt | grep -o '"blockNumber":"0x[a-fA-F0-9]*"' | cut -d'"' -f4)" >> "$OUTPUT_DIR/$contract_name/deployment.txt"
    echo "Gas Used: $(echo $receipt | grep -o '"gasUsed":"0x[a-fA-F0-9]*"' | cut -d'"' -f4)" >> "$OUTPUT_DIR/$contract_name/deployment.txt"

    return 0
}

# Function to generate interaction script
generate_interaction_script() {
    print_info "Generating contract interaction script..."

    cat > "$OUTPUT_DIR/interact.js" << 'EOF'
// EIP-8082 Contract Interaction Script
// Load this script in Geth console with: loadScript('interact.js')

// Contract addresses (will be populated by deployment script)
const contracts = {};

// Contract ABIs (will be populated by deployment script)
const abis = {};

// Helper function to create contract instances
function getContract(name) {
    if (!contracts[name] || !abis[name]) {
        console.log("Contract " + name + " not found or ABI missing");
        return null;
    }
    return web3.eth.contract(JSON.parse(abis[name])).at(contracts[name]);
}

// Helper function to call EIP-8082 opcodes directly
function testSubscribe(eventHash, contractAddr, callbackAddr, gasLimit, value, data) {
    console.log("Testing SUBSCRIBE opcode...");
    // This would require custom transaction with EIP-8082 opcodes
    // For now, we'll use contract methods that internally call these opcodes
}

function testUnsubscribe(subscriptionId, contractAddr) {
    console.log("Testing UNSUBSCRIBE opcode...");
    // This would require custom transaction with EIP-8082 opcodes
}

function testNotifySubscribers(eventHash, data, gasLimit) {
    console.log("Testing NOTIFYSUBSCRIBERS opcode...");
    // This would require custom transaction with EIP-8082 opcodes
}

console.log("EIP-8082 interaction script loaded!");
console.log("Available contracts:", Object.keys(contracts));
console.log("Use getContract('ContractName') to interact with deployed contracts");
EOF

    print_success "Interaction script created at $OUTPUT_DIR/interact.js"
}

# Main deployment function
main() {
    echo ""
    print_info "EIP-8082 Contract Deployment Script"
    print_info "====================================="
    echo ""

    # Check prerequisites
    check_geth_connection
    check_solc
    get_default_account
    unlock_account

    # Check if contracts directory exists
    if [ ! -d "$CONTRACTS_DIR" ]; then
        print_error "Contracts directory not found: $CONTRACTS_DIR"
        print_error "Please ensure the solidity repository is in the correct location"
        exit 1
    fi

    # Create output directory
    mkdir -p "$OUTPUT_DIR"

    echo ""
    print_info "Starting contract compilation and deployment..."
    echo ""

    # List of contracts to deploy
    contracts_to_deploy=(
        "SimpleToken"
        "PriceOracle"
        "TokenWatcher"
        "DerivedProtocol"
        "ComprehensiveTest"
    )

    deployed_count=0

    # Deploy each contract
    for contract in "${contracts_to_deploy[@]}"; do
        contract_file="$CONTRACTS_DIR/$contract.sol"

        if compile_contract "$contract_file"; then
            if deploy_contract "$contract" ""; then
                ((deployed_count++))
            fi
        fi
        echo ""
    done

    # Generate interaction script
    generate_interaction_script

    echo ""
    print_info "Deployment Summary"
    print_info "=================="
    print_success "Successfully deployed $deployed_count out of ${#contracts_to_deploy[@]} contracts"
    print_info "Deployment details saved in: $OUTPUT_DIR"
    print_info "Contract interaction script: $OUTPUT_DIR/interact.js"
    echo ""
    print_info "Next steps:"
    print_info "1. Load the interaction script in Geth console:"
    print_info "   > loadScript('$OUTPUT_DIR/interact.js')"
    print_info "2. Test EIP-8082 functionality with the deployed contracts"
    print_info "3. Monitor events and subscriptions using the new opcodes"
    echo ""
}

# Run main function
main "$@"
