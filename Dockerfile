# Multi-stage Dockerfile for Chord DHT

# Stage 1: Build stage
FROM golang:1.24-alpine AS builder

# Install protobuf compiler and git
RUN apk add --no-cache git protobuf-dev make

# Set working directory
WORKDIR /app

# Copy go mod files first for better caching
COPY go.mod go.sum ./

# Download dependencies
RUN go mod download

# Install protobuf Go plugins
RUN go install google.golang.org/protobuf/cmd/protoc-gen-go@latest && \
    go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@latest

# Copy source code
COPY . .

# Generate protobuf code
RUN export PATH=$PATH:$(go env GOPATH)/bin && \
    protoc --go_out=. --go-grpc_out=. proto/chord.proto

# Build the applications
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o chord-node ./cmd/node && \
    CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o chord-simulator ./cmd/simulator

# Stage 2: Runtime stage
FROM alpine:latest

# Install ca-certificates for HTTPS requests
RUN apk --no-cache add ca-certificates tzdata

# Create non-root user
RUN addgroup -g 1001 -S chord && \
    adduser -u 1001 -S chord -G chord

WORKDIR /app

# Copy binaries from builder stage
COPY --from=builder /app/chord-node .
COPY --from=builder /app/chord-simulator .

# Create directories for results
RUN mkdir -p /app/results && \
    chown -R chord:chord /app

# Switch to non-root user
USER chord

# Expose default port
EXPOSE 5000

# Default command runs a single node
# Can be overridden with docker run arguments
ENTRYPOINT ["./chord-node"]
CMD ["--addr=0.0.0.0:5000", "--bootstrap=", "--metrics=/app/results"]

# Labels for metadata
LABEL maintainer="chord-dht-team"
LABEL description="Chord DHT implementation in Go"
LABEL version="1.0"

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD nc -z localhost 5000 || exit 1