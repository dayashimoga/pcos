# PCOS Operations Runbook

## Quick Reference

| Action | Command |
|--------|---------|
| Start dev stack | `docker compose up -d` |
| Start prod stack | `docker compose -f docker-compose.yml up -d` |
| View logs | `docker compose logs -f backend` |
| Run migrations | Automatic on startup |
| Health check | `curl http://localhost:8080/health` |
| Run unit tests | `cargo test -p pcos-common` |
| Run integration tests | `cargo test --test integration -- --ignored` |
| Backend shell | `docker compose exec backend sh` |
| DB shell | `docker compose exec postgres psql -U pcos -d pcos` |

---

## Startup Checklist

1. **Environment**: Copy `backend/.env.example` → `backend/.env` and fill:
   ```
   PCOS_DATABASE__URL=postgresql://pcos:password@localhost:5432/pcos
   PCOS_AUTH__JWT_SECRET=your-64-char-secret-here
   ```

2. **Storage directory**: Created automatically on startup at `PCOS_STORAGE__BASE_PATH`

3. **Database**: Migrations run automatically via `sqlx::migrate!`

4. **Verify**: `curl http://localhost:8080/health` → `{"status":"healthy",...}`

---

## Common Operations

### Reset Database
```bash
docker compose exec postgres psql -U pcos -d pcos -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public;"
docker compose restart backend
```

### Force Re-migration
```bash
docker compose exec postgres psql -U pcos -d pcos -c "DROP TABLE IF EXISTS _sqlx_migrations;"
docker compose restart backend
```

### Check Background Tasks
Background tasks log to stdout:
```bash
docker compose logs backend | grep -E "(Cleaned|auto-deleted|deactivat)"
```

Active tasks:
- **Token cleanup**: Every hour, deletes expired/revoked refresh tokens
- **Trash cleanup**: Every 6 hours, permanently deletes items trashed >30 days
- **Share expiry**: Every hour, deactivates expired share links

### Monitor Storage Usage
```bash
# Per-user via API
curl -H "Authorization: Bearer $TOKEN" http://localhost:8080/api/v1/storage/stats

# Disk level
du -sh /data/pcos/storage/
```

### Prometheus Metrics
```
GET /api/v1/admin/metrics
```
Scrape endpoint for Grafana/Prometheus stack.

---

## Troubleshooting

### Backend won't start
| Symptom | Cause | Fix |
|---------|-------|-----|
| `Failed to load configuration` | Missing env vars | Check `.env` file has `DATABASE__URL` and `AUTH__JWT_SECRET` |
| `connection refused` on DB | Postgres not ready | `docker compose up -d postgres && sleep 5 && docker compose up -d backend` |
| Migration error | Schema conflict | Reset DB (see above) |
| `SQLX_OFFLINE=true` build fail | Missing query cache | Run `cargo sqlx prepare` with live DB |

### Frontend won't connect
| Symptom | Cause | Fix |
|---------|-------|-----|
| CORS errors in browser | Wrong origins | Set `PCOS_CORS_ORIGINS=http://localhost:3000` |
| 401 on every request | Token expired | Check `SharedPreferences` or re-login |
| Blank page | JS error | Check browser console, ensure `flutter build web` succeeded |

### Agent won't sync
| Symptom | Cause | Fix |
|---------|-------|-----|
| `Connection refused` | Backend not reachable | Check `server_url` in agent config TOML |
| `401 Unauthorized` | Token expired | Re-register agent: `pcos-agent --register` |
| Files not uploading | Ignore patterns | Check `ignore_patterns` in config |

---

## Backup & Recovery

### Database Backup
```bash
docker compose exec postgres pg_dump -U pcos -d pcos -F c -f /tmp/pcos_backup.dump
docker compose cp postgres:/tmp/pcos_backup.dump ./backups/
```

### Database Restore
```bash
docker compose cp ./backups/pcos_backup.dump postgres:/tmp/
docker compose exec postgres pg_restore -U pcos -d pcos -c /tmp/pcos_backup.dump
```

### Storage Backup
```bash
tar czf pcos_storage_$(date +%Y%m%d).tar.gz /data/pcos/storage/
```

---

## Security Checklist

- [ ] JWT secret is 64+ chars, randomly generated
- [ ] `PCOS_CORS_ORIGINS` set to specific domains (not `*`) in production
- [ ] PostgreSQL password changed from default
- [ ] Redis password set if exposed
- [ ] HTTPS enabled via Caddy or reverse proxy
- [ ] Storage directory permissions: `700` (owner only)
- [ ] Regular DB backups scheduled
- [ ] Log aggregation configured

---

## Scaling Notes

| Component | Scaling Strategy |
|-----------|-----------------|
| Backend | Horizontal — stateless, share DB + storage |
| PostgreSQL | Vertical first, then read replicas |
| Storage | Network filesystem (NFS/CIFS) for shared access |
| Redis | Single instance sufficient for caching |
| Frontend | CDN-served static assets |
