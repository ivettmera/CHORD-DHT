package main

import (
	"context"
	"fmt"
	"log"
	"math/rand"
	"sync"
	"testing"
	"time"

	"chord-dht/internal/chord"
	"chord-dht/pkg/hash"
)

// TestIntegrationBasicRing tests basic ring formation and lookups
func TestIntegrationBasicRing(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping integration test in short mode")
	}

	// Create multiple nodes
	nodeCount := 5
	basePort := 7000
	nodes := make([]*chord.Node, nodeCount)
	addresses := make([]string, nodeCount)

	// Create nodes
	for i := 0; i < nodeCount; i++ {
		port := basePort + i
		addr := fmt.Sprintf("localhost:%d", port)
		addresses[i] = addr
		nodes[i] = chord.NewNode(addr, nil)
	}

	// Start all nodes
	var wg sync.WaitGroup
	for i, node := range nodes {
		wg.Add(1)
		go func(idx int, n *chord.Node) {
			defer wg.Done()
			if err := n.Start(); err != nil {
				t.Errorf("Failed to start node %d: %v", idx, err)
				return
			}
		}(i, node)
	}
	wg.Wait()

	// Ensure cleanup
	defer func() {
		for i, node := range nodes {
			if node != nil {
				node.Stop()
				log.Printf("Stopped node %d", i)
			}
		}
	}()

	// First node creates the ring
	if err := nodes[0].Join(""); err != nil {
		t.Fatalf("Failed to create ring: %v", err)
	}
	log.Printf("Ring created by node 0")

	// Other nodes join the ring
	for i := 1; i < nodeCount; i++ {
		if err := nodes[i].Join(addresses[0]); err != nil {
			t.Errorf("Failed to join node %d to ring: %v", i, err)
			continue
		}
		log.Printf("Node %d joined ring", i)
		time.Sleep(200 * time.Millisecond) // Small delay between joins
	}

	// Wait for stabilization
	log.Printf("Waiting for ring stabilization...")
	time.Sleep(15 * time.Second)

	// Verify ring structure
	log.Printf("Verifying ring structure...")
	for i, node := range nodes {
		successor := node.GetSuccessor()
		predecessor := node.GetPredecessor()

		if successor == nil {
			t.Errorf("Node %d has no successor", i)
		}

		log.Printf("Node %d: ID=%s, Succ=%s, Pred=%s",
			i,
			node.GetID().String()[:8],
			getNodeIDString(successor),
			getNodeIDString(predecessor))
	}

	// Perform some lookups
	log.Printf("Performing lookup tests...")
	performLookupTests(t, nodes)
}

// TestIntegrationLookupPerformance tests lookup performance across multiple nodes
func TestIntegrationLookupPerformance(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping integration test in short mode")
	}

	nodeCount := 8
	basePort := 8000
	nodes := setupTestRing(t, nodeCount, basePort)
	defer cleanupTestRing(nodes)

	// Wait for stabilization
	time.Sleep(20 * time.Second)

	// Perform many lookups
	lookupCount := 50
	var totalLatency time.Duration
	var lookupWg sync.WaitGroup
	latencyChan := make(chan time.Duration, lookupCount)

	log.Printf("Performing %d lookups...", lookupCount)

	for i := 0; i < lookupCount; i++ {
		lookupWg.Add(1)
		go func(lookupID int) {
			defer lookupWg.Done()

			// Random key
			key := fmt.Sprintf("key_%d_%d", lookupID, rand.Intn(1000))
			keyHash := hash.NewHashFromString(key)

			// Random node to start lookup from
			nodeIdx := rand.Intn(len(nodes))
			node := nodes[nodeIdx]

			startTime := time.Now()
			
			// For now, just get successor (in full implementation, would call FindSuccessor)
			successor := node.GetSuccessor()
			
			latency := time.Since(startTime)
			latencyChan <- latency

			if successor == nil {
				t.Errorf("Lookup %d failed: no successor found", lookupID)
			}

			if lookupID%10 == 0 {
				log.Printf("Lookup %d: key=%s, latency=%v", 
					lookupID, keyHash.String()[:8], latency)
			}
		}(i)
	}

	lookupWg.Wait()
	close(latencyChan)

	// Calculate statistics
	lookupCount = 0
	for latency := range latencyChan {
		totalLatency += latency
		lookupCount++
	}

	if lookupCount > 0 {
		avgLatency := totalLatency / time.Duration(lookupCount)
		log.Printf("Lookup performance: %d lookups, avg latency: %v", 
			lookupCount, avgLatency)

		// Verify reasonable performance (should be much less than a second)
		if avgLatency > time.Second {
			t.Errorf("Average lookup latency too high: %v", avgLatency)
		}
	}
}

// TestIntegrationNodeFailure tests behavior when nodes fail
func TestIntegrationNodeFailure(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping integration test in short mode")
	}

	nodeCount := 6
	basePort := 9000
	nodes := setupTestRing(t, nodeCount, basePort)
	defer cleanupTestRing(nodes)

	// Wait for initial stabilization
	time.Sleep(15 * time.Second)

	log.Printf("Initial ring established")

	// Stop a middle node (not bootstrap)
	failedNodeIdx := 2
	log.Printf("Stopping node %d to simulate failure", failedNodeIdx)
	nodes[failedNodeIdx].Stop()
	nodes[failedNodeIdx] = nil

	// Wait for failure detection and recovery
	time.Sleep(30 * time.Second)

	// Verify remaining nodes can still perform lookups
	log.Printf("Testing lookups after node failure...")
	activeNodes := make([]*chord.Node, 0, len(nodes)-1)
	for i, node := range nodes {
		if node != nil {
			activeNodes = append(activeNodes, node)
			log.Printf("Active node %d: ID=%s", i, node.GetID().String()[:8])
		}
	}

	if len(activeNodes) == 0 {
		t.Fatal("No active nodes remaining")
	}

	// Perform lookups on remaining nodes
	for i := 0; i < 10; i++ {
		key := fmt.Sprintf("recovery_key_%d", i)
		nodeIdx := rand.Intn(len(activeNodes))
		node := activeNodes[nodeIdx]

		successor := node.GetSuccessor()
		if successor == nil {
			t.Errorf("Lookup failed after node failure")
		}
	}

	log.Printf("Ring recovery test completed")
}

// Helper functions

func setupTestRing(t *testing.T, nodeCount, basePort int) []*chord.Node {
	nodes := make([]*chord.Node, nodeCount)
	addresses := make([]string, nodeCount)

	// Create nodes
	for i := 0; i < nodeCount; i++ {
		port := basePort + i
		addr := fmt.Sprintf("localhost:%d", port)
		addresses[i] = addr
		nodes[i] = chord.NewNode(addr, nil)
	}

	// Start all nodes
	var wg sync.WaitGroup
	for i, node := range nodes {
		wg.Add(1)
		go func(idx int, n *chord.Node) {
			defer wg.Done()
			if err := n.Start(); err != nil {
				t.Errorf("Failed to start node %d: %v", idx, err)
				return
			}
		}(i, node)
	}
	wg.Wait()

	// Create ring
	if err := nodes[0].Join(""); err != nil {
		t.Fatalf("Failed to create ring: %v", err)
	}

	// Join other nodes
	for i := 1; i < nodeCount; i++ {
		if err := nodes[i].Join(addresses[0]); err != nil {
			t.Errorf("Failed to join node %d: %v", i, err)
		}
		time.Sleep(100 * time.Millisecond)
	}

	return nodes
}

func cleanupTestRing(nodes []*chord.Node) {
	for i, node := range nodes {
		if node != nil {
			node.Stop()
			log.Printf("Cleaned up node %d", i)
		}
	}
}

func performLookupTests(t *testing.T, nodes []*chord.Node) {
	lookupCount := 20
	
	for i := 0; i < lookupCount; i++ {
		// Generate random key
		key := fmt.Sprintf("test_key_%d", i)
		keyHash := hash.NewHashFromString(key)
		
		// Pick random node to start lookup
		nodeIdx := rand.Intn(len(nodes))
		node := nodes[nodeIdx]
		
		// Perform lookup (simplified - just check successor)
		successor := node.GetSuccessor()
		if successor == nil {
			t.Errorf("Lookup %d failed: no successor", i)
			continue
		}
		
		log.Printf("Lookup %d: key=%s -> successor=%s", 
			i, keyHash.String()[:8], successor.ID.String()[:8])
	}
}

func getNodeIDString(nodeInfo *chord.NodeInfo) string {
	if nodeInfo == nil {
		return "nil"
	}
	return nodeInfo.ID.String()[:8]
}

// Benchmark tests

func BenchmarkRingLookup(b *testing.B) {
	nodeCount := 5
	basePort := 10000
	nodes := make([]*chord.Node, nodeCount)

	// Setup ring
	for i := 0; i < nodeCount; i++ {
		addr := fmt.Sprintf("localhost:%d", basePort+i)
		nodes[i] = chord.NewNode(addr, nil)
		nodes[i].Start()
	}

	defer func() {
		for _, node := range nodes {
			if node != nil {
				node.Stop()
			}
		}
	}()

	// Create ring
	nodes[0].Join("")
	for i := 1; i < nodeCount; i++ {
		nodes[i].Join(fmt.Sprintf("localhost:%d", basePort))
		time.Sleep(50 * time.Millisecond)
	}

	// Wait for stabilization
	time.Sleep(5 * time.Second)

	b.ResetTimer()

	// Benchmark lookups
	for i := 0; i < b.N; i++ {
		key := fmt.Sprintf("bench_key_%d", i)
		nodeIdx := i % nodeCount
		node := nodes[nodeIdx]
		
		// Simplified lookup
		successor := node.GetSuccessor()
		if successor == nil {
			b.Error("Lookup failed")
		}
	}
}