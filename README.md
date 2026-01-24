# Debt Tracker (IOU Tracker)

A modern debt management application with event-sourced architecture, offline-first design, and cross-platform support.

## Features

- 📱 **Cross-platform**: iOS, Android, Web, and Linux Desktop
- 🔄 **Offline-first**: Works offline, syncs when online
- 🔍 **Real-time sync**: Firebase-like instant updates via WebSocket
- 📊 **Event-sourced**: Complete audit trail, no data loss
- 🖥️ **Admin Panel**: Web-based monitoring and debugging
- 🔒 **Secure**: Event sourcing with idempotency and version tracking

## Tech Stack

- **Backend**: Rust (Axum) - High-performance API server
- **Mobile/Web**: Flutter (Dart) - Cross-platform UI
- **Database**: PostgreSQL (events and projections)
- **Real-time**: WebSocket with broadcast channels
- **Deployment**: Docker

## Quick Start

### Prerequisites

- Rust (latest stable)
- Flutter SDK (for mobile/web apps)
- Docker & Docker Compose
- PostgreSQL 14+ (via Docker)

### Setup

1. **Initial setup**:
   ```bash
   ./scripts/setup.sh
   ```

2. **Start server**:
   ```bash
   ./scripts/manage.sh start-server
   ```

3. **Run mobile app**:
   ```bash
   ./scripts/mobile.sh run android
   ```

4. **Access admin panel**:
   Open http://localhost:8000/admin in your browser

## Project Structure

```
.
├── backend/          # Rust backend server
│   └── rust-api/    # API server
│       └── static/   # Static web files
│           ├── admin/  # Admin panel
│           └── app/    # Standalone web app
├── mobile/          # Flutter mobile/web app
├── scripts/         # Management scripts
│   ├── manage.sh    # Server management
│   ├── mobile.sh    # Mobile app management
│   └── setup.sh     # Initial setup
├── docs/            # Documentation
│   ├── ARCHITECTURE.md
│   ├── API.md
│   ├── DEVELOPMENT.md
│   └── DEPLOYMENT.md
└── LICENSE
```

## Scripts

All scripts are in the `scripts/` directory:

### Server Management (`scripts/manage.sh`)

```bash
./scripts/manage.sh start-server    # Start API server
./scripts/manage.sh stop-server     # Stop API server
./scripts/manage.sh status          # Check system status
./scripts/manage.sh full-flash      # Reset everything
./scripts/manage.sh import backup.zip  # Import data
./scripts/manage.sh help            # Show all commands
```

### Mobile App (`scripts/mobile.sh`)

```bash
./scripts/mobile.sh run android    # Run Android app
./scripts/mobile.sh run web         # Run web app
./scripts/mobile.sh run linux       # Run Linux desktop
./scripts/mobile.sh build android   # Build Android APK
./scripts/mobile.sh test            # Run tests
./scripts/mobile.sh setup           # Setup Flutter app
```

### Setup (`scripts/setup.sh`)

```bash
./scripts/setup.sh                  # Initial project setup
```

## Admin Panel

The admin panel is available at `http://localhost:8000/admin` and provides:
- Real-time data monitoring
- Event store inspection
- Contact and transaction views
- Projection status
- Debt charts and statistics

## Documentation

Complete documentation is available in the `docs/` directory:

- **[Architecture](./docs/ARCHITECTURE.md)** - System architecture, event sourcing, real-time updates
- **[API Reference](./docs/API.md)** - Complete API endpoint documentation
- **[Development Guide](./docs/DEVELOPMENT.md)** - Development setup, testing, admin panel
- **[Deployment Guide](./docs/DEPLOYMENT.md)** - Production deployment instructions

## Development

### Backend Development

```bash
# Start services
./scripts/manage.sh start-services

# Build server
./scripts/manage.sh build

# Start server
./scripts/manage.sh start-server

# View logs
./scripts/manage.sh logs
```

### Mobile Development

```bash
# Setup Flutter app
./scripts/mobile.sh setup

# Run app
./scripts/mobile.sh run android

# Run tests
./scripts/mobile.sh test
```

## Key Features

### Event Sourcing
- All changes stored as immutable events
- Complete audit trail
- Idempotency support
- Version tracking for optimistic locking

### Real-Time Updates
- WebSocket-based instant updates
- Firebase-like experience
- Auto-reconnect on connection loss
- Broadcast to all connected clients

### Offline-First
- Works without internet connection
- Local storage with Hive (mobile/desktop)
- Automatic sync when online
- Seamless online/offline transition

## License

GNU General Public License v3.0 - See [LICENSE](./LICENSE) file for details.

## Contributing

See [Development Guide](./docs/DEVELOPMENT.md) for contribution guidelines.
