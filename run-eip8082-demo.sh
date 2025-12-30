#!/bin/bash

# EIP-8082 Master Demo Script
# This script orchestrates the complete EIP-8082 testing process:
# 1. Start Geth with EIP-8082 support
# 2. Deploy EIP-8082 contracts
# 3. Run functionality tests
# 4. Provide interactive options

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$SCRIPT_DIR/eip8082-demo-logs"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to print colored output
print_header() {
    echo -e "${PURPLE}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║${NC} $1 ${PURPLE}║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
}

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

print_step() {
    echo -e "${CYAN}[STEP]${NC} $1"
}

# Function to show usage
show_usage() {
    cat << EOF
EIP-8082 Demo Script Usage:
==========================

./run-eip8082-demo.sh [OPTIONS] [COMMAND]

COMMANDS:
  start       Start Geth node with EIP-8082 support
  deploy      Deploy EIP-8082 contracts (requires running node)
  test        Run EIP-8082 functionality tests
  full        Run complete demo (start + deploy + test)
  stop        Stop running Geth node
  clean       Clean up generated files
  status      Check demo status

OPTIONS:
  -h, --help     Show this help message
  -v, --verbose  Enable verbose logging
  -q, --quiet    Suppress non-essential output
  --no-wait      Don't wait for user input between steps
  --log-dir DIR  Custom log directory (default: $LOG_DIR)

EXAMPLES:
  ./run-eip8082-demo.sh full          # Run complete demo
  ./run-eip8082-demo.sh start         # Just start the node
  ./run-eip8082-demo.sh deploy        # Deploy contracts to running node
  ./run-eip8082-demo.sh test          # Run tests against running node
  ./run-eip8082-demo.sh --verbose full # Run with detailed logging

EOF
}

# Function to check prerequisites
check_prerequisites() {
    print_step "Checking prerequisites..."

    local missing_deps=()

    # Check required commands
    for cmd in curl jq bc; do
        if ! command -v $cmd &> /dev/null; then
            missing_deps+=($cmd)
        fi
    done

    # Check if geth binary exists
    if [ ! -f "$SCRIPT_DIR/build/bin/geth" ]; then
        print_error "Geth binary not found. Please run 'make geth' first."
        exit 1
    fi

    # Check if solidity contracts exist
    if [ ! -d "$SCRIPT_DIR/../solidity/test/eip8802-examples" ]; then
        print_warning "Solidity contracts directory not found"
        print_info "Expected: $SCRIPT_DIR/../solidity/test/eip8802-examples"
        print_info "This may affect contract deployment tests"
    fi

    if [ ${#missing_deps[@]} -gt 0 ]; then
        print_error "Missing dependencies: ${missing_deps[*]}"
        print_info "Please install missing dependencies:"
        print_info "  macOS: brew install curl jq bc"
        print_info "  Ubuntu: sudo apt-get install curl jq bc"
        exit 1
    fi

    print_success "Prerequisites check passed"
}

# Function to setup logging
setup_logging() {
    mkdir -p "$LOG_DIR"

    export GETH_LOG="$LOG_DIR/geth_$TIMESTAMP.log"
    export DEPLOY_LOG="$LOG_DIR/deploy_$TIMESTAMP.log"
    export TEST_LOG="$LOG_DIR/test_$TIMESTAMP.log"

    print_info "Logs will be saved to: $LOG_DIR"
}

# Function to start Geth node
start_geth_node() {
    print_step "Starting Geth node with EIP-8082 support..."

    if pgrep -f "geth.*--dev" > /dev/null; then
        print_warning "Geth dev node already running"
        return 0
    fi

    print_info "Starting Geth in background..."
    print_info "Geth log: $GETH_LOG"

    # Start Geth and capture its output
    nohup ./start-eip8082-dev.sh > "$GETH_LOG" 2>&1 &
    local geth_pid=$!

    # Give it a moment to start
    sleep 3

    # Check if the process is still running
    if ! kill -0 $geth_pid 2>/dev/null; then
        print_error "Geth process failed to start or died immediately"
        print_info "Checking startup logs..."
        if [ -f "$GETH_LOG" ]; then
            print_info "Geth startup log:"
            cat "$GETH_LOG"
        fi
        return 1
    fi

    echo $geth_pid > "$LOG_DIR/geth.pid"

    print_info "Waiting for Geth to start..."
    local attempts=0
    while [ $attempts -lt 30 ]; do
        if curl -s -X POST \
            -H "Content-Type: application/json" \
            --data '{"jsonrpc":"2.0","method":"web3_clientVersion","params":[],"id":1}' \
            http://127.0.0.1:8545 > /dev/null 2>&1; then
            break
        fi
        sleep 2
        ((attempts++))

        # Show progress and check if process is still running
        if [ $((attempts % 5)) -eq 0 ]; then
            print_info "Still waiting... (attempt $attempts/30)"
            if [ -f "$LOG_DIR/geth.pid" ]; then
                local pid=$(cat "$LOG_DIR/geth.pid")
                if ! kill -0 $pid 2>/dev/null; then
                    print_error "Geth process died! Checking logs..."
                    print_info "Last 10 lines of Geth log:"
                    tail -10 "$GETH_LOG" || echo "No log file found"
                    return 1
                fi
            fi
        fi
    done

    if [ $attempts -eq 30 ]; then
        print_error "Geth failed to start within timeout (60 seconds)"
        print_info "Checking Geth logs for errors..."
        if [ -f "$GETH_LOG" ]; then
            print_info "Last 20 lines of Geth log:"
            tail -20 "$GETH_LOG"
        else
            print_error "No Geth log file found at $GETH_LOG"
        fi
        return 1
    fi

    print_success "Geth node started successfully (PID: $geth_pid)"
    print_info "RPC endpoint: http://127.0.0.1:8545"
    print_info "WebSocket endpoint: ws://127.0.0.1:8546"
    return 0
}

# Function to deploy contracts
deploy_contracts() {
    print_step "Deploying EIP-8082 contracts..."

    if ! curl -s -X POST \
        -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"web3_clientVersion","params":[],"id":1}' \
        http://127.0.0.1:8545 > /dev/null 2>&1; then
        print_error "Geth node is not running"
        print_info "Please start the node first with: ./run-eip8082-demo.sh start"
        return 1
    fi

    if [ -f "./deploy-eip8082-contracts.sh" ]; then
        ./deploy-eip8082-contracts.sh 2>&1 | tee "$DEPLOY_LOG"
        local deploy_status=${PIPESTATUS[0]}

        if [ $deploy_status -eq 0 ]; then
            print_success "Contracts deployed successfully"
            return 0
        else
            print_error "Contract deployment failed"
            return 1
        fi
    else
        print_error "Deployment script not found"
        return 1
    fi
}

# Function to run tests
run_tests() {
    print_step "Running EIP-8082 functionality tests..."

    if ! curl -s -X POST \
        -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"web3_clientVersion","params":[],"id":1}' \
        http://127.0.0.1:8545 > /dev/null 2>&1; then
        print_error "Geth node is not running"
        print_info "Please start the node first with: ./run-eip8082-demo.sh start"
        return 1
    fi

    if [ -f "./test-eip8082.sh" ]; then
        ./test-eip8082.sh 2>&1 | tee "$TEST_LOG"
        local test_status=${PIPESTATUS[0]}

        if [ $test_status -eq 0 ]; then
            print_success "Tests completed successfully"
            return 0
        else
            print_warning "Some tests may have failed (check logs for details)"
            return 1
        fi
    else
        print_error "Test script not found"
        return 1
    fi
}

# Function to stop Geth node
stop_geth_node() {
    print_step "Stopping Geth node..."

    if [ -f "$LOG_DIR/geth.pid" ]; then
        local geth_pid=$(cat "$LOG_DIR/geth.pid")
        if kill -0 $geth_pid 2>/dev/null; then
            kill -TERM $geth_pid
            print_info "Sent termination signal to Geth (PID: $geth_pid)"

            # Wait for graceful shutdown
            local attempts=0
            while kill -0 $geth_pid 2>/dev/null && [ $attempts -lt 10 ]; do
                sleep 1
                ((attempts++))
            done

            if kill -0 $geth_pid 2>/dev/null; then
                kill -KILL $geth_pid
                print_warning "Force killed Geth process"
            fi
        fi
        rm -f "$LOG_DIR/geth.pid"
    fi

    # Fallback: kill any remaining geth processes
    pkill -f "geth.*--dev" 2>/dev/null || true

    print_success "Geth node stopped"
}

# Function to clean up
cleanup() {
    print_step "Cleaning up demo files..."

    stop_geth_node

    # Remove generated files
    rm -rf ./dev-data
    rm -rf ./eip8082-deployments
    rm -rf ./eip8082-test-results
    rm -rf "$LOG_DIR"

    print_success "Cleanup completed"
}

# Function to check status
check_status() {
    print_step "Checking EIP-8082 demo status..."

    echo ""
    print_info "Geth Node Status:"
    if pgrep -f "geth.*--dev" > /dev/null; then
        print_success "✓ Geth node is running"

        if curl -s -X POST \
            -H "Content-Type: application/json" \
            --data '{"jsonrpc":"2.0","method":"web3_clientVersion","params":[],"id":1}' \
            http://127.0.0.1:8545 > /dev/null 2>&1; then
            print_success "✓ RPC endpoint is accessible"
        else
            print_warning "⚠ Geth is running but RPC is not accessible"
        fi
    else
        print_warning "⚠ Geth node is not running"
    fi

    echo ""
    print_info "File Status:"

    if [ -d "./dev-data" ]; then
        print_success "✓ Blockchain data directory exists"
    else
        print_info "○ No blockchain data directory"
    fi

    if [ -d "./eip8082-deployments" ]; then
        local contract_count=$(find ./eip8082-deployments -name "deployment.txt" | wc -l)
        print_success "✓ Contract deployments found ($contract_count contracts)"
    else
        print_info "○ No contract deployments found"
    fi

    if [ -d "./eip8082-test-results" ]; then
        print_success "✓ Test results available"
    else
        print_info "○ No test results found"
    fi

    echo ""
}

# Function to show interactive menu
show_interactive_menu() {
    while true; do
        echo ""
        print_header "EIP-8082 Interactive Demo Menu"
        echo ""
        echo "1) Start Geth node"
        echo "2) Deploy contracts"
        echo "3) Run tests"
        echo "4) Check status"
        echo "5) View logs"
        echo "6) Stop Geth node"
        echo "7) Clean up"
        echo "8) Exit"
        echo ""
        read -p "Select an option (1-8): " choice

        case $choice in
            1) start_geth_node ;;
            2) deploy_contracts ;;
            3) run_tests ;;
            4) check_status ;;
            5)
                echo "Log files in $LOG_DIR:"
                ls -la "$LOG_DIR/" 2>/dev/null || echo "No logs found"
                ;;
            6) stop_geth_node ;;
            7) cleanup ;;
            8)
                print_info "Exiting demo..."
                stop_geth_node
                exit 0
                ;;
            *) print_error "Invalid option. Please select 1-8." ;;
        esac

        if [ "$WAIT_FOR_INPUT" != "false" ]; then
            echo ""
            read -p "Press Enter to continue..."
        fi
    done
}

# Function to run full demo
run_full_demo() {
    print_header "Running Complete EIP-8082 Demo"

    local steps=("start_geth_node" "deploy_contracts" "run_tests")
    local step_names=("Starting Geth Node" "Deploying Contracts" "Running Tests")
    local failed_steps=()

    for i in "${!steps[@]}"; do
        echo ""
        print_header "Step $((i+1))/3: ${step_names[i]}"

        if ${steps[i]}; then
            print_success "Step $((i+1)) completed successfully"
        else
            print_error "Step $((i+1)) failed"
            failed_steps+=("${step_names[i]}")
        fi

        if [ "$WAIT_FOR_INPUT" != "false" ] && [ $i -lt $((${#steps[@]}-1)) ]; then
            echo ""
            read -p "Press Enter to continue to next step..."
        fi
    done

    echo ""
    print_header "Demo Complete"

    if [ ${#failed_steps[@]} -eq 0 ]; then
        print_success "All steps completed successfully! 🎉"
        print_info ""
        print_info "What's available now:"
        print_info "• Geth node running with EIP-8082 support"
        print_info "• EIP-8082 contracts deployed and ready"
        print_info "• Test results available for review"
        print_info ""
        print_info "Next steps:"
        print_info "• Connect to http://127.0.0.1:8545 for RPC calls"
        print_info "• Check deployment details in ./eip8082-deployments/"
        print_info "• Review test results in ./eip8082-test-results/"
        print_info "• Check logs in $LOG_DIR/"
    else
        print_warning "Demo completed with some failures:"
        for step in "${failed_steps[@]}"; do
            print_error "  - $step"
        done
        print_info "Check logs in $LOG_DIR/ for detailed error information"
    fi
}

# Parse command line arguments
VERBOSE=false
QUIET=false
WAIT_FOR_INPUT=true
COMMAND=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_usage
            exit 0
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -q|--quiet)
            QUIET=true
            shift
            ;;
        --no-wait)
            WAIT_FOR_INPUT=false
            shift
            ;;
        --log-dir)
            LOG_DIR="$2"
            shift 2
            ;;
        start|deploy|test|full|stop|clean|status|interactive)
            COMMAND="$1"
            shift
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Main execution
main() {
    cd "$SCRIPT_DIR"

    print_header "EIP-8082 (Contract Event Subscription) Demo"
    print_info "This demo showcases the EIP-8082 implementation in go-ethereum"
    echo ""

    setup_logging
    check_prerequisites

    case "$COMMAND" in
        start)
            start_geth_node
            ;;
        deploy)
            deploy_contracts
            ;;
        test)
            run_tests
            ;;
        full)
            run_full_demo
            ;;
        stop)
            stop_geth_node
            ;;
        clean)
            cleanup
            ;;
        status)
            check_status
            ;;
        interactive|"")
            show_interactive_menu
            ;;
    esac
}

# Trap to ensure cleanup on exit
trap 'stop_geth_node' EXIT

# Run main function
main "$@"
