# EIP-8082 Implementation Guide

This document provides a comprehensive guide to the EIP-8082 (Contract Event Subscription) implementation in this Go-Ethereum fork.

## Overview

EIP-8082 introduces a revolutionary mechanism for smart contracts to subscribe to events emitted by other contracts and automatically execute callback functions when those events occur. This enables real-time, on-chain reactions to blockchain events without requiring off-chain infrastructure.

## Table of Contents

1. [Architecture](#architecture)
2. [New Opcodes](#new-opcodes)
3. [Implementation Details](#implementation-details)
4. [Gas Model](#gas-model)
5. [Security Considerations](#security-considerations)
6. [Testing](#testing)
7. [Integration Guide](#integration-guide)
8. [Troubleshooting](#troubleshooting)

## Architecture

### High-Level Design

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Event Emitter │    │   Subscription  │    │   Subscriber    │
│    Contract     │    │    Manager      │    │    Contract     │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         │ 1. emit subscribable  │                       │
         │    event              │                       │
         ├──────────────────────►│                       │
         │                       │ 2. notify subscribers │
         │                       ├──────────────────────►│
         │                       │                       │
         │                       │ 3. execute callbacks  │
         │                       │    (isolated context) │
         │                       ├──────────────────────►│
```

### Core Components

1. **Subscription Manager**: Manages active subscriptions and handles callback execution
2. **Event Dispatcher**: Routes events to appropriate subscribers
3. **Gas Accounting System**: Handles gas deposits, refunds, and callback execution costs
4. **Isolation Engine**: Ensures callback failures don't affect main transaction

## New Opcodes

### SUBSCRIBE (0xF8)

Subscribes to events emitted by a target contract.

**Stack Input:**
```
[eventHash, contractAddress, subscriberAddress, callbackSelector, gasLimit, value]
```

**Stack Output:**
```
[subscriptionId]
```

**Gas Cost:** `20,000 + SSTORE_SET_GAS` (for new subscription storage)

**Implementation Location:** `core/vm/instructions.go:opSubscribe()`

### UNSUBSCRIBE (0xF9)

Removes an active subscription.

**Stack Input:**
```
[subscriptionId, contractAddress]
```

**Stack Output:**
```
[success]
```

**Gas Cost:** `5,000 + SSTORE_RESET_GAS` (storage refund)

**Implementation Location:** `core/vm/instructions.go:opUnsubscribe()`

### NOTIFYSUBSCRIBERS (0xFA)

Notifies all subscribers of an event (called automatically by LOG opcodes for subscribable events).

**Stack Input:**
```
[eventHash, dataOffset, dataSize]
```

**Stack Output:**
```
[numNotified]
```

**Gas Cost:** `2,000 + (500 * numSubscribers)`

**Implementation Location:** `core/vm/instructions.go:opNotifySubscribers()`

## Implementation Details

### File Structure

```
go-ethereum/
├── core/
│   ├── state/
│   │   ├── statedb.go              # Subscription state management
│   │   └── subscription.go         # Subscription data structures
│   ├── vm/
│   │   ├── eips.go                 # EIP-8082 activation
│   │   ├── instructions.go         # New opcode implementations
│   │   ├── opcodes.go              # Opcode definitions
│   │   └── subscription_manager.go # Core subscription logic
│   └── blockchain.go               # Event notification integration
├── internal/ethapi/
│   └── subscription_api.go         # RPC methods for subscriptions
└── rpc/
    └── subscription_types.go       # RPC type definitions
```

### Core Data Structures

#### Subscription

```go
type Subscription struct {
    ID              common.Hash     // Unique subscription ID
    EventHash       common.Hash     // Keccak256 of event signature
    TargetContract  common.Address  // Contract being monitored
    Subscriber      common.Address  // Subscribing contract
    CallbackSelector [4]byte        // Function selector for callback
    GasLimit        uint64          // Max gas for callback execution
    GasDeposit      *big.Int        // Deposited gas funds
    CreatedAt       uint64          // Block number when created
    Active          bool            // Whether subscription is active
}
```

#### SubscriptionManager

```go
type SubscriptionManager struct {
    subscriptions map[common.Hash]*Subscription
    eventIndex    map[common.Hash][]common.Hash  // eventHash -> subscriptionIDs
    contractIndex map[common.Address][]common.Hash // contract -> subscriptionIDs
    mu            sync.RWMutex
}
```

### Opcode Implementation

#### SUBSCRIBE Implementation

```go
func opSubscribe(pc *uint64, interpreter *EVMInterpreter, scope *ScopeContext) ([]byte, error) {
    stack := scope.Stack
    
    // Pop parameters from stack
    eventHash := common.Hash(stack.pop().Bytes32())
    contractAddr := common.Address(stack.pop().Bytes20())
    subscriberAddr := common.Address(stack.pop().Bytes20())
    callbackSelector := stack.pop().Bytes()[:4]
    gasLimit := stack.pop().Uint64()
    value := stack.pop()
    
    // Validate parameters
    if gasLimit == 0 || gasLimit > interpreter.evm.Context.GasLimit {
        return nil, ErrInvalidGasLimit
    }
    
    if value.Cmp(common.Big0) < 0 {
        return nil, ErrInsufficientFunds
    }
    
    // Create subscription
    subscription := &Subscription{
        ID:               generateSubscriptionID(contractAddr, eventHash, subscriberAddr),
        EventHash:        eventHash,
        TargetContract:   contractAddr,
        Subscriber:       subscriberAddr,
        CallbackSelector: [4]byte(callbackSelector),
        GasLimit:         gasLimit,
        GasDeposit:       new(big.Int).Set(value),
        CreatedAt:        interpreter.evm.Context.BlockNumber.Uint64(),
        Active:           true,
    }
    
    // Store subscription
    if err := interpreter.evm.SubscriptionManager.AddSubscription(subscription); err != nil {
        return nil, err
    }
    
    // Charge gas for storage
    if err := interpreter.evm.UseGas(params.SstoreSetGas); err != nil {
        return nil, err
    }
    
    // Transfer gas deposit
    if value.Cmp(common.Big0) > 0 {
        interpreter.evm.StateDB.SubBalance(scope.Contract.Address(), value)
        interpreter.evm.StateDB.AddBalance(subscription.ID, value)
    }
    
    // Push subscription ID to stack
    stack.push(subscription.ID.Big())
    
    return nil, nil
}
```

### Event Notification System

#### Integration with LOG Opcodes

The LOG opcodes are modified to automatically notify subscribers for subscribable events:

```go
func makeLog(size int) executionFunc {
    return func(pc *uint64, interpreter *EVMInterpreter, scope *ScopeContext) ([]byte, error) {
        // ... existing LOG implementation ...
        
        // Check if this event is subscribable
        eventHash := topics[0] // First topic is event signature hash
        if interpreter.evm.SubscriptionManager.HasSubscribers(eventHash, scope.Contract.Address()) {
            // Notify subscribers
            numNotified := interpreter.evm.SubscriptionManager.NotifySubscribers(
                eventHash,
                scope.Contract.Address(),
                mStart,
                mSize,
                interpreter.evm.StateDB,
            )
            
            // Charge gas for notifications
            notificationCost := params.NotificationBaseGas + (params.NotificationPerSubscriberGas * numNotified)
            if err := interpreter.evm.UseGas(notificationCost); err != nil {
                return nil, err
            }
        }
        
        return nil, nil
    }
}
```

### Callback Execution

Callbacks are executed in an isolated context to prevent failures from affecting the main transaction:

```go
func (sm *SubscriptionManager) ExecuteCallback(
    subscription *Subscription,
    eventData []byte,
    statedb *StateDB,
) error {
    // Create isolated EVM context
    callbackEVM := &EVM{
        Context:       evm.Context,
        StateDB:       statedb.Copy(), // Isolated state
        chainConfig:   evm.chainConfig,
        depth:         evm.depth + 1,
    }
    
    // Prepare callback call
    input := make([]byte, 4+len(eventData))
    copy(input[:4], subscription.CallbackSelector[:])
    copy(input[4:], eventData)
    
    // Execute callback with gas limit
    ret, gasUsed, err := callbackEVM.Call(
        AccountRef(SUBSCRIPTION_DISPATCHER),
        subscription.Subscriber,
        input,
        subscription.GasLimit,
        big.NewInt(0),
    )
    
    // Handle callback result
    if err != nil {
        // Log callback failure but don't revert main transaction
        log.Debug("Callback execution failed", "subscription", subscription.ID, "error", err)
        return nil // Graceful failure
    }
    
    // Refund unused gas
    refund := subscription.GasLimit - gasUsed
    if refund > 0 {
        refundValue := new(big.Int).Mul(big.NewInt(int64(refund)), subscription.GasPrice)
        statedb.AddBalance(subscription.Subscriber, refundValue)
    }
    
    return nil
}
```

## Gas Model

### Gas Costs

| Operation | Base Cost | Additional Cost |
|-----------|-----------|-----------------|
| SUBSCRIBE | 20,000 | + SSTORE_SET_GAS (20,000) |
| UNSUBSCRIBE | 5,000 | + SSTORE_RESET_GAS (-15,000 refund) |
| NOTIFYSUBSCRIBERS | 2,000 | + (500 × num_subscribers) |
| Callback Execution | 0 | Paid from subscription deposit |

### Gas Accounting

1. **Subscription Creation**: Subscriber pays upfront gas cost + deposits gas for future callbacks
2. **Event Notification**: Event emitter pays notification costs
3. **Callback Execution**: Paid from subscription deposit, unused gas refunded

```go
type GasAccountingModel struct {
    SubscriptionBaseGas     uint64 // 20,000
    UnsubscriptionBaseGas   uint64 // 5,000
    NotificationBaseGas     uint64 // 2,000
    NotificationPerSubGas   uint64 // 500
    CallbackBaseGas         uint64 // 21,000 (like external call)
}
```

## Security Considerations

### Reentrancy Protection

Callbacks cannot perform subscriptions or unsubscriptions to prevent reentrancy attacks:

```go
func opSubscribe(pc *uint64, interpreter *EVMInterpreter, scope *ScopeContext) ([]byte, error) {
    // Check if we're in a callback context
    if interpreter.evm.depth > 0 && interpreter.evm.origin == SUBSCRIPTION_DISPATCHER {
        return nil, ErrReentrantSubscription
    }
    // ... rest of implementation
}
```

### Gas Limit Protection

Callbacks have strict gas limits to prevent DoS attacks:

```go
const (
    MaxCallbackGasLimit = 1000000 // 1M gas maximum
    MinGasDeposit      = 100000   // Minimum gas deposit required
)
```

### Authorization

Only the original subscriber can unsubscribe:

```go
func opUnsubscribe(pc *uint64, interpreter *EVMInterpreter, scope *ScopeContext) ([]byte, error) {
    subscription := sm.GetSubscription(subscriptionID)
    if subscription.Subscriber != scope.Contract.Address() {
        return nil, ErrUnauthorizedUnsubscribe
    }
    // ... rest of implementation
}
```

## Testing

### Unit Tests

Location: `core/vm/subscription_test.go`

```go
func TestSubscribeOpcode(t *testing.T) {
    tests := []struct {
        name           string
        eventHash      common.Hash
        contractAddr   common.Address
        subscriber     common.Address
        gasLimit       uint64
        gasDeposit     *big.Int
        expectError    bool
        expectedSubID  common.Hash
    }{
        {
            name:          "Valid subscription",
            eventHash:     crypto.Keccak256Hash([]byte("Transfer(address,address,uint256)")),
            contractAddr:  common.HexToAddress("0x1234..."),
            subscriber:    common.HexToAddress("0x5678..."),
            gasLimit:      100000,
            gasDeposit:    big.NewInt(1000000000000000000), // 1 ETH
            expectError:   false,
        },
        // ... more test cases
    }
    
    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            // Test implementation
        })
    }
}
```

### Integration Tests

Location: `tests/subscription_test.go`

Tests complete subscription lifecycle:
1. Deploy contracts with subscribable events
2. Create subscriptions
3. Emit events and verify callbacks
4. Test gas accounting
5. Test failure scenarios

### End-to-End Tests

Use the demo scripts to test real scenarios:

```bash
# Run complete test suite
./run-eip8082-demo.sh full

# Individual test components
./test-eip8082.sh
```

## Integration Guide

### For dApp Developers

1. **Use Compatible Solidity Compiler**:
   ```bash
   # Clone EIP-8082 Solidity fork
   git clone https://github.com/bitcoinbrisbane/solidity.git
   cd solidity
   git checkout claude/verify-solidity-eip-alignment-013A1gVMfHnkNGYriiDHGLKf
   ```

2. **Deploy Contracts with Subscribable Events**:
   ```solidity
   contract PriceOracle {
       event subscribable PriceUpdated(uint256 price) gasHint(50000);
       
       function updatePrice(uint256 _price) external {
           emit PriceUpdated(_price);
       }
   }
   ```

3. **Create Subscriber Contracts**:
   ```solidity
   contract PriceConsumer {
       constructor(address oracle) payable {
           subscribe PriceOracle(oracle).PriceUpdated(price)
               with onPriceUpdate(price)
               gasLimit 100000
               gasPrice 20 gwei;
       }
       
       function onPriceUpdate(uint256 price) external payable onlyEventCallback {
           // React to price update
       }
   }
   ```

### For Node Operators

1. **Enable EIP-8082**:
   ```bash
   geth --dev --eip8082 # Automatically enabled in dev mode
   ```

2. **Monitor Subscription Activity**:
   ```bash
   # View active subscriptions
   curl -X POST -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"eth_getSubscriptions","params":["0x..."],"id":1}' \
        http://localhost:8545
   ```

### RPC Methods

#### eth_getSubscriptions

Returns all active subscriptions for an address:

```json
{
    "jsonrpc": "2.0",
    "method": "eth_getSubscriptions",
    "params": ["0x742d35Cc6635C0532925a3b8D6B3B0B7C6e9C3a9"],
    "id": 1
}
```

#### eth_getSubscription

Returns details for a specific subscription:

```json
{
    "jsonrpc": "2.0",
    "method": "eth_getSubscription", 
    "params": ["0x123..."],
    "id": 1
}
```

#### eth_getCallbackHistory

Returns callback execution history:

```json
{
    "jsonrpc": "2.0",
    "method": "eth_getCallbackHistory",
    "params": ["0x123...", "0x100", "0x200"],
    "id": 1
}
```

## Troubleshooting

### Common Issues

#### Subscription Not Triggered

**Symptoms**: Events are emitted but callbacks aren't executed

**Debugging**:
1. Check if event is marked as `subscribable` in Solidity
2. Verify subscription was created successfully
3. Ensure sufficient gas deposit for callbacks
4. Check callback function signature matches event parameters

```bash
# Check subscription status
curl -X POST --data '{"jsonrpc":"2.0","method":"eth_getSubscription","params":["0x..."],"id":1}' \
     http://localhost:8545
```

#### Callback Execution Fails

**Symptoms**: Callbacks consistently fail or revert

**Common Causes**:
- Insufficient gas limit
- Callback function not marked `payable`
- Missing `onlyEventCallback` modifier
- Logic errors in callback function

**Fix**:
```solidity
function onEvent(uint256 param) 
    external 
    payable 
    onlyEventCallback // Required!
{
    // Callback logic
}
```

#### Gas Issues

**Symptoms**: High gas costs or out-of-gas errors

**Solutions**:
1. Optimize callback functions
2. Increase gas limit for subscriptions
3. Use appropriate `gasHint` values in events
4. Monitor gas usage patterns

### Debug Mode

Enable detailed logging:

```bash
geth --dev --verbosity 5 --vmodule subscription=6
```

### Performance Monitoring

Monitor subscription system performance:

```bash
# Check subscription metrics
curl -X POST --data '{"jsonrpc":"2.0","method":"debug_subscriptionStats","params":[],"id":1}' \
     http://localhost:8545
```

## Future Enhancements

### Planned Features

1. **Subscription Marketplace**: Allow gas sponsors to pay for subscriptions
2. **Conditional Subscriptions**: Subscribe only when conditions are met
3. **Batch Notifications**: Optimize gas for multiple subscribers
4. **Cross-chain Subscriptions**: Subscribe to events on other chains

### Performance Optimizations

1. **Subscription Indexing**: Optimize subscription lookup performance
2. **Callback Batching**: Execute multiple callbacks in single transaction
3. **Gas Estimation**: Better gas estimation for callback execution

## Contributing

### Development Workflow

1. Fork the repository
2. Create feature branch
3. Implement changes with tests
4. Run test suite: `./test-eip8082.sh`
5. Submit pull request

### Code Style

Follow existing Go-Ethereum conventions:
- Use gofmt for formatting
- Add comprehensive tests
- Document public APIs
- Include benchmarks for performance-critical code

## References

- [EIP-8082 Specification](https://github.com/ethereum/EIPs)
- [Solidity EIP-8082 Implementation](https://github.com/bitcoinbrisbane/solidity)
- [Go-Ethereum Documentation](https://geth.ethereum.org/docs)
- [EVM Instruction Set](https://ethereum.org/en/developers/docs/evm/opcodes/)

---

**Last Updated**: December 30, 2025
**Version**: 1.0.0
**Author**: Bitcoin Brisbane Team