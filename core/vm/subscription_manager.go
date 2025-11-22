// Copyright 2025 The go-ethereum Authors
// This file is part of the go-ethereum library.
//
// The go-ethereum library is free software: you can redistribute it and/or modify
// it under the terms of the GNU Lesser General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// The go-ethereum library is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Lesser General Public License for more details.
//
// You should have received a copy of the GNU Lesser General Public License
// along with the go-ethereum library. If not, see <http://www.gnu.org/licenses/>.

package vm

import (
	"math/big"

	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/types"
	"github.com/ethereum/go-ethereum/params"
)

// SubscriptionManager handles on-chain event subscriptions as per EIP-8082.
// It manages subscription creation, deletion, notification, and callback execution.
type SubscriptionManager struct {
	statedb StateDB
}

// NewSubscriptionManager creates a new subscription manager
func NewSubscriptionManager(statedb StateDB) *SubscriptionManager {
	return &SubscriptionManager{
		statedb: statedb,
	}
}

// Subscribe creates a new event subscription
// Returns the subscription ID and any error
func (sm *SubscriptionManager) Subscribe(
	target common.Address,
	eventSig common.Hash,
	subscriber common.Address,
	callback common.Address,
	selector [4]byte,
	gasLimit uint64,
	gasPrice *big.Int,
) (common.Hash, error) {
	// Compute subscription ID
	subID := types.ComputeSubscriptionID(target, eventSig, subscriber)

	// Check if subscription already exists
	if existing := sm.statedb.GetSubscription(subID); existing != nil && existing.Active {
		// Subscription already exists, return existing ID
		return subID, nil
	}

	// Create new subscription
	sub := &types.Subscription{
		ID:                 subID,
		TargetContract:     target,
		EventSignature:     eventSig,
		SubscriberContract: subscriber,
		CallbackAddress:    callback,
		CallbackSelector:   selector,
		GasLimit:           gasLimit,
		GasPrice:           gasPrice,
		DepositBalance:     big.NewInt(0),
		Active:             true,
	}

	// Store subscription in state
	sm.statedb.SetSubscription(subID, sub)

	// Emit subscription created log
	sm.statedb.AddLog(&types.Log{
		Address: params.SubscriptionManagerAddress,
		Topics: []common.Hash{
			common.BytesToHash([]byte("SubscriptionCreated")),
			subID,
			common.BytesToHash(target.Bytes()),
			common.BytesToHash(subscriber.Bytes()),
		},
		Data: eventSig.Bytes(),
	})

	return subID, nil
}

// Unsubscribe removes an event subscription
func (sm *SubscriptionManager) Unsubscribe(
	target common.Address,
	eventSig common.Hash,
	subscriber common.Address,
) error {
	// Compute subscription ID
	subID := types.ComputeSubscriptionID(target, eventSig, subscriber)

	// Get subscription
	sub := sm.statedb.GetSubscription(subID)
	if sub == nil || !sub.Active {
		// Subscription doesn't exist or already inactive
		return nil
	}

	// Mark as inactive
	sub.Active = false
	sm.statedb.SetSubscription(subID, sub)

	// Emit subscription removed log
	sm.statedb.AddLog(&types.Log{
		Address: params.SubscriptionManagerAddress,
		Topics: []common.Hash{
			common.BytesToHash([]byte("SubscriptionRemoved")),
			subID,
		},
	})

	return nil
}

// NotifySubscribers notifies all subscribers of an event emission
// Returns the callback executions to be processed
func (sm *SubscriptionManager) NotifySubscribers(
	target common.Address,
	eventSig common.Hash,
	eventData []byte,
	origin common.Address,
) []*types.CallbackExecution {
	// Get all subscribers for this event
	subscribers := sm.statedb.GetSubscribers(target, eventSig)

	callbacks := make([]*types.CallbackExecution, 0, len(subscribers))

	for _, sub := range subscribers {
		if !sub.Active {
			continue
		}

		// Check if subscriber has sufficient deposit
		if !sub.HasSufficientDeposit() {
			// Insufficient balance, skip and log
			sm.statedb.AddLog(&types.Log{
				Address: params.SubscriptionManagerAddress,
				Topics: []common.Hash{
					common.BytesToHash([]byte("InsufficientDeposit")),
					sub.ID,
				},
			})
			continue
		}

		// Deduct gas from deposit
		if !sub.DeductGas() {
			continue
		}

		// Update subscription in state
		sm.statedb.SetSubscription(sub.ID, sub)

		// Build callback data (selector + event data)
		callbackData := append(sub.CallbackSelector[:], eventData...)

		// Create callback execution
		callbacks = append(callbacks, &types.CallbackExecution{
			SubscriptionID:    sub.ID,
			SubscriberAddress: sub.SubscriberContract,
			CallbackAddress:   sub.CallbackAddress,
			CallbackData:      callbackData,
			GasLimit:          sub.GasLimit,
			GasPrice:          sub.GasPrice,
			OriginalOrigin:    origin,
		})
	}

	return callbacks
}

// Deposit adds funds to a subscription's deposit balance
func (sm *SubscriptionManager) Deposit(subID common.Hash, amount *big.Int) error {
	sub := sm.statedb.GetSubscription(subID)
	if sub == nil {
		return ErrInvalidSubscription
	}

	sub.DepositBalance.Add(sub.DepositBalance, amount)
	sm.statedb.SetSubscription(subID, sub)

	return nil
}

// Withdraw removes funds from a subscription's deposit balance
func (sm *SubscriptionManager) Withdraw(subID common.Hash, amount *big.Int) error {
	sub := sm.statedb.GetSubscription(subID)
	if sub == nil {
		return ErrInvalidSubscription
	}

	if sub.DepositBalance.Cmp(amount) < 0 {
		return ErrInsufficientDeposit
	}

	sub.DepositBalance.Sub(sub.DepositBalance, amount)
	sm.statedb.SetSubscription(subID, sub)

	return nil
}

// GetBalance returns the deposit balance for a subscription
func (sm *SubscriptionManager) GetBalance(subID common.Hash) *big.Int {
	sub := sm.statedb.GetSubscription(subID)
	if sub == nil {
		return big.NewInt(0)
	}
	return sub.DepositBalance
}

// GetSubscription returns subscription details
func (sm *SubscriptionManager) GetSubscription(subID common.Hash) *types.Subscription {
	return sm.statedb.GetSubscription(subID)
}

// RefundGas refunds unused gas to a subscription's deposit
func (sm *SubscriptionManager) RefundGas(subID common.Hash, gasUsed uint64) {
	sub := sm.statedb.GetSubscription(subID)
	if sub == nil {
		return
	}

	sub.RefundGas(gasUsed)
	sm.statedb.SetSubscription(subID, sub)
}

// UpdateSubscription updates subscription parameters
func (sm *SubscriptionManager) UpdateSubscription(
	subID common.Hash,
	gasLimit uint64,
	gasPrice *big.Int,
) error {
	sub := sm.statedb.GetSubscription(subID)
	if sub == nil || !sub.Active {
		return ErrInvalidSubscription
	}

	sub.GasLimit = gasLimit
	sub.GasPrice = gasPrice
	sm.statedb.SetSubscription(subID, sub)

	return nil
}
