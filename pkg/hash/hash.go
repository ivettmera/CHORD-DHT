package hash

import (
	"crypto/sha1"
	"fmt"
	"math/big"
	"strconv"
)

const (
	// M is the number of bits in the hash key space (SHA-1 = 160 bits)
	M = 160
	// MaxNodes is the maximum number of nodes in the hash ring (2^M)
	MaxNodes = 1 << M
)

// Hash represents a position on the Chord hash ring
type Hash struct {
	value *big.Int
}

// NewHash creates a new Hash from a big.Int value
func NewHash(value *big.Int) *Hash {
	if value == nil {
		value = big.NewInt(0)
	}
	// Ensure the value is within the hash ring bounds
	maxValue := new(big.Int).Lsh(big.NewInt(1), M) // 2^M
	value.Mod(value, maxValue)
	return &Hash{value: new(big.Int).Set(value)}
}

// NewHashFromString creates a new Hash by hashing a string
func NewHashFromString(s string) *Hash {
	hasher := sha1.New()
	hasher.Write([]byte(s))
	hashBytes := hasher.Sum(nil)
	
	// Convert bytes to big.Int
	value := new(big.Int).SetBytes(hashBytes)
	return NewHash(value)
}

// NewHashFromHex creates a new Hash from a hex string
func NewHashFromHex(hexStr string) (*Hash, error) {
	value := new(big.Int)
	_, ok := value.SetString(hexStr, 16)
	if !ok {
		return nil, fmt.Errorf("invalid hex string: %s", hexStr)
	}
	return NewHash(value), nil
}

// String returns the hex representation of the hash
func (h *Hash) String() string {
	return h.value.Text(16)
}

// Bytes returns the byte representation of the hash
func (h *Hash) Bytes() []byte {
	return h.value.Bytes()
}

// BigInt returns a copy of the underlying big.Int
func (h *Hash) BigInt() *big.Int {
	return new(big.Int).Set(h.value)
}

// Add returns a new Hash that is the sum of this hash and the given value
func (h *Hash) Add(value *big.Int) *Hash {
	result := new(big.Int).Add(h.value, value)
	return NewHash(result)
}

// AddPowerOfTwo returns a new Hash that is this hash + 2^i (used for finger table)
func (h *Hash) AddPowerOfTwo(i int) *Hash {
	if i < 0 || i >= M {
		return NewHash(new(big.Int).Set(h.value))
	}
	
	powerOfTwo := new(big.Int).Lsh(big.NewInt(1), uint(i)) // 2^i
	return h.Add(powerOfTwo)
}

// Equal checks if two hashes are equal
func (h *Hash) Equal(other *Hash) bool {
	if other == nil {
		return false
	}
	return h.value.Cmp(other.value) == 0
}

// Less checks if this hash is less than the other hash
func (h *Hash) Less(other *Hash) bool {
	if other == nil {
		return false
	}
	return h.value.Cmp(other.value) < 0
}

// Distance calculates the clockwise distance from this hash to the target hash
func (h *Hash) Distance(target *Hash) *big.Int {
	if target == nil {
		return big.NewInt(0)
	}
	
	distance := new(big.Int).Sub(target.value, h.value)
	maxValue := new(big.Int).Lsh(big.NewInt(1), M) // 2^M
	
	// If distance is negative, wrap around the ring
	if distance.Sign() < 0 {
		distance.Add(distance, maxValue)
	}
	
	return distance
}

// InRange checks if this hash is in the range (start, end] on the hash ring
// This handles the circular nature of the hash ring
func (h *Hash) InRange(start, end *Hash) bool {
	if start == nil || end == nil {
		return false
	}
	
	// If start == end, the range includes the entire ring except start
	if start.Equal(end) {
		return !h.Equal(start)
	}
	
	// If start < end, normal range check
	if start.Less(end) {
		return start.Less(h) && (h.Less(end) || h.Equal(end))
	}
	
	// If start > end, the range wraps around the ring
	// The hash is in range if it's > start OR <= end
	return start.Less(h) || h.Less(end) || h.Equal(end)
}

// InRangeExclusive checks if this hash is in the range (start, end) on the hash ring
func (h *Hash) InRangeExclusive(start, end *Hash) bool {
	if start == nil || end == nil {
		return false
	}
	
	// If start == end, the range is empty
	if start.Equal(end) {
		return false
	}
	
	// If start < end, normal range check
	if start.Less(end) {
		return start.Less(h) && h.Less(end)
	}
	
	// If start > end, the range wraps around the ring
	return start.Less(h) || h.Less(end)
}

// Copy creates a copy of the hash
func (h *Hash) Copy() *Hash {
	return NewHash(new(big.Int).Set(h.value))
}

// GenerateID generates a unique ID for a node based on its address
func GenerateID(address string) *Hash {
	return NewHashFromString(address)
}

// FingerStart calculates the start of the i-th finger table entry
// finger[i].start = (n + 2^(i-1)) mod 2^m
func FingerStart(nodeID *Hash, i int) *Hash {
	if i <= 0 || i > M {
		return nodeID.Copy()
	}
	return nodeID.AddPowerOfTwo(i - 1)
}

// ParseNodeID parses a node ID from various formats (hex string, decimal string, etc.)
func ParseNodeID(idStr string) (*Hash, error) {
	// Try hex first
	if hash, err := NewHashFromHex(idStr); err == nil {
		return hash, nil
	}
	
	// Try decimal
	if value, err := strconv.ParseInt(idStr, 10, 64); err == nil {
		return NewHash(big.NewInt(value)), nil
	}
	
	// Fall back to hashing the string
	return NewHashFromString(idStr), nil
}