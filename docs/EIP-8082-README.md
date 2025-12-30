# EIP-8082 Demo Setup Guide

This guide helps you run and test the EIP-8082 (Contract Event Subscription) implementation in go-ethereum.

## 🚀 Quick Start

### Prerequisites

- Go 1.21+ installed
- Basic development tools (make, git, curl, jq, bc)
- Solidity compiler (optional, for advanced contract testing)

### 1. Build Geth with EIP-8082 Support

```bash
make geth
```

### 2. Run Complete Demo

```bash
./run-eip8082-demo.sh full
```

This will:
1. Start a Geth development node with EIP-8082 enabled
2. Deploy EIP-8082 example contracts
3. Run comprehensive functionality tests

## 📋 Available Scripts

### Core Scripts

| Script | Purpose |
|--------|---------|
| `run-eip8082-demo.sh` | Master orchestration script |
| `start-eip8082-dev.sh` | Start Geth node with EIP-8082 support |
| `deploy-eip8082-contracts.sh` | Deploy EIP-8082 example contracts |
| `test-eip8082.sh` | Run EIP-8082 functionality tests |

### Usage Examples

```bash
# Interactive menu
./run-eip8082-demo.sh

# Start just the node
./run-eip8082-demo.sh start

# Deploy contracts (requires running node)
./run-eip8082-demo.sh deploy

# Run tests (requires running node)
./run-eip8082-demo.sh test

# Check status
./run-eip8082-demo.sh status

# Clean up everything
./run-eip8082-demo.sh clean

# Show help
./run-eip8082-demo.sh --help
```

## 🔧 EIP-8082 Features

### New Opcodes

- **SUBSCRIBE (0xF8)**: Subscribe to contract events
- **UNSUBSCRIBE (0xF9)**: Unsubscribe from contract events  
- **NOTIFYSUBSCRIBERS (0xFA)**: Notify event subscribers

### Node Configuration

The development node runs with:
- Chain ID: 1337
- HTTP RPC: http://127.0.0.1:8545
- WebSocket: ws://127.0.0.1:8546
- Pre-funded developer account
- Instant mining (1 second block time)
- All EIPs enabled including EIP-8082

## 📁 Directory Structure

```
go-ethereum/
├── run-eip8082-demo.sh           # Master demo script
├── start-eip8082-dev.sh          # Node startup script
├── deploy-eip8082-contracts.sh   # Contract deployment
├── test-eip8082.sh              # Functionality tests
├── dev-data/                    # Blockchain data (created)
├── eip8082-deployments/         # Contract deployment info (created)
├── eip8082-test-results/        # Test results (created)
└── eip8082-demo-logs/          # Demo logs (created)

../solidity/test/eip8802-examples/  # Example contracts
├── SimpleToken.sol              # Basic ERC-20 with EIP-8082
├── PriceOracle.sol             # Price oracle with subscriptions
├── TokenWatcher.sol            # Event monitoring contract
├── DerivedProtocol.sol         # Complex protocol example
└── ComprehensiveTest.sol       # Full feature test contract
```

## 🧪 Testing EIP-8082

### Automated Tests

The test suite verifies:
- Basic EVM functionality 
- EIP-8082 opcode recognition
- Gas estimation for new opcodes
- Event subscription mechanisms
- Contract deployment and interaction

### Manual Testing

1. **Start the node:**
   ```bash
   ./start-eip8082-dev.sh
   ```

2. **Connect to console:**
   The node starts with an interactive console where you can:
   ```javascript
   // Check accounts
   eth.accounts
   
   // Check balance
   web3.fromWei(eth.getBalance(eth.accounts[0]), 'ether')
   
   // Send test transaction
   eth.sendTransaction({from: eth.accounts[0], to: '0x...', value: web3.toWei(1, 'ether')})
   ```

3. **Deploy and test contracts:**
   ```bash
   ./deploy-eip8082-contracts.sh
   ```

## 🔍 Troubleshooting

### Common Issues

**Geth fails to start:**
- Ensure you built with `make geth`
- Check if port 8545 is already in use
- Review logs in `eip8082-demo-logs/`

**Contract deployment fails:**
- Verify Geth node is running
- Check account has sufficient balance
- Ensure Solidity compiler is available

**Tests show warnings:**
- EIP-8082 opcodes may not be fully implemented yet
- Some tests expect specific opcode behaviors
- Check test logs for detailed error messages

### Log Files

All operations are logged to `eip8082-demo-logs/`:
- `geth_TIMESTAMP.log` - Node startup and runtime logs
- `deploy_TIMESTAMP.log` - Contract deployment logs  
- `test_TIMESTAMP.log` - Test execution logs

### Cleanup

To reset everything:
```bash
./run-eip8082-demo.sh clean
```

This removes:
- Blockchain data directory
- Deployed contract information
- Test results
- Log files

## 🌐 Network Details

### Development Network
- **Network ID**: 1337
- **Chain ID**: 1337  
- **Consensus**: Proof of Authority (dev mode)
- **Block Time**: 1 second
- **Gas Limit**: 30M gas
- **Pre-funded Account**: Available via `eth.accounts[0]`

### RPC Endpoints
- **HTTP**: http://127.0.0.1:8545
- **WebSocket**: ws://127.0.0.1:8546
- **Available APIs**: eth, web3, net, debug, txpool, admin, miner, personal

## 📚 EIP-8082 Resources

- **EIP Specification**: [EIP-8082 GitHub](https://github.com/ethereum/EIPs)
- **Implementation**: This go-ethereum fork includes the core EVM changes
- **Example Contracts**: Located in `../solidity/test/eip8802-examples/`
- **Test Documentation**: Check individual contract files for usage examples

## 🤝 Contributing

To extend the demo or fix issues:

1. **Core EVM changes**: Modify files in `core/vm/`
2. **RPC additions**: Update files in `internal/ethapi/` and `rpc/`
3. **Test contracts**: Add to `../solidity/test/eip8802-examples/`
4. **Demo scripts**: Update the bash scripts in this directory

## ⚠️ Important Notes

- This is a development/testing implementation
- EIP-8082 may not be finalized - implementation details could change
- The demo node stores data locally in `dev-data/`
- All accounts are unlocked by default (development only!)
- The node runs with mining enabled for immediate transaction confirmation

## 🎯 Next Steps

After running the demo:

1. **Explore the contracts** - Check deployment details and interact with them
2. **Monitor events** - Use the WebSocket endpoint to watch for events
3. **Test custom contracts** - Deploy your own contracts using EIP-8082 features
4. **Review implementation** - Examine the core EVM changes in `core/vm/`
5. **Contribute feedback** - Report issues or suggest improvements

Happy testing! 🚀