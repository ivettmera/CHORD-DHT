package main

import (
	"flag"
	"fmt"
	"log"
	"os"
	"os/signal"
	"syscall"
	"time"

	"chord-dht/internal/chord"
	"chord-dht/internal/metrics"
	"chord-dht/pkg/hash"
)

func main() {
	// Define command line flags
	var (
		addr      = flag.String("addr", "localhost:5000", "Node address (IP:port)")
		publicAddr = flag.String("public", "", "Public address for advertising to other nodes (defaults to addr)")
		bootstrap = flag.String("bootstrap", "", "Bootstrap node address (empty for first node)")
		nodeID    = flag.String("id", "", "Node ID (hex string, auto-generated if empty)")
		metricsDir = flag.String("metrics", "results", "Directory to save metrics CSV files")
	)
	flag.Parse()

	// Validate address
	if *addr == "" {
		log.Fatal("Node address (--addr) is required")
	}

	// Set public address (defaults to addr if not specified)
	advertiseAddr := *addr
	if *publicAddr != "" {
		advertiseAddr = *publicAddr
	}

	// Generate experiment ID
	experimentID := fmt.Sprintf("exp_%d", time.Now().Unix())

	// Parse or generate node ID
	var id *hash.Hash
	var err error
	if *nodeID != "" {
		id, err = hash.ParseNodeID(*nodeID)
		if err != nil {
			log.Fatalf("Invalid node ID: %v", err)
		}
	} else {
		// Auto-generate ID from advertise address for consistency
		id = hash.GenerateID(advertiseAddr)
	}

	log.Printf("Starting Chord node: ID=%s, Listen=%s, Advertise=%s", id.String()[:16], *addr, advertiseAddr)

	// Create metrics collector
	var nodeMetrics *metrics.Metrics
	if *metricsDir != "" {
		nodeMetrics, err = metrics.NewMetrics(id.String(), *metricsDir, experimentID)
		if err != nil {
			log.Fatalf("Failed to initialize metrics: %v", err)
		}
		defer nodeMetrics.Close()
		log.Printf("Metrics will be saved to: %s", *metricsDir)
	}

	// Create and start the Chord node
	node := chord.NewNodeWithAdvertise(*addr, advertiseAddr, id)
	
	if err := node.Start(); err != nil {
		log.Fatalf("Failed to start node: %v", err)
	}
	defer node.Stop()

	// Join the ring
	if *bootstrap == "" {
		log.Printf("Creating new ring (bootstrap node)")
		if err := node.Join(""); err != nil {
			log.Fatalf("Failed to create ring: %v", err)
		}
	} else {
		log.Printf("Joining existing ring via bootstrap: %s", *bootstrap)
		if err := node.Join(*bootstrap); err != nil {
			log.Fatalf("Failed to join ring: %v", err)
		}
	}

	log.Printf("Node successfully started and joined ring")

	// Start metrics collection goroutine
	if nodeMetrics != nil {
		go func() {
			ticker := time.NewTicker(10 * time.Second)
			defer ticker.Stop()
			
			for {
				select {
				case <-ticker.C:
				// Get current stats from node
				_, lookups := node.GetStats()
				
				// Update metrics (node count would need to be determined via discovery)
				nodeMetrics.UpdateNodeCount(1) // At least this node
				nodeMetrics.RecordMessage()    // Called for each message					// Record lookups with dummy latency for now
					if lookups > 0 {
						nodeMetrics.RecordLookup(time.Millisecond * 50) // Placeholder
					}
				}
			}
		}()
	}

	// Print node information
	log.Printf("Node is running:")
	log.Printf("  ID: %s", id.String())
	log.Printf("  Address: %s", *addr)
	log.Printf("  Bootstrap: %s", *bootstrap)
	if nodeMetrics != nil {
		log.Printf("  Metrics: enabled")
	}

	// Handle graceful shutdown
	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)

	log.Printf("Node is ready. Press Ctrl+C to stop.")

	// Wait for shutdown signal
	<-sigCh
	log.Printf("Received shutdown signal, stopping...")

	// Graceful shutdown
	if nodeMetrics != nil {
		// Write final metrics snapshot
		if err := nodeMetrics.WriteSnapshot(); err != nil {
			log.Printf("Error writing final metrics: %v", err)
		}
		
		// Print final stats
		nodeCount, messages, lookups, avgLatency := nodeMetrics.GetCurrentStats()
		log.Printf("Final stats: Nodes=%d, Messages=%d, Lookups=%d, AvgLatency=%.2fms",
			nodeCount, messages, lookups, avgLatency)
	}

	log.Printf("Node stopped gracefully")
}