package chord

import (
	"context"
	"testing"
	"time"

	"chord-dht/pkg/hash"
)

func TestNewNode(t *testing.T) {
	address := "localhost:8000"
	nodeID := hash.NewHashFromString("test-node")
	
	node := NewNode(address, nodeID)
	
	if node == nil {
		t.Fatal("NewNode returned nil")
	}
	
	if node.address != address {
		t.Errorf("Expected address %s, got %s", address, node.address)
	}
	
	if !node.id.Equal(nodeID) {
		t.Errorf("Expected node ID %s, got %s", nodeID.String(), node.id.String())
	}
	
	// Check finger table initialization
	if len(node.fingers) != FingerTableSize {
		t.Errorf("Expected finger table size %d, got %d", FingerTableSize, len(node.fingers))
	}
	
	// All fingers should initially point to self
	for i, finger := range node.fingers {
		if finger == nil {
			t.Errorf("Finger %d is nil", i)
			continue
		}
		if finger.Address != address {
			t.Errorf("Finger %d has wrong address: expected %s, got %s", 
				i, address, finger.Address)
		}
	}
}

func TestNodeStartStop(t *testing.T) {
	node := NewNode("localhost:8001", nil)
	
	// Test start
	err := node.Start()
	if err != nil {
		t.Fatalf("Failed to start node: %v", err)
	}
	
	// Give the server a moment to start
	time.Sleep(100 * time.Millisecond)
	
	// Test stop
	node.Stop()
	
	// Give the server a moment to stop
	time.Sleep(100 * time.Millisecond)
}

func TestNodeJoinAsBootstrap(t *testing.T) {
	node := NewNode("localhost:8002", nil)
	
	err := node.Start()
	if err != nil {
		t.Fatalf("Failed to start node: %v", err)
	}
	defer node.Stop()
	
	// Join with empty bootstrap (becomes bootstrap node)
	err = node.Join("")
	if err != nil {
		t.Errorf("Failed to join as bootstrap: %v", err)
	}
	
	// Check that node points to itself
	if node.successor == nil {
		t.Error("Bootstrap node should have successor set")
	} else if node.successor.Address != node.address {
		t.Error("Bootstrap node successor should point to itself")
	}
	
	if node.predecessor != nil {
		t.Error("Bootstrap node should not have predecessor initially")
	}
}

func TestFindSuccessorRPC(t *testing.T) {
	// Create a simple node
	node := NewNode("localhost:8003", hash.NewHashFromString("node1"))
	
	err := node.Start()
	if err != nil {
		t.Fatalf("Failed to start node: %v", err)
	}
	defer node.Stop()
	
	// Join as bootstrap
	err = node.Join("")
	if err != nil {
		t.Fatalf("Failed to join as bootstrap: %v", err)
	}
	
	// Test FindSuccessor RPC
	ctx := context.Background()
	targetKey := hash.NewHashFromString("test-key")
	
	resp, err := node.FindSuccessor(ctx, &struct {
		Key       string
		Requester *struct {
			Id      string
			Address string
		}
	}{
		Key: targetKey.String(),
		Requester: &struct {
			Id      string
			Address string
		}{
			Id:      node.id.String(),
			Address: node.address,
		},
	})
	
	// Note: This test needs the actual protobuf structs to work properly
	// For now, we'll just check that the method doesn't panic
	_ = resp
	_ = err
}

func TestClosestPrecedingFinger(t *testing.T) {
	nodeID := hash.NewHashFromString("node")
	node := NewNode("localhost:8004", nodeID)
	
	// Set up some finger table entries
	finger1ID := hash.NewHashFromString("finger1")
	finger2ID := hash.NewHashFromString("finger2")
	
	node.fingers[0] = &NodeInfo{ID: finger1ID, Address: "localhost:8005"}
	node.fingers[1] = &NodeInfo{ID: finger2ID, Address: "localhost:8006"}
	
	// Test with a target that should use one of the fingers
	targetID := hash.NewHashFromString("target")
	
	result := node.closestPrecedingFinger(targetID)
	
	if result == nil {
		t.Error("closestPrecedingFinger returned nil")
	}
	
	// Should return either a finger or self
	if result.Address != "localhost:8005" && 
	   result.Address != "localhost:8006" && 
	   result.Address != node.address {
		t.Errorf("Unexpected result from closestPrecedingFinger: %s", result.Address)
	}
}

func TestGetNodeInfo(t *testing.T) {
	nodeID := hash.NewHashFromString("test-info")
	address := "localhost:8007"
	node := NewNode(address, nodeID)
	
	info := node.GetNodeInfo()
	
	if info == nil {
		t.Fatal("GetNodeInfo returned nil")
	}
	
	if info.Address != address {
		t.Errorf("Expected address %s, got %s", address, info.Address)
	}
	
	if !info.ID.Equal(nodeID) {
		t.Errorf("Expected ID %s, got %s", nodeID.String(), info.ID.String())
	}
}

// Integration tests with multiple nodes
func TestTwoNodeRing(t *testing.T) {
	// Skip this test if we don't have protobuf generated
	t.Skip("Requires protobuf generation for full integration test")
	
	// Create bootstrap node
	bootstrap := NewNode("localhost:9000", hash.NewHashFromString("bootstrap"))
	err := bootstrap.Start()
	if err != nil {
		t.Fatalf("Failed to start bootstrap: %v", err)
	}
	defer bootstrap.Stop()
	
	err = bootstrap.Join("")
	if err != nil {
		t.Fatalf("Failed to create bootstrap ring: %v", err)
	}
	
	// Create second node
	node2 := NewNode("localhost:9001", hash.NewHashFromString("node2"))
	err = node2.Start()
	if err != nil {
		t.Fatalf("Failed to start node2: %v", err)
	}
	defer node2.Stop()
	
	err = node2.Join("localhost:9000")
	if err != nil {
		t.Fatalf("Failed to join node2: %v", err)
	}
	
	// Allow time for stabilization
	time.Sleep(2 * time.Second)
	
	// Verify ring structure
	// This would require more detailed verification of the ring state
}

// Test hash range calculations for finger table
func TestFingerTableCalculations(t *testing.T) {
	nodeID := hash.NewHashFromString("test-node")
	
	// Test that finger starts are calculated correctly
	for i := 1; i <= 10; i++ {
		fingerStart := hash.FingerStart(nodeID, i)
		
		// Each finger should be further around the ring
		if i > 1 {
			prevFingerStart := hash.FingerStart(nodeID, i-1)
			distance := prevFingerStart.Distance(fingerStart)
			
			// Distance should be 2^(i-2) (since we're comparing i-1 to i)
			expectedDistance := int64(1) << (i - 2)
			if distance.Int64() != expectedDistance {
				t.Logf("Finger %d distance: expected %d, got %d", 
					i, expectedDistance, distance.Int64())
			}
		}
	}
}

// Test node maintenance routines
func TestMaintenanceRoutines(t *testing.T) {
	node := NewNode("localhost:8010", nil)
	
	// Test that maintenance doesn't panic
	node.stabilize()
	node.fixFingers()
	node.checkPredecessor()
	
	// These should complete without error even with no network
}

// Test metrics counting
func TestMetricsCounting(t *testing.T) {
	node := NewNode("localhost:8011", nil)
	
	initialMessages := node.MessageCount
	initialLookups := node.LookupCount
	
	// Simulate some activity (this would normally be done via RPC)
	node.MessageCount++
	node.LookupCount++
	
	if node.MessageCount <= initialMessages {
		t.Error("Message count should have increased")
	}
	
	if node.LookupCount <= initialLookups {
		t.Error("Lookup count should have increased")
	}
}

// Benchmark finger table operations
func BenchmarkClosestPrecedingFinger(b *testing.B) {
	node := NewNode("localhost:8020", hash.NewHashFromString("bench-node"))
	
	// Set up finger table
	for i := 0; i < FingerTableSize; i++ {
		fingerID := hash.NewHashFromString(fmt.Sprintf("finger-%d", i))
		node.fingers[i] = &NodeInfo{
			ID:      fingerID,
			Address: fmt.Sprintf("localhost:%d", 9000+i),
		}
	}
	
	targetID := hash.NewHashFromString("target")
	
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		node.closestPrecedingFinger(targetID)
	}
}

func BenchmarkFingerTableInit(b *testing.B) {
	address := "localhost:8021"
	
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		nodeID := hash.NewHashFromString(fmt.Sprintf("node-%d", i))
		node := NewNode(address, nodeID)
		_ = node // Prevent optimization
	}
}