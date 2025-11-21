# Chord DHT Makefile

# Variables
BINARY_NODE=bin/chord-node
BINARY_SIMULATOR=bin/chord-simulator
PROTO_DIR=proto
BUILD_DIR=build
GO_VERSION=1.21

# Go parameters
GOCMD=go
GOBUILD=$(GOCMD) build
GOCLEAN=$(GOCMD) clean
GOTEST=$(GOCMD) test
GOGET=$(GOCMD) get
GOMOD=$(GOCMD) mod

# Docker parameters
DOCKER_IMAGE=chord-dht
DOCKER_TAG=latest

.PHONY: all build proto docker clean test run help deps

all: deps proto build ## Build everything

help: ## Show this help message
	@echo 'Management commands for Chord DHT:'
	@echo
	@echo 'Usage:'
	@echo '    make build       Compile the project'
	@echo '    make proto       Generate protobuf code'
	@echo '    make docker      Build docker image'
	@echo '    make test        Run tests'
	@echo '    make run         Run a single node'
	@echo '    make simulator   Run the simulator'
	@echo '    make clean       Clean up build artifacts'
	@echo '    make deps        Install dependencies'
	@echo

deps: ## Install Go dependencies
	@echo "Installing dependencies..."
	$(GOMOD) tidy
	$(GOMOD) download
	@echo "Installing protobuf tools..."
	$(GOCMD) install google.golang.org/protobuf/cmd/protoc-gen-go@latest
	$(GOCMD) install google.golang.org/grpc/cmd/protoc-gen-go-grpc@latest

proto: ## Generate protobuf code
	@echo "Generating protobuf code..."
	@mkdir -p $(PROTO_DIR)
	export PATH=$$PATH:$$($(GOCMD) env GOPATH)/bin && \
	protoc --go_out=. --go-grpc_out=. $(PROTO_DIR)/chord.proto
	@echo "Protobuf code generated successfully"

build: proto ## Build the binaries
	@echo "Building node binary..."
	@mkdir -p bin
	$(GOBUILD) -o $(BINARY_NODE) ./cmd/node
	@echo "Building simulator binary..."
	$(GOBUILD) -o $(BINARY_SIMULATOR) ./cmd/simulator
	@echo "Build completed successfully"

test: ## Run tests
	@echo "Running unit tests..."
	$(GOTEST) -v ./pkg/...
	$(GOTEST) -v ./internal/...
	@echo "Running integration tests..."
	$(GOTEST) -v ./test/...

test-short: ## Run short tests only
	@echo "Running short tests..."
	$(GOTEST) -short -v ./...

benchmark: ## Run benchmarks
	@echo "Running benchmarks..."
	$(GOTEST) -bench=. -benchmem ./...

run: build ## Run a single node (bootstrap)
	@echo "Starting bootstrap node..."
	./$(BINARY_NODE) --addr=localhost:5000 --bootstrap="" --metrics=results

run-node: build ## Run a node that joins existing ring
	@echo "Starting node that joins ring..."
	./$(BINARY_NODE) --addr=localhost:5001 --bootstrap=localhost:5000 --metrics=results

simulator: build ## Run the simulator
	@echo "Starting simulator..."
	@mkdir -p results
	./$(BINARY_SIMULATOR) --nodes=5 --lookups=100 --duration=60s --results-dir=results

# Docker targets
docker: ## Build Docker image
	@echo "Building Docker image..."
	docker build -t $(DOCKER_IMAGE):$(DOCKER_TAG) .
	@echo "Docker image built: $(DOCKER_IMAGE):$(DOCKER_TAG)"

docker-run: docker ## Run node in Docker
	@echo "Running node in Docker..."
	docker run -p 5000:5000 $(DOCKER_IMAGE):$(DOCKER_TAG) \
		--addr=0.0.0.0:5000 --bootstrap="" --metrics=/results

docker-clean: ## Remove Docker images
	docker rmi $(DOCKER_IMAGE):$(DOCKER_TAG) || true

# Deployment helpers for Google Cloud
deploy-vm1: build ## Deploy bootstrap node to VM1
	@echo "Deploying bootstrap node to VM1..."
	@echo "Run on VM1: ./$(BINARY_NODE) --addr=<VM1-IP>:5000 --bootstrap='' --metrics=results"

deploy-vm2: build ## Deploy node to VM2
	@echo "Deploying node to VM2..."
	@echo "Run on VM2: ./$(BINARY_NODE) --addr=<VM2-IP>:5000 --bootstrap=<VM1-IP>:5000 --metrics=results"

deploy-vm3: build ## Deploy node to VM3
	@echo "Deploying node to VM3..."
	@echo "Run on VM3: ./$(BINARY_NODE) --addr=<VM3-IP>:5000 --bootstrap=<VM1-IP>:5000 --metrics=results"

# Development helpers
dev-ring: build ## Start a local 3-node ring for development
	@echo "Starting development ring..."
	@mkdir -p results
	./$(BINARY_NODE) --addr=localhost:5000 --bootstrap="" --metrics=results &
	sleep 2
	./$(BINARY_NODE) --addr=localhost:5001 --bootstrap=localhost:5000 --metrics=results &
	sleep 2
	./$(BINARY_NODE) --addr=localhost:5002 --bootstrap=localhost:5000 --metrics=results &
	@echo "Development ring started. Press Ctrl+C to stop all nodes."
	wait

stop-dev: ## Stop all local nodes
	@echo "Stopping all local chord nodes..."
	pkill -f "chord-node" || true

# Cleanup
clean: ## Clean build artifacts
	@echo "Cleaning..."
	$(GOCLEAN)
	rm -rf bin/
	rm -rf $(BUILD_DIR)/
	rm -rf results/
	rm -f $(PROTO_DIR)/*.pb.go
	@echo "Clean completed"

# Formatting and linting
fmt: ## Format Go code
	$(GOCMD) fmt ./...

vet: ## Run go vet
	$(GOCMD) vet ./...

# Generate coverage report
coverage: ## Generate test coverage report
	@echo "Generating coverage report..."
	$(GOTEST) -coverprofile=coverage.out ./...
	$(GOCMD) tool cover -html=coverage.out -o coverage.html
	@echo "Coverage report generated: coverage.html"

# Version info
version: ## Show version information
	@echo "Go version: $$($(GOCMD) version)"
	@echo "Git commit: $$(git rev-parse --short HEAD 2>/dev/null || echo 'unknown')"
	@echo "Build time: $$(date)"

# Documentation
docs: ## Generate documentation
	@echo "Generating documentation..."
	$(GOCMD) doc -all ./... > docs/godoc.txt
	@echo "Documentation generated in docs/"

# Install tools
install-tools: ## Install development tools
	$(GOCMD) install github.com/golangci/golangci-lint/cmd/golangci-lint@latest
	$(GOCMD) install github.com/golang/mock/mockgen@latest

lint: install-tools ## Run linter
	golangci-lint run

# Performance testing
perf-test: build ## Run performance tests
	@echo "Running performance tests..."
	./$(BINARY_SIMULATOR) --nodes=10 --lookups=1000 --duration=300s --results-dir=perf-results
	@echo "Performance test completed. Results in perf-results/"

# Build for different architectures
build-linux: proto ## Build for Linux
	GOOS=linux GOARCH=amd64 $(GOBUILD) -o bin/chord-node-linux ./cmd/node
	GOOS=linux GOARCH=amd64 $(GOBUILD) -o bin/chord-simulator-linux ./cmd/simulator

build-windows: proto ## Build for Windows
	GOOS=windows GOARCH=amd64 $(GOBUILD) -o bin/chord-node.exe ./cmd/node
	GOOS=windows GOARCH=amd64 $(GOBUILD) -o bin/chord-simulator.exe ./cmd/simulator

build-mac: proto ## Build for macOS
	GOOS=darwin GOARCH=amd64 $(GOBUILD) -o bin/chord-node-mac ./cmd/node
	GOOS=darwin GOARCH=amd64 $(GOBUILD) -o bin/chord-simulator-mac ./cmd/simulator

build-all: build-linux build-windows build-mac ## Build for all platforms

# Check if required tools are installed
check-tools: ## Check if required tools are installed
	@echo "Checking required tools..."
	@which protoc >/dev/null || (echo "protoc not found. Install protobuf compiler." && exit 1)
	@which $(GOCMD) >/dev/null || (echo "Go not found. Install Go $(GO_VERSION)+" && exit 1)
	@echo "All required tools are installed"