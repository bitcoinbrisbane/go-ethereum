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

package types

import (
	"math/big"

	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/crypto"
	"github.com/ethereum/go-ethereum/rlp"
)

// Subscription represents an on-chain event subscription as defined in EIP-8082.
// When a subscribable event is emitted, the subscription's callback is executed
// in an isolated context with gas bounded by the subscription parameters.
type Subscription struct {
	// ID is the unique identifier for this subscription
	ID common.Hash `json:"id"`

	// TargetContract is the address of the contract emitting the event
	TargetContract common.Address `json:"targetContract"`

	// EventSignature is the keccak256 hash of the event signature
	EventSignature common.Hash `json:"eventSignature"`

	// SubscriberContract is the address of the contract that created the subscription
	SubscriberContract common.Address `json:"subscriberContract"`

	// CallbackAddress is the address of the contract containing the callback function
	// (usually the same as SubscriberContract)
	CallbackAddress common.Address `json:"callbackAddress"`

	// CallbackSelector is the 4-byte function selector for the callback function
	CallbackSelector [4]byte `json:"callbackSelector"`

	// GasLimit is the maximum gas allowed for callback execution
	GasLimit uint64 `json:"gasLimit"`

	// GasPrice is the gas price for callback execution (in wei)
	GasPrice *big.Int `json:"gasPrice"`

	// DepositBalance is the prepaid balance for callback execution
	DepositBalance *big.Int `json:"depositBalance"`

	// Active indicates whether this subscription is active
	Active bool `json:"active"`
}

// subscriptionRLP is the RLP encoding structure for subscriptions
type subscriptionRLP struct {
	TargetContract     common.Address
	EventSignature     common.Hash
	SubscriberContract common.Address
	CallbackAddress    common.Address
	CallbackSelector   [4]byte
	GasLimit           uint64
	GasPrice           *big.Int
	DepositBalance     *big.Int
	Active             bool
}

// EncodeRLP implements rlp.Encoder
func (s *Subscription) EncodeRLP(w rlp.RawWriter) error {
	return rlp.Encode(w, &subscriptionRLP{
		TargetContract:     s.TargetContract,
		EventSignature:     s.EventSignature,
		SubscriberContract: s.SubscriberContract,
		CallbackAddress:    s.CallbackAddress,
		CallbackSelector:   s.CallbackSelector,
		GasLimit:           s.GasLimit,
		GasPrice:           s.GasPrice,
		DepositBalance:     s.DepositBalance,
		Active:             s.Active,
	})
}

// DecodeRLP implements rlp.Decoder
func (s *Subscription) DecodeRLP(stream *rlp.Stream) error {
	var dec subscriptionRLP
	if err := stream.Decode(&dec); err != nil {
		return err
	}
	s.TargetContract = dec.TargetContract
	s.EventSignature = dec.EventSignature
	s.SubscriberContract = dec.SubscriberContract
	s.CallbackAddress = dec.CallbackAddress
	s.CallbackSelector = dec.CallbackSelector
	s.GasLimit = dec.GasLimit
	s.GasPrice = dec.GasPrice
	s.DepositBalance = dec.DepositBalance
	s.Active = dec.Active
	s.ID = ComputeSubscriptionID(dec.TargetContract, dec.EventSignature, dec.SubscriberContract)
	return nil
}

// ComputeSubscriptionID computes the unique subscription ID from its components
func ComputeSubscriptionID(target common.Address, eventSig common.Hash, subscriber common.Address) common.Hash {
	return crypto.Keccak256Hash(
		target.Bytes(),
		eventSig.Bytes(),
		subscriber.Bytes(),
	)
}

// GasCost calculates the total gas cost for one callback execution
func (s *Subscription) GasCost() *big.Int {
	return new(big.Int).Mul(new(big.Int).SetUint64(s.GasLimit), s.GasPrice)
}

// HasSufficientDeposit checks if the deposit balance is sufficient for one callback
func (s *Subscription) HasSufficientDeposit() bool {
	return s.DepositBalance.Cmp(s.GasCost()) >= 0
}

// DeductGas deducts the gas cost from the deposit balance
func (s *Subscription) DeductGas() bool {
	if !s.HasSufficientDeposit() {
		return false
	}
	s.DepositBalance.Sub(s.DepositBalance, s.GasCost())
	return true
}

// RefundGas refunds unused gas to the deposit balance
func (s *Subscription) RefundGas(gasUsed uint64) {
	unusedGas := s.GasLimit - gasUsed
	refund := new(big.Int).Mul(new(big.Int).SetUint64(unusedGas), s.GasPrice)
	s.DepositBalance.Add(s.DepositBalance, refund)
}

// CallbackExecution represents a pending callback execution
type CallbackExecution struct {
	// SubscriptionID identifies the subscription that triggered this callback
	SubscriptionID common.Hash

	// SubscriberAddress is the address of the subscriber contract
	SubscriberAddress common.Address

	// CallbackAddress is the address to call
	CallbackAddress common.Address

	// CallbackData is the ABI-encoded callback data (selector + parameters)
	CallbackData []byte

	// GasLimit is the gas limit for this callback
	GasLimit uint64

	// GasPrice is the gas price for this callback
	GasPrice *big.Int

	// OriginalOrigin is the tx.origin from the original transaction
	OriginalOrigin common.Address
}

// SubscriptionLog represents a log entry for subscription events
type SubscriptionLog struct {
	// SubscriptionID identifies the subscription
	SubscriptionID common.Hash

	// Event type (created, deleted, callback_success, callback_failed, insufficient_deposit)
	EventType string

	// BlockNumber when the event occurred
	BlockNumber uint64

	// Additional data (e.g., error message for failures)
	Data []byte
}
