# Debt Tracker - Project Plan

A modern debt management application with event-sourced architecture.

## Tech Stack

- **Backend**: Rust (Axum) - Pure Rust, no Python
- **Mobile**: Flutter (Dart)
- **Web**: Flutter Web
- **Database**: PostgreSQL (event store + projections)
- **Cache**: Redis
- **Deployment**: Docker

## Architecture

- **Event Sourcing**: Write-only append log, complete audit trail
- **Offline-First**: Works offline, syncs when online
- **Cross-Platform**: iOS, Android, Web

## Project Structure

```
.
├── backend/rust-api/    # Rust API server + background tasks
├── mobile/              # Flutter mobile app
├── web/                 # Flutter web app
├── scripts/             # Utility scripts
└── docker-compose.yml   # Development environment
```

## Development Phases

### Phase 1: Foundation ✅
- [x] Project structure
- [x] Rust backend setup
- [x] Docker Compose
- [x] Database schema
- [ ] Basic API endpoints

### Phase 2: Authentication
- [ ] User registration
- [ ] User login
- [ ] JWT tokens
- [ ] Password hashing

### Phase 3: Core Features
- [ ] Contacts CRUD
- [ ] Transactions CRUD
- [ ] Event sourcing implementation
- [ ] Projections

### Phase 4: Sync
- [ ] Event-based sync
- [ ] Conflict resolution
- [ ] Offline queue

### Phase 5: Search & Notifications
- [ ] Full-text search
- [ ] Email notifications
- [ ] Push notifications
- [ ] Reminders

### Phase 6: Polish
- [ ] Testing
- [ ] Documentation
- [ ] Performance optimization
- [ ] Security audit

## Quick Start

```bash
# Setup
./scripts/setup.sh

# Start services
docker-compose up -d

# Run backend
cd backend/rust-api && cargo run
```

## Documentation

- [Rust Backend Guide](RUST_BACKEND.md)
- [Additional Considerations](ADDITIONAL_CONSIDERATIONS.md)
- [Development Checklist](DEVELOPMENT_CHECKLIST.md)
