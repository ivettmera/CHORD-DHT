package hash

import (
	"fmt"
	"math/big"
	"testing"
)

func TestNewHashFromString(t *testing.T) {
	tests := []struct {
		input    string
		expected string // first 8 chars of expected hex
	}{
		{"hello", "2cf24dba"},
		{"world", "486ea46c"},
		{"chord", "89b5f0a8"},
		{"", "e3b0c442"},
	}
	
	for _, test := range tests {
		hash := NewHashFromString(test.input)
		result := hash.String()
		if len(result) < 8 {
			t.Errorf("Hash too short for input %s", test.input)
			continue
		}
		if result[:8] != test.expected {
			t.Errorf("NewHashFromString(%s) = %s..., expected %s...", 
				test.input, result[:8], test.expected)
		}
	}
}

func TestNewHashFromHex(t *testing.T) {
	tests := []struct {
		input     string
		shouldErr bool
	}{
		{"0", false},
		{"1", false},
		{"ff", false},
		{"abc123", false},
		{"ABCDEF", false},
		{"xyz", true}, // invalid hex
		{"", false},   // empty string should work (becomes 0)
	}
	
	for _, test := range tests {
		hash, err := NewHashFromHex(test.input)
		if test.shouldErr {
			if err == nil {
				t.Errorf("NewHashFromHex(%s) should have failed", test.input)
			}
		} else {
			if err != nil {
				t.Errorf("NewHashFromHex(%s) failed: %v", test.input, err)
			}
			if hash == nil {
				t.Errorf("NewHashFromHex(%s) returned nil hash", test.input)
			}
		}
	}
}

func TestHashEqual(t *testing.T) {
	hash1 := NewHashFromString("test")
	hash2 := NewHashFromString("test")
	hash3 := NewHashFromString("different")
	
	if !hash1.Equal(hash2) {
		t.Error("Equal hashes should be equal")
	}
	
	if hash1.Equal(hash3) {
		t.Error("Different hashes should not be equal")
	}
	
	if hash1.Equal(nil) {
		t.Error("Hash should not equal nil")
	}
}

func TestHashLess(t *testing.T) {
	hash1 := NewHash(big.NewInt(100))
	hash2 := NewHash(big.NewInt(200))
	
	if !hash1.Less(hash2) {
		t.Error("100 should be less than 200")
	}
	
	if hash2.Less(hash1) {
		t.Error("200 should not be less than 100")
	}
	
	if hash1.Less(hash1) {
		t.Error("Hash should not be less than itself")
	}
	
	if hash1.Less(nil) {
		t.Error("Hash should not be less than nil")
	}
}

func TestHashDistance(t *testing.T) {
	// Test basic distance calculation
	hash1 := NewHash(big.NewInt(100))
	hash2 := NewHash(big.NewInt(200))
	
	distance := hash1.Distance(hash2)
	expected := big.NewInt(100)
	
	if distance.Cmp(expected) != 0 {
		t.Errorf("Distance from 100 to 200 should be 100, got %s", distance.String())
	}
	
	// Test wrap-around distance
	maxValue := new(big.Int).Lsh(big.NewInt(1), M) // 2^M
	hash3 := NewHash(new(big.Int).Sub(maxValue, big.NewInt(50))) // near end of ring
	hash4 := NewHash(big.NewInt(50)) // near start of ring
	
	distance2 := hash3.Distance(hash4)
	expected2 := big.NewInt(100) // 50 + 50 = 100
	
	if distance2.Cmp(expected2) != 0 {
		t.Errorf("Wrap-around distance should be 100, got %s", distance2.String())
	}
}

func TestHashInRange(t *testing.T) {
	// Test normal range (start < end)
	start := NewHash(big.NewInt(100))
	end := NewHash(big.NewInt(200))
	
	// Should be in range
	inRange := NewHash(big.NewInt(150))
	if !inRange.InRange(start, end) {
		t.Error("150 should be in range (100, 200]")
	}
	
	// Should not be in range
	outRange := NewHash(big.NewInt(50))
	if outRange.InRange(start, end) {
		t.Error("50 should not be in range (100, 200]")
	}
	
	// Test boundary conditions
	if end.InRange(start, end) {
		t.Error("End value should be in range (100, 200]")
	}
	
	if start.InRange(start, end) {
		t.Error("Start value should not be in range (100, 200]")
	}
	
	// Test wrap-around range (start > end)
	maxValue := new(big.Int).Lsh(big.NewInt(1), M)
	wrapStart := NewHash(new(big.Int).Sub(maxValue, big.NewInt(50)))
	wrapEnd := NewHash(big.NewInt(50))
	
	// Should be in wrap-around range
	inWrapRange1 := NewHash(new(big.Int).Sub(maxValue, big.NewInt(25)))
	if !inWrapRange1.InRange(wrapStart, wrapEnd) {
		t.Error("Value should be in wrap-around range")
	}
	
	inWrapRange2 := NewHash(big.NewInt(25))
	if !inWrapRange2.InRange(wrapStart, wrapEnd) {
		t.Error("Value should be in wrap-around range")
	}
	
	// Should not be in wrap-around range
	outWrapRange := NewHash(big.NewInt(100))
	if outWrapRange.InRange(wrapStart, wrapEnd) {
		t.Error("Value should not be in wrap-around range")
	}
}

func TestHashInRangeExclusive(t *testing.T) {
	start := NewHash(big.NewInt(100))
	end := NewHash(big.NewInt(200))
	
	// Should be in exclusive range
	inRange := NewHash(big.NewInt(150))
	if !inRange.InRangeExclusive(start, end) {
		t.Error("150 should be in range (100, 200)")
	}
	
	// Boundary values should not be in exclusive range
	if start.InRangeExclusive(start, end) {
		t.Error("Start value should not be in exclusive range")
	}
	
	if end.InRangeExclusive(start, end) {
		t.Error("End value should not be in exclusive range")
	}
	
	// Empty range (start == end)
	if inRange.InRangeExclusive(start, start) {
		t.Error("No value should be in empty range")
	}
}

func TestAddPowerOfTwo(t *testing.T) {
	hash := NewHash(big.NewInt(100))
	
	// Test adding 2^0 = 1
	result1 := hash.AddPowerOfTwo(0)
	expected1 := big.NewInt(101)
	if result1.BigInt().Cmp(expected1) != 0 {
		t.Errorf("100 + 2^0 should be 101, got %s", result1.String())
	}
	
	// Test adding 2^3 = 8
	result2 := hash.AddPowerOfTwo(3)
	expected2 := big.NewInt(108)
	if result2.BigInt().Cmp(expected2) != 0 {
		t.Errorf("100 + 2^3 should be 108, got %s", result2.String())
	}
	
	// Test invalid power (should return copy of original)
	result3 := hash.AddPowerOfTwo(-1)
	if !result3.Equal(hash) {
		t.Error("Invalid power should return copy of original hash")
	}
	
	result4 := hash.AddPowerOfTwo(M)
	if !result4.Equal(hash) {
		t.Error("Power >= M should return copy of original hash")
	}
}

func TestFingerStart(t *testing.T) {
	nodeID := NewHash(big.NewInt(100))
	
	// Test finger table start calculations
	for i := 1; i <= 5; i++ {
		fingerStart := FingerStart(nodeID, i)
		
		// Should be nodeID + 2^(i-1)
		expected := nodeID.AddPowerOfTwo(i - 1)
		
		if !fingerStart.Equal(expected) {
			t.Errorf("FingerStart(%d) incorrect: got %s, expected %s",
				i, fingerStart.String()[:16], expected.String()[:16])
		}
	}
	
	// Test boundary conditions
	finger0 := FingerStart(nodeID, 0)
	if !finger0.Equal(nodeID) {
		t.Error("FingerStart(0) should return copy of nodeID")
	}
	
	fingerTooLarge := FingerStart(nodeID, M+1)
	if !fingerTooLarge.Equal(nodeID) {
		t.Error("FingerStart(M+1) should return copy of nodeID")
	}
}

func TestParseNodeID(t *testing.T) {
	tests := []struct {
		input     string
		shouldErr bool
	}{
		{"abc123", false}, // hex
		{"123", false},    // decimal
		{"hello", false},  // string (will be hashed)
		{"", false},       // empty (will be hashed)
	}
	
	for _, test := range tests {
		hash, err := ParseNodeID(test.input)
		if test.shouldErr {
			if err == nil {
				t.Errorf("ParseNodeID(%s) should have failed", test.input)
			}
		} else {
			if err != nil {
				t.Errorf("ParseNodeID(%s) failed: %v", test.input, err)
			}
			if hash == nil {
				t.Errorf("ParseNodeID(%s) returned nil hash", test.input)
			}
		}
	}
}

func TestHashRingProperties(t *testing.T) {
	// Test that hash ring is properly bounded
	maxValue := new(big.Int).Lsh(big.NewInt(1), M)
	
	// Create hash from max value - should wrap to 0
	overflowHash := NewHash(maxValue)
	zero := NewHash(big.NewInt(0))
	
	if !overflowHash.Equal(zero) {
		t.Error("Hash at max value should wrap to 0")
	}
	
	// Test that all hashes are within bounds
	for i := 0; i < 100; i++ {
		randomString := fmt.Sprintf("test-%d", i)
		hash := NewHashFromString(randomString)
		
		if hash.BigInt().Sign() < 0 {
			t.Errorf("Hash should not be negative: %s", hash.String())
		}
		
		if hash.BigInt().Cmp(maxValue) >= 0 {
			t.Errorf("Hash should be less than 2^M: %s", hash.String())
		}
	}
}

// Benchmark tests
func BenchmarkNewHashFromString(b *testing.B) {
	for i := 0; i < b.N; i++ {
		NewHashFromString("benchmark-test-string")
	}
}

func BenchmarkHashDistance(b *testing.B) {
	hash1 := NewHashFromString("hash1")
	hash2 := NewHashFromString("hash2")
	
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		hash1.Distance(hash2)
	}
}

func BenchmarkHashInRange(b *testing.B) {
	start := NewHashFromString("start")
	end := NewHashFromString("end")
	test := NewHashFromString("test")
	
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		test.InRange(start, end)
	}
}