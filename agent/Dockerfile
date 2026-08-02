# Build stage
FROM rust:1.79-bookworm AS builder

WORKDIR /app

RUN apt-get update && apt-get install -y pkg-config libssl-dev && rm -rf /var/lib/apt/lists/*

COPY Cargo.toml Cargo.lock* ./
RUN mkdir src && echo "fn main() {}" > src/main.rs
RUN cargo build --release 2>/dev/null || true

COPY src/ src/
RUN touch src/main.rs && cargo build --release --bin pcos-agent

# Runtime stage
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y ca-certificates && rm -rf /var/lib/apt/lists/*

RUN useradd -m -u 1001 pcos
RUN mkdir -p /data/pcos/sync && chown -R pcos:pcos /data/pcos

COPY --from=builder /app/target/release/pcos-agent /usr/local/bin/pcos-agent

USER pcos

ENTRYPOINT ["pcos-agent"]
CMD ["--sync-dir", "/data/pcos/sync"]
