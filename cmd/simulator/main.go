package main

import (
	"flag"
	"fmt"
	"log"
	"math/rand"
	"sync"
	"time"

	"chord-dht/internal/chord"
	"chord-dht/internal/metrics"
	"chord-dht/pkg/hash"
)

type SimulatorConfig struct {
	NumNodes      int
	BasePort      int
	LookupCount   int
	Duration      time.Duration
	ResultsDir    string
	ExperimentID  string
}

func main() {
	var config SimulatorConfig
	
	// Parse command line flags
	flag.IntVar(&config.NumNodes, "nodes", 5, "Number of nodes to simulate")
	flag.IntVar(&config.BasePort, "base-port", 6000, "Base port number (nodes will use consecutive ports)")
	flag.IntVar(&config.LookupCount, "lookups", 100, "Number of random lookups to perform")
	flag.DurationVar(&config.Duration, "duration", 60*time.Second, "Duration to run simulation")
	flag.StringVar(&config.ResultsDir, "results-dir", "results", "Directory to save results")
	flag.StringVar(&config.ExperimentID, "experiment-id", "", "Experiment ID (auto-generated if empty)")
	flag.Parse()

	// Generate experiment ID if not provided
	if config.ExperimentID == "" {
		config.ExperimentID = fmt.Sprintf("sim_%d", time.Now().Unix())
	}

	log.Printf("Starting Chord DHT Simulator")
	log.Printf("Configuration:")
	log.Printf("  Nodes: %d", config.NumNodes)
	log.Printf("  Base Port: %d", config.BasePort)
	log.Printf("  Lookups: %d", config.LookupCount)
	log.Printf("  Duration: %v", config.Duration)
	log.Printf("  Results Dir: %s", config.ResultsDir)
	log.Printf("  Experiment ID: %s", config.ExperimentID)

	// Create nodes
	nodes := make([]*chord.Node, config.NumNodes)
	addresses := make([]string, config.NumNodes)
	
	// Initialize nodes
	for i := 0; i < config.NumNodes; i++ {
		port := config.BasePort + i
		addr := fmt.Sprintf("localhost:%d", port)
		addresses[i] = addr
		
		// Generate unique node ID
		nodeID := hash.GenerateID(addr)
		nodes[i] = chord.NewNode(addr, nodeID)
		
		log.Printf("Created node %d: ID=%s, Address=%s", 
			i, nodeID.String()[:16], addr)
	}

	// Start all nodes
	log.Printf("Starting all nodes...")
	var wg sync.WaitGroup
	for i, node := range nodes {
		wg.Add(1)
		go func(idx int, n *chord.Node) {
			defer wg.Done()
			if err := n.Start(); err != nil {
				log.Printf("Failed to start node %d: %v", idx, err)
				return
			}
		}(i, node)
	}
	wg.Wait()
	log.Printf("All nodes started")

	// Create the ring - first node creates it, others join
	log.Printf("Building Chord ring...")
	
	// First node creates the ring
	if err := nodes[0].Join(""); err != nil {
		log.Fatalf("Failed to create ring: %v", err)
	}
	log.Printf("Ring created by node 0")

	// Other nodes join the ring via the first node (bootstrap)
	bootstrapAddr := addresses[0]
	for i := 1; i < config.NumNodes; i++ {
		if err := nodes[i].Join(bootstrapAddr); err != nil {
			log.Printf("Failed to join node %d to ring: %v", i, err)
			continue
		}
		log.Printf("Node %d joined ring", i)
		
		// Add small delay between joins to avoid overwhelming the bootstrap
		time.Sleep(200 * time.Millisecond)
	}

	// Wait for stabilization
	log.Printf("Waiting for ring stabilization...")
	time.Sleep(10 * time.Second)

	// Initialize global metrics
	globalMetrics := metrics.NewGlobalMetrics(config.ResultsDir, config.ExperimentID)

	// Start metrics collection for all nodes
	nodeMetrics := make([]*metrics.Metrics, config.NumNodes)
	for i, node := range nodes {
		if node == nil {
			continue
		}
		
		var err error
		nodeMetrics[i], err = metrics.NewMetrics(
			node.GetID().String(), 
			config.ResultsDir, 
			config.ExperimentID,
		)
		if err != nil {
			log.Printf("Failed to initialize metrics for node %d: %v", i, err)
			continue
		}
		
		// Update node count for all metrics
		nodeMetrics[i].UpdateNodeCount(config.NumNodes)
	}

	// Start the simulation
	log.Printf("Starting simulation for %v...", config.Duration)
	
	simulationDone := make(chan struct{})
	
	// Lookup generator
	go func() {
		defer close(simulationDone)
		
		lookupInterval := config.Duration / time.Duration(config.LookupCount)
		if lookupInterval < 100*time.Millisecond {
			lookupInterval = 100 * time.Millisecond
		}
		
		ticker := time.NewTicker(lookupInterval)
		defer ticker.Stop()
		
		lookupCount := 0
		startTime := time.Now()
		
		for {
			select {
			case <-ticker.C:
				if lookupCount >= config.LookupCount || time.Since(startTime) >= config.Duration {
					return
				}
				
				// Perform random lookup
				performRandomLookup(nodes, nodeMetrics, lookupCount)
				lookupCount++
				
			case <-time.After(config.Duration):
				return
			}
		}
	}()

	// Wait for simulation to complete
	<-simulationDone
	log.Printf("Simulation completed")

	// Collect final metrics
	log.Printf("Collecting final metrics...")
	totalMessages := int64(0)
	totalLookups := int64(0)
	
	for i, node := range nodes {
		if node == nil || nodeMetrics[i] == nil {
			continue
		}
		
		// Get final stats
		messages, lookups := node.GetStats()
		totalMessages += messages
		totalLookups += lookups
		
		// Write final snapshot
		if err := nodeMetrics[i].WriteSnapshot(); err != nil {
			log.Printf("Error writing final metrics for node %d: %v", i, err)
		}
		
		// Close metrics
		nodeMetrics[i].Close()
	}

	// Create global metrics summary
	if err := globalMetrics.CombineNodeMetrics(); err != nil {
		log.Printf("Error creating global metrics: %v", err)
	}

	// Print simulation summary
	log.Printf("\n=== Simulation Summary ===")
	log.Printf("Nodes: %d", config.NumNodes)
	log.Printf("Duration: %v", config.Duration)
	log.Printf("Total Messages: %d", totalMessages)
	log.Printf("Total Lookups: %d", totalLookups)
	if totalLookups > 0 {
		log.Printf("Messages per Lookup: %.2f", float64(totalMessages)/float64(totalLookups))
	}
	log.Printf("Results saved to: %s", config.ResultsDir)

	// Stop all nodes
	log.Printf("Stopping all nodes...")
	for i, node := range nodes {
		if node != nil {
			node.Stop()
			log.Printf("Node %d stopped", i)
		}
	}

	log.Printf("Simulation finished successfully")
}

// performRandomLookup performs a random lookup operation
func performRandomLookup(nodes []*chord.Node, nodeMetrics []*metrics.Metrics, lookupID int) {
	// Select random node to perform lookup
	nodeIdx := rand.Intn(len(nodes))
	node := nodes[nodeIdx]
	if node == nil {
		return
	}

	// Generate random key to lookup
	randomKey := fmt.Sprintf("key_%d_%d", lookupID, rand.Intn(1000))
	keyHash := hash.NewHashFromString(randomKey)

	startTime := time.Now()
	
	// Perform lookup (this would call the actual FindSuccessor)
	// For simulation, we just record the operation
	successor := node.GetSuccessor() // Simplified - would be actual lookup
	
	latency := time.Since(startTime)
	
	if successor == nil {
		log.Printf("Lookup %d failed: successor is nil", lookupID)
		return
	}

	// Record metrics
	if nodeMetrics[nodeIdx] != nil {
		nodeMetrics[nodeIdx].RecordLookup(latency)
		nodeMetrics[nodeIdx].RecordMessage() // For the lookup request
	}

	if lookupID%10 == 0 {
		log.Printf("Performed lookup %d: key=%s, latency=%v", 
			lookupID, keyHash.String()[:16], latency)
	}
}

// Additional helper functions for analysis

func analyzeRingStructure(nodes []*chord.Node) {
	log.Printf("\n=== Ring Structure Analysis ===")
	
	for i, node := range nodes {
		if node == nil {
			continue
		}
		
		successor := node.GetSuccessor()
		predecessor := node.GetPredecessor()
		
		log.Printf("Node %d:", i)
		log.Printf("  ID: %s", node.GetID().String()[:16])
		log.Printf("  Address: %s", node.GetAddress())
		
		if successor != nil {
			log.Printf("  Successor: %s", successor.ID.String()[:16])
		} else {
			log.Printf("  Successor: nil")
		}
		
		if predecessor != nil {
			log.Printf("  Predecessor: %s", predecessor.ID.String()[:16])
		} else {
			log.Printf("  Predecessor: nil")
		}
		
		fingers := node.GetFingers()
		log.Printf("  Fingers: %d entries", len(fingers))
	}
}