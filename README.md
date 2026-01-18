# Debt Tracker

A modern debt management application with event-sourced architecture, offline-first design, and cross-platform support.

## Features

- 📱 **Cross-platform**: iOS, Android, and Web
- 🔄 **Offline-first**: Works offline, syncs when online
- 🔍 **Full-text search**: Find anything quickly
- 🔔 **Automated reminders**: Never forget a debt
- 📊 **Event-sourced**: Complete audit trail, no data loss
- 🔒 **Secure**: End-to-end encryption option
- 🖥️ **Admin Panel**: Web-based monitoring and debugging

## Tech Stack

- **Backend**: Rust (Axum) - Pure Rust, no Python
- **Mobile**: Flutter (Dart)
- **Web**: Flutter Web
- **Database**: PostgreSQL (event store + projections)
- **Cache**: Redis
- **Deployment**: Docker

## Quick Start

### Prerequisites

- Rust (latest stable)
- Flutter SDK (for mobile/web apps)
- Docker & Docker Compose
- PostgreSQL 14+
- Redis

### Setup

1. **Clone and setup**:
   ```bash
   ./scripts/setup.sh
   ```

2. **Start services**:
   ```bash
   docker-compose up -d
   ```

3. **Run backend**:
   ```bash
   cd backend/rust-api
   cargo run
   ```

4. **Access admin panel**:
   Open http://localhost:8000/admin in your browser

5. **Run mobile app**:
   ```bash
   cd mobile
   flutter pub get
   flutter run
   ```

## Project Structure

```
.
├── backend/rust-api/    # Rust API server + background tasks
├── mobile/              # Flutter mobile app
├── web/                 # Flutter web app
├── web/admin/           # Admin panel (HTML/JS)
├── scripts/             # Utility scripts
└── docker-compose.yml   # Development environment
```

## Admin Panel

The admin panel is available at `http://localhost:8000/admin` and provides:
- Real-time data monitoring
- Event store inspection
- Contact and transaction views
- Projection status
- Auto-refresh every 30 seconds

## Development Status

- ✅ Project structure
- ✅ Rust backend foundation
- ✅ Flutter mobile app with dummy data
- ✅ Web admin panel
- ✅ Database schema
- ✅ Docker setup
- ⏳ Database connection (in progress)
- ⏳ Authentication (pending)

## Documentation

- [Project Plan](PROJECT_PLAN.md)
- [Rust Backend Guide](RUST_BACKEND.md)
- [Additional Considerations](ADDITIONAL_CONSIDERATIONS.md)
- [Development Checklist](DEVELOPMENT_CHECKLIST.md)

## License

[To be determined]
