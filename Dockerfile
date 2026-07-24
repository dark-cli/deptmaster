# Build stage
FROM rust:latest as builder

WORKDIR /app

# Copy workspace files (root level)
COPY Cargo.toml Cargo.lock ./

# Copy all crate manifests for dependency caching
COPY crates/server/Cargo.toml ./crates/server/
COPY crates/client/Cargo.toml ./crates/client/
COPY crates/core/domain/Cargo.toml ./crates/core/domain/
COPY crates/core/applier/Cargo.toml ./crates/core/applier/
COPY crates/core/resolver/Cargo.toml ./crates/core/resolver/
COPY crates/core/snapshots/Cargo.toml ./crates/core/snapshots/

# Copy actual source code
COPY crates ./crates

# Build release binary
RUN cargo build --release

# Runtime stage
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y \
    ca-certificates \
    libssl3 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy binary from builder
COPY --from=builder /app/target/release/server /app/server

# Run the application
CMD ["./server"]
