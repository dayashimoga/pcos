# PCOS Deployment Guide

## Prerequisites
- Docker Engine 24+ and Docker Compose v2
- At least 2GB RAM, 10GB disk space
- A domain name (optional, for HTTPS)

## Quick Start (Docker Compose)

```bash
# Clone the repository
git clone https://github.com/pcos/pcos.git
cd pcos

# Create environment file
cp backend/.env.example .env

# IMPORTANT: Change the JWT secret
# Generate a random secret: openssl rand -base64 64
# Edit .env and set PCOS_JWT_SECRET

# Start all services
docker compose up -d

# Check status
docker compose ps
docker compose logs -f backend
```

The application will be available at:
- **Web UI**: http://localhost (via Caddy) or http://localhost:3000 (direct)
- **API**: http://localhost:8080
- **API via proxy**: http://localhost/api/v1

## Production Deployment

### 1. Configure HTTPS
Edit `caddy/Caddyfile` to use your domain:
```
yourdomain.com {
    handle /api/* {
        reverse_proxy backend:8080
    }
    handle {
        reverse_proxy frontend:80
    }
}
```

### 2. Set Environment Variables
```bash
export PCOS_JWT_SECRET=$(openssl rand -base64 64)
export POSTGRES_PASSWORD=$(openssl rand -base64 32)
```

### 3. Deploy
```bash
docker compose -f docker-compose.yml up -d
```

## Backup
```bash
# Database backup
docker compose exec postgres pg_dump -U pcos pcos > backup.sql

# Restore
cat backup.sql | docker compose exec -T postgres psql -U pcos pcos
```

## Monitoring
- Health check: `GET /health`
- PostgreSQL: `docker compose exec postgres pg_isready`
- Redis: `docker compose exec redis redis-cli ping`
- NATS: `http://localhost:8222/healthz`
