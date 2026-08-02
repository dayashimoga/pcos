# PCOS Deployment Guide

## Prerequisites
- Docker Engine 24+ and Docker Compose v2
- At least 2GB RAM, 10GB disk space
- A domain name (optional, for HTTPS)

---

## Quick Start (Docker Compose — 3 commands)

```bash
git clone https://github.com/dayashimoga/pcos.git
cd pcos
cp .env.example .env    # Edit .env — change PCOS_JWT_SECRET and POSTGRES_PASSWORD
docker compose up -d
```

The stack automatically:
- Initializes PostgreSQL with migrations
- Creates storage directories
- Starts all 13 services
- Exposes HTTPS via Caddy (auto-cert with Let's Encrypt when domain configured)

### Services Available

| Service | URL | Notes |
|---------|-----|-------|
| Web UI | http://localhost | Via Caddy reverse proxy |
| API | http://localhost/api/v1 | Backend API |
| WebDAV | http://localhost/webdav | File manager compatibility |
| S3 | http://localhost/s3 | aws-cli/rclone compatible |
| Grafana | http://localhost:3001 | Monitoring dashboards |
| Health | http://localhost/health | Backend health check |

### Optional: Enable AI

```bash
docker compose --profile ai up -d
```

---

## Production Deployment

### 1. Generate Secrets
```bash
# Generate secure random values
openssl rand -hex 32   # For PCOS_JWT_SECRET
openssl rand -base64 32  # For POSTGRES_PASSWORD
openssl rand -base64 32  # For GRAFANA_ADMIN_PASSWORD
```

### 2. Configure HTTPS
Edit `caddy/Caddyfile` — replace `:80` with your domain:
```
yourdomain.com {
    handle /api/* {
        reverse_proxy backend:8080
    }
    handle /webdav/* {
        reverse_proxy backend:8080
    }
    handle /s3/* {
        reverse_proxy backend:8080
    }
    handle /grafana/* {
        reverse_proxy grafana:3000
    }
    handle {
        reverse_proxy frontend:80
    }
}
```

Caddy automatically obtains and renews Let's Encrypt TLS certificates.

### 3. Deploy
```bash
docker compose up -d
docker compose ps       # Verify all services healthy
docker compose logs -f backend  # Watch logs
```

### 4. Resource Recommendations

| Deployment | CPU | RAM | Disk |
|-----------|-----|-----|------|
| Home/Dev | 2 cores | 2 GB | 20 GB |
| Small team (1–10) | 4 cores | 4 GB | 100 GB |
| Medium (10–100) | 8 cores | 8 GB | 500 GB |
| Enterprise | 16+ cores | 16+ GB | 1+ TB |

---

## Kubernetes Deployment

Apply manifests from `k8s/` directory:

```bash
# Create namespace and deploy
kubectl apply -f k8s/deployment.yaml

# Update secrets (base64 encode your values)
echo -n "your-jwt-secret" | base64
kubectl edit secret pcos-secrets -n pcos

# Check status
kubectl get pods -n pcos
kubectl get ingress -n pcos
```

### Requirements
- Kubernetes 1.28+
- cert-manager (for TLS)
- nginx-ingress or similar
- StorageClass with ReadWriteMany for shared storage

---

## Backup & Recovery

### Automated (Docker)
The `backup` container runs daily at 02:00 UTC:
- Creates `pg_dump` compressed backups
- Retains last 30 backups automatically
- Stored in `backup_data` volume

### Manual Backup
```bash
# Database dump
docker compose exec postgres pg_dump -U pcos -Fc pcos > backup_$(date +%Y%m%d).dump

# File storage backup
docker run --rm -v pcos_file_storage:/data -v $(pwd):/backup alpine tar czf /backup/files_$(date +%Y%m%d).tar.gz /data

# Restore database
docker compose exec -T postgres pg_restore -U pcos -d pcos < backup.dump

# Restore files
docker run --rm -v pcos_file_storage:/data -v $(pwd):/backup alpine tar xzf /backup/files.tar.gz -C /
```

### API-Based Backup
```bash
# Create backup
curl -X POST http://localhost/api/v1/backups -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" -d '{"name":"weekly"}'

# Verify backup integrity
curl http://localhost/api/v1/backups/$BACKUP_ID/verify -H "Authorization: Bearer $TOKEN"

# Enforce retention (keep last 10)
curl -X POST http://localhost/api/v1/backups/retention -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" -d '{"keep_count":10}'
```

---

## Monitoring

| Check | Command |
|-------|---------|
| Health | `curl http://localhost/health` |
| PostgreSQL | `docker compose exec postgres pg_isready` |
| Redis | `docker compose exec redis redis-cli ping` |
| NATS | `curl http://localhost:8222/healthz` |
| Metrics | `curl http://localhost:8080/api/v1/admin/metrics` |
| Grafana | http://localhost:3001 (admin / `$GRAFANA_ADMIN_PASSWORD`) |

### Prometheus Targets
- Backend metrics (10s interval)
- PostgreSQL exporter (15s)
- Redis exporter (15s)
- Node exporter (15s — CPU, RAM, disk, network)
- Caddy metrics (30s)

---

## Upgrading

```bash
git pull origin main
docker compose build
docker compose up -d   # Zero-downtime with health checks
```

Migrations run automatically on backend startup.
