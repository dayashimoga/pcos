# PCOS Development Guide

## Project Structure
```
pcos/
├── backend/                 # Rust backend (Cargo workspace)
│   ├── crates/
│   │   ├── common/          # Shared types, config, auth, DB
│   │   ├── auth/            # Authentication service
│   │   ├── user/            # User profile service
│   │   ├── device/          # Device management service
│   │   └── gateway/         # Main binary, router
│   └── migrations/          # SQL migration files
├── frontend/                # Flutter web client
│   └── lib/
│       ├── core/            # Theme, routing, DI, network
│       └── features/        # Feature modules (auth, dashboard, devices)
├── caddy/                   # Reverse proxy config
├── docs/                    # Documentation
├── docker-compose.yml       # Production Docker Compose
├── docker-compose.dev.yml   # Development overrides
└── .github/workflows/       # CI/CD pipelines
```

## Development Setup

### Using Docker (Recommended)
```bash
# Start infrastructure + backend with hot reload
docker compose -f docker-compose.yml -f docker-compose.dev.yml up -d

# View logs
docker compose logs -f backend
```

### Local Development

**Backend (requires Rust 1.79+):**
```bash
cd backend
cp .env.example .env  # Edit with your local PostgreSQL URL
cargo run --bin pcos-server
```

**Frontend (requires Flutter 3.24+):**
```bash
cd frontend
flutter pub get
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8080
```

## Code Style
- **Rust**: `cargo fmt` (default rustfmt settings), `cargo clippy -- -D warnings`
- **Dart**: `dart format .`, `dart analyze`

## Testing
```bash
# Backend tests
cd backend && cargo test --all

# Frontend tests
cd frontend && flutter test

# With coverage
cd frontend && flutter test --coverage
```

## Adding a New Feature
1. Create a new crate in `backend/crates/` for the backend service
2. Add models, service, handlers following existing patterns
3. Add the router to `gateway/src/main.rs`
4. Create a new feature directory in `frontend/lib/features/`
5. Add BLoC, repository, pages, widgets
6. Register in DI container (`service_locator.dart`)
7. Add route to `app_router.dart`
8. Write tests for both backend and frontend
9. Update documentation
