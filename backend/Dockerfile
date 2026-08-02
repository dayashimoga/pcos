# Build stage
FROM rust:1.79-bookworm AS builder

WORKDIR /app

# Install required system dependencies
RUN apt-get update && apt-get install -y pkg-config libssl-dev && rm -rf /var/lib/apt/lists/*

# Copy workspace manifests first for dependency caching
COPY Cargo.toml Cargo.toml
COPY crates/common/Cargo.toml crates/common/Cargo.toml
COPY crates/auth/Cargo.toml crates/auth/Cargo.toml
COPY crates/user/Cargo.toml crates/user/Cargo.toml
COPY crates/device/Cargo.toml crates/device/Cargo.toml
COPY crates/gateway/Cargo.toml crates/gateway/Cargo.toml

# Create dummy source files to cache dependency compilation
RUN mkdir -p crates/common/src && echo "pub mod auth; pub mod config; pub mod db; pub mod error; #[derive(Clone)] pub struct AppState { pub db: DatabasePool, pub config: AppConfig } pub use config::AppConfig; pub use db::DatabasePool; pub use error::AppError; impl AppState { pub fn new(db: DatabasePool, config: AppConfig) -> Self { Self { db, config } } }" > crates/common/src/lib.rs
RUN mkdir -p crates/auth/src && echo "" > crates/auth/src/lib.rs
RUN mkdir -p crates/user/src && echo "" > crates/user/src/lib.rs
RUN mkdir -p crates/device/src && echo "" > crates/device/src/lib.rs
RUN mkdir -p crates/gateway/src && echo "fn main() {}" > crates/gateway/src/main.rs

# Build dependencies only (this layer is cached unless Cargo.toml changes)
RUN cargo build --release 2>/dev/null || true

# Copy actual source code
COPY crates/ crates/
COPY migrations/ migrations/

# Touch source files to invalidate the build cache for our code only
RUN find crates -name "*.rs" -exec touch {} +

# Build the actual application
ENV SQLX_OFFLINE=true
RUN cargo build --release --bin pcos-server

# Runtime stage - minimal image
FROM debian:bookworm-slim AS runtime

RUN apt-get update && apt-get install -y ca-certificates curl && rm -rf /var/lib/apt/lists/*

RUN useradd -m -u 1001 pcos

COPY --from=builder /app/target/release/pcos-server /usr/local/bin/pcos-server

USER pcos

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

ENTRYPOINT ["pcos-server"]
