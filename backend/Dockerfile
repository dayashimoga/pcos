FROM rust:latest AS builder

WORKDIR /app

# Install required system dependencies
RUN apt-get update && apt-get install -y pkg-config libssl-dev && rm -rf /var/lib/apt/lists/*

# Copy workspace manifest and lockfile for dependency caching
COPY Cargo.toml Cargo.lock* ./

# Copy ALL crate manifests for workspace dependency resolution
COPY crates/common/Cargo.toml crates/common/Cargo.toml
COPY crates/auth/Cargo.toml crates/auth/Cargo.toml
COPY crates/user/Cargo.toml crates/user/Cargo.toml
COPY crates/device/Cargo.toml crates/device/Cargo.toml
COPY crates/file_metadata/Cargo.toml crates/file_metadata/Cargo.toml
COPY crates/search/Cargo.toml crates/search/Cargo.toml
COPY crates/ai/Cargo.toml crates/ai/Cargo.toml
COPY crates/sharing/Cargo.toml crates/sharing/Cargo.toml
COPY crates/sync_engine/Cargo.toml crates/sync_engine/Cargo.toml
COPY crates/notification/Cargo.toml crates/notification/Cargo.toml
COPY crates/worker/Cargo.toml crates/worker/Cargo.toml
COPY crates/backup/Cargo.toml crates/backup/Cargo.toml
COPY crates/analytics/Cargo.toml crates/analytics/Cargo.toml
COPY crates/gateway/Cargo.toml crates/gateway/Cargo.toml
COPY crates/streaming/Cargo.toml crates/streaming/Cargo.toml

# Create dummy source files to cache dependency compilation
RUN for crate in common auth user device file_metadata search ai sharing sync_engine notification worker backup analytics streaming; do \
      mkdir -p crates/$crate/src && echo "" > crates/$crate/src/lib.rs; \
    done && \
    mkdir -p crates/gateway/src && echo "fn main() {}" > crates/gateway/src/main.rs

# Build dependencies only (this layer is cached unless Cargo.toml changes)
RUN cargo build --release 2>/dev/null || true

# Copy actual source code
COPY crates/ crates/
COPY migrations/ migrations/
COPY .sqlx/ .sqlx/

# Touch source files to invalidate the build cache for our code only
RUN find crates -name "*.rs" -exec touch {} +

# Build the actual application
ENV SQLX_OFFLINE=true
RUN cargo build --release --bin pcos-server

# Runtime stage - minimal image (Debian Trixie matching rust:latest GLIBC 2.39)
FROM debian:trixie-slim AS runtime

RUN apt-get update && apt-get install -y ca-certificates curl && rm -rf /var/lib/apt/lists/*

RUN useradd -m -u 1001 pcos
RUN mkdir -p /data/pcos/storage && chown -R pcos:pcos /data/pcos

COPY --from=builder /app/target/release/pcos-server /usr/local/bin/pcos-server

USER pcos

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

ENTRYPOINT ["pcos-server"]
