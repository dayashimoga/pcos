# PCOS QA — Autonomous Production Certification

## Architecture

```
qa/
├── feature_registry.json      # Machine-readable feature map (36 features, 12 modules)
├── docker-compose.test.yml    # Isolated test environment (PostgreSQL, Redis, NATS, backend)
├── fixtures/
│   └── seed_data.json         # Test users, files, folders, chaos scenarios, perf thresholds
├── scripts/
│   ├── orchestrator.sh        # Full certification run (provision → test → report → teardown)
│   ├── certify.sh             # Quality gate verification (reads certification.json)
│   └── self_heal.sh           # Self-healing iteration loop (max 5 iterations)
└── reports/                   # Generated reports (JSON, JUnit XML, Markdown)
    └── latest/                # Most recent passing certification
```

## Quick Start

```bash
# Full autonomous certification (provision → test → report → teardown)
bash qa/scripts/orchestrator.sh

# Keep environment alive for debugging
bash qa/scripts/orchestrator.sh --keep-env

# Self-healing loop (runs up to 5 iterations)
bash qa/scripts/self_heal.sh

# Verify quality gates from existing report
bash qa/scripts/certify.sh qa/reports/latest/certification.json
```

## Feature Registry

36 features across 12 modules with machine-readable acceptance criteria:

| Module | Features | Critical | Coverage Target |
|--------|----------|----------|----------------|
| auth | 7 | 5 (register, login, MFA, RBAC, tokens) | 95–100% |
| file_metadata | 5 | 2 (upload, download) | 95–100% |
| sharing | 1 | 0 | 95% |
| search | 2 | 0 | 85–90% |
| sync | 3 | 1 (WebSocket) | 85–100% |
| backup | 3 | 1 (create/restore) | 95–100% |
| notification | 3 | 0 | 85–90% |
| ai | 1 | 0 | 80% |
| device | 1 | 0 | 90% |
| admin | 1 | 0 | 90% |
| common | 3 | 1 (E2EE) | 85–100% |
| infrastructure | 3 | 2 (Docker, CI/CD) | 85–95% |

## Quality Gates

| Gate | Target |
|------|--------|
| Overall pass rate | ≥ 90% |
| Critical module coverage | ≥ 95% |
| Auth/Sync/Encryption coverage | 100% |
| Critical defects | 0 |
| High-severity defects | 0 |
| Regressions | 0 |
| Placeholders | 0 |
| Incomplete workflows | 0 |

## Test Types

| Type | Tool | Scope |
|------|------|-------|
| Unit | `cargo test` | All Rust crates + agent |
| Integration | `cargo test` + Docker services | DB, Redis, NATS interactions |
| API | curl/orchestrator.sh | 30+ HTTP endpoint validations |
| E2E | orchestrator.sh | Full user journeys |
| Security | cargo-deny, secret scan | Dependencies, licenses, secrets |
| Chaos | fixtures/seed_data.json | 5 failure injection scenarios |
| Performance | fixtures/seed_data.json | Latency, throughput, resource thresholds |

## CI/CD Integration

The `certification.yml` workflow runs on every PR and release:

1. **Build & Test** — Backend + agent `cargo test`
2. **Security** — `cargo-deny` audit + secret scanning
3. **Integration** — Live PostgreSQL + Redis, API smoke tests
4. **Docker Validation** — All 3 compose files validated
5. **Certification Report** — JSON + GitHub Summary with pass/fail verdict

## Reports

Generated in `qa/reports/<timestamp>/`:

| File | Format | Contents |
|------|--------|----------|
| `certification.json` | JSON | Full results, pass/fail, feature matrix |
| `certification_report.md` | Markdown | Human-readable summary |
| `junit/results.xml` | JUnit XML | CI-compatible test results |
| `rust_tests.log` | Text | Cargo test output |
| `agent_tests.log` | Text | Agent test output |
| `provision.log` | Text | Docker provisioning output |

## Blocked Features

Features requiring external infrastructure that cannot be validated in CI:

| Feature | Blocker |
|---------|---------|
| AI Auto-Tag | Requires Ollama instance |
| OCR (images) | Requires Tesseract binary |
| LDAP/AD | Requires ldap3 crate + LDAP server |
| Kubernetes | Requires K8s cluster |
