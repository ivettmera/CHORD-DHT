# Chord DHT Implementation in Go

A complete distributed hash table implementation based on the Chord protocol, written in Go with gRPC communication. Designed for deployment across multiple VMs in Google Cloud with comprehensive metrics collection.

## Features

- **Complete Chord Protocol**: Full implementation with Join, FindSuccessor, Stabilize, FixFingers, CheckPredecessor
- **SHA-1 Based**: 160-bit identifier space using SHA-1 hashing (as per original Chord paper)
- **gRPC Communication**: All inter-node communication uses gRPC with Protocol Buffers
- **Multi-VM Support**: Designed for deployment across distributed VMs in different regions
- **Bootstrap Discovery**: Automatic ring joining via bootstrap node
- **Fault Tolerance**: Handles node failures with automatic ring repair
- **O(log N) Complexity**: Efficient lookups with logarithmic message complexity
- **Comprehensive Metrics**: CSV-based metrics collection with timestamp, node count, messages, lookups, and latency
- **Production Ready**: Docker support, comprehensive testing, and deployment tools

## Quick Start

### Prerequisites

- Go 1.21 or later
- Protocol Buffers compiler (`protoc`)
- Make (optional, but recommended)
- Docker (for containerized deployment)

### Installation

```bash
git clone <repository-url>
cd chord-dht
make build
```

### Local Development with Scripts

```bash
# Single node deployment
./scripts/start-node.sh localhost:8000

# Multiple nodes on same machine
./scripts/deploy-multi-nodes.sh bootstrap 3

# Monitor the ring
./scripts/monitor.sh
./scripts/ring-status.sh

# Test functionality
./scripts/test-ring.sh

# Stop all nodes
./scripts/stop-nodes.sh

# Run the simulator
./bin/chord-simulator -nodes 5 -duration 30s -lookups 100
```

### Multi-VM Deployment (Google Cloud)

**📖 Complete Guide:** [docs/DEPLOYMENT_GUIDE.md](docs/DEPLOYMENT_GUIDE.md)

**Quick 3-VM Setup:**

1. **VM1 (Bootstrap):**
```bash
git clone <repo> && cd chord-dht && make build
./scripts/deploy-multi-nodes.sh bootstrap 3
```

2. **VM2/VM3 (Join):**
```bash
# Configure network
cp config/network.conf.example config/network.conf
# Edit BOOTSTRAP_ADDR=VM1_EXTERNAL_IP:8000

./scripts/deploy-multi-nodes.sh join 3
```

## Google Cloud Deployment Guide (Legacy)

### VM Setup (3 VMs in Different Regions)

#### VM1 (Bootstrap Node) - us-central1
```bash
# Create VM
gcloud compute instances create chord-vm1 \
    --zone=us-central1-a \
    --machine-type=e2-medium \
    --image-family=debian-11 \
    --image-project=debian-cloud \
    --tags=chord-node

# Allow traffic on port 5000
gcloud compute firewall-rules create chord-port \
    --allow tcp:5000 \
    --source-ranges 0.0.0.0/0 \
    --target-tags chord-node

# Deploy and run
scp bin/chord-node user@VM1-EXTERNAL-IP:~/
ssh user@VM1-EXTERNAL-IP
./chord-node --addr=0.0.0.0:5000 --bootstrap="" --metrics=results
```

#### VM2 (Region: europe-west1)
```bash
# Create VM in different region
gcloud compute instances create chord-vm2 \
    --zone=europe-west1-b \
    --machine-type=e2-medium \
    --image-family=debian-11 \
    --image-project=debian-cloud \
    --tags=chord-node

# Deploy and run
scp bin/chord-node user@VM2-EXTERNAL-IP:~/
ssh user@VM2-EXTERNAL-IP
./chord-node --addr=0.0.0.0:5000 --bootstrap=VM1-EXTERNAL-IP:5000 --metrics=results
```

#### VM3 (Region: asia-southeast1)
```bash
# Create VM in third region
gcloud compute instances create chord-vm3 \
    --zone=asia-southeast1-a \
    --machine-type=e2-medium \
    --image-family=debian-11 \
    --image-project=debian-cloud \
    --tags=chord-node

# Deploy and run
scp bin/chord-node user@VM3-EXTERNAL-IP:~/
ssh user@VM3-EXTERNAL-IP
./chord-node --addr=0.0.0.0:5000 --bootstrap=VM1-EXTERNAL-IP:5000 --metrics=results
```

### Multiple Logical Nodes per VM (Microservices)

Run multiple nodes on different ports per VM:

```bash
# VM1 - Multiple nodes
./chord-node --addr=0.0.0.0:5000 --bootstrap="" --metrics=results --id=node1 &
./chord-node --addr=0.0.0.0:5001 --bootstrap=localhost:5000 --metrics=results --id=node2 &
./chord-node --addr=0.0.0.0:5002 --bootstrap=localhost:5000 --metrics=results --id=node3 &

# VM2 - Multiple nodes joining VM1's bootstrap
./chord-node --addr=0.0.0.0:5000 --bootstrap=VM1-IP:5000 --metrics=results --id=node4 &
./chord-node --addr=0.0.0.0:5001 --bootstrap=VM1-IP:5000 --metrics=results --id=node5 &

# VM3 - Multiple nodes joining VM1's bootstrap  
./chord-node --addr=0.0.0.0:5000 --bootstrap=VM1-IP:5000 --metrics=results --id=node6 &
./chord-node --addr=0.0.0.0:5001 --bootstrap=VM1-IP:5000 --metrics=results --id=node7 &
```

## Local Development & Testing

### Running the Simulator

The simulator creates multiple local nodes for testing:

```bash
# Run 5 nodes with 100 lookups over 60 seconds
make simulator

# Custom configuration
./bin/chord-simulator \
    --nodes=10 \
    --base-port=6000 \
    --lookups=500 \
    --duration=120s \
    --results-dir=results \
    --experiment-id=test-1
```

### Development Ring

```bash
# Start 3-node development ring
make dev-ring

# Stop all local nodes
make stop-dev
```

## Architecture

### Core Components

- **pkg/hash**: SHA-1 hash functions and 160-bit identifier management
- **internal/chord**: Core Chord protocol implementation (node.go, rpc.go)
- **internal/metrics**: Performance monitoring and CSV export
- **cmd/node**: Main node application with all required flags
- **cmd/simulator**: Multi-node simulation tool
- **proto**: gRPC service definitions

### Chord Algorithm Implementation

#### Core Operations (O(log N) complexity)
1. **Join(bootstrapAddr)**: Join ring via bootstrap node
2. **FindSuccessor(key)**: Locate successor of a key
3. **ClosestPrecedingFinger(key)**: Find closest preceding node
4. **Notify(node)**: Notify about potential predecessor
5. **Stabilize()**: Periodic successor/predecessor verification
6. **FixFingers()**: Periodic finger table maintenance
7. **CheckPredecessor()**: Periodic predecessor liveness check

#### Network Protocol (gRPC)

```protobuf
service ChordService {
    rpc FindSuccessor(FindSuccessorRequest) returns (FindSuccessorResponse);
    rpc Notify(NotifyRequest) returns (NotifyResponse);
    rpc GetInfo(GetInfoRequest) returns (GetInfoResponse);
    rpc Ping(PingRequest) returns (PingResponse);
    rpc ClosestPrecedingFinger(ClosestPrecedingFingerRequest) returns (ClosestPrecedingFingerResponse);
}
```

## Command Line Interface

### Node Application

```bash
./chord-node [options]

Options:
  --addr string       Node address (IP:port) (default "localhost:5000")
  --bootstrap string  Bootstrap node address (empty for first node)
  --id string        Node ID (hex string, auto-generated if empty)
  --metrics string   Directory to save metrics CSV files (default "results")
```

**Examples:**
```bash
# Bootstrap node (creates new ring)
./chord-node --addr=localhost:5000 --bootstrap="" --metrics=results

# Regular node (joins existing ring)
./chord-node --addr=localhost:5001 --bootstrap=localhost:5000 --metrics=results

# Custom node ID
./chord-node --addr=localhost:5002 --bootstrap=localhost:5000 --id=abc123 --metrics=results
```

### Simulator Application

```bash
./chord-simulator [options]

Options:
  --nodes int           Number of nodes to simulate (default 5)
  --base-port int       Base port number (default 6000)
  --lookups int         Number of random lookups (default 100)
  --duration duration   Duration to run simulation (default 60s)
  --results-dir string  Directory to save results (default "results")
  --experiment-id string Experiment ID (auto-generated if empty)
```

## Metrics Collection

### CSV Format

Each node generates a CSV file: `node_{nodeID}_{experimentID}.csv`

```csv
timestamp,nodes,messages,lookups,avg_lookup_ms
1637123456,3,45,12,23.45
1637123486,3,67,18,19.23
```

### Global Metrics

The simulator also generates a global summary: `global_{experimentID}.csv`

### Metrics Interpretation

- **timestamp**: Unix timestamp
- **nodes**: Number of known nodes in the ring
- **messages**: Cumulative messages sent/received
- **lookups**: Cumulative lookup operations performed
- **avg_lookup_ms**: Average lookup latency in milliseconds

## Docker Deployment

### Build Image

```bash
make docker
```

### Run Bootstrap Node

```bash
docker run -d --name chord-bootstrap \
    -p 5000:5000 \
    chord-dht:latest \
    --addr=0.0.0.0:5000 \
    --bootstrap="" \
    --metrics=/app/results
```

### Run Additional Nodes

```bash
docker run -d --name chord-node-2 \
    -p 5001:5000 \
    chord-dht:latest \
    --addr=0.0.0.0:5000 \
    --bootstrap=<bootstrap-ip>:5000 \
    --metrics=/app/results
```

### Extract Metrics

```bash
docker cp chord-bootstrap:/app/results ./results
```

## Testing

### Unit Tests

```bash
make test           # All tests
make test-short     # Unit tests only
```

### Integration Tests

```bash
# Run integration tests (creates real network of nodes)
go test -v ./test/...
```

### Benchmarks

```bash
make benchmark      # Performance benchmarks
```

### Test Coverage

```bash
make coverage       # Generate coverage report
```

## Performance Characteristics

### Theoretical Complexity
- **Lookup**: O(log N) messages
- **Join**: O(log² N) messages  
- **Node failure recovery**: O(log² N) messages

### Measured Performance (Local Network)
- **Lookup Latency**: 1-10ms for 5-100 nodes
- **Join Time**: 2-5 seconds for stabilization
- **Memory Usage**: ~10MB per node
- **Network Overhead**: ~50-200 messages/minute per node

### Scalability Testing
- Tested up to 1000 nodes in simulation
- Maintains O(log N) complexity
- Suitable for production deployment

## Troubleshooting

### Common Issues

1. **"Port already in use"**
   ```bash
   # Find and kill process using port
   sudo lsof -i :5000
   sudo kill -9 <PID>
   ```

2. **"Bootstrap connection failed"**
   ```bash
   # Verify bootstrap node is running
   curl -v telnet://bootstrap-ip:5000
   
   # Check firewall rules
   sudo ufw status
   ```

3. **"Protobuf generation failed"**
   ```bash
   # Install required tools
   make deps
   ```

4. **Nodes not joining ring**
   - Verify network connectivity between VMs
   - Check firewall rules allow port 5000
   - Ensure bootstrap node is accessible from joining nodes

### Debug Mode

Enable verbose logging:
```bash
./chord-node --addr=localhost:5000 --bootstrap="" --verbose
```

### Health Checks

```bash
# Check if node is responding
curl http://node-ip:5000/health

# View node information (via gRPC)
grpcurl -plaintext node-ip:5000 proto.ChordService/GetInfo
```

## Build System

### Makefile Targets

```bash
make help           # Show all available targets
make build          # Build binaries
make proto          # Generate protobuf code
make test           # Run all tests
make docker         # Build Docker image
make clean          # Clean build artifacts
make dev-ring       # Start development ring
make simulator      # Run simulator
```

### Cross-Platform Builds

```bash
make build-linux    # Linux binaries
make build-windows  # Windows binaries
make build-mac      # macOS binaries
make build-all      # All platforms
```

## Contributing

### Development Setup

1. Fork repository
2. Install dependencies: `make deps`
3. Generate protobuf: `make proto`
4. Run tests: `make test`
5. Build: `make build`

### Code Style

- Follow Go formatting: `make fmt`
- Run linter: `make lint`
- Add tests for new features
- Update documentation

### Pull Request Process

1. Create feature branch
2. Add tests for new functionality
3. Ensure all tests pass
4. Update documentation
5. Submit pull request

## License

MIT License - see LICENSE file for details.

## References

- [Chord: A Scalable Peer-to-peer Lookup Protocol](https://pdos.csail.mit.edu/papers/chord:sigcomm01/chord_sigcomm.pdf)
- [gRPC Documentation](https://grpc.io/docs/)
- [Protocol Buffers Guide](https://developers.google.com/protocol-buffers)
- [Google Cloud Compute Engine](https://cloud.google.com/compute/docs)