# Debt Tracker Documentation

Complete documentation for the Debt Tracker application.

## Documentation

- **[Architecture](./ARCHITECTURE.md)** - System architecture, event sourcing, real-time updates
- **[API Reference](./API.md)** - Complete API endpoint documentation
- **[Development Guide](./DEVELOPMENT.md)** - Development setup, testing, admin panel, database management
- **[Deployment Guide](./DEPLOYMENT.md)** - Production deployment instructions
- **[Integration test commands](./INTEGRATION_TEST_COMMANDS.md)** - Command/assert vocabulary for Rust client core integration tests (`run_commands`, `assert_commands`)

## Quick Links

- **Setup**: See [Development Guide](./DEVELOPMENT.md#quick-start)
- **API**: See [API Reference](./API.md)
- **Architecture**: See [Architecture](./ARCHITECTURE.md)

## Project Overview

Debt Tracker is a cross-platform debt management application with:
- **Real-time synchronization** using WebSockets
- **Offline-first** architecture with local storage
- **Event-sourced** database for complete audit trail
- **Cross-platform** support (Web, iOS, Android, Linux Desktop)

## Tech Stack

- **Backend**: Rust (Axum), PostgreSQL, EventStore DB
- **Frontend**: Flutter (Dart), Riverpod, Hive
- **Real-time**: WebSocket with broadcast channels

## Getting Started

```bash
# Start services
./manage.sh start-services

# Start server
./manage.sh start-server

# Run app
./manage.sh run-app android
```

For detailed setup instructions, see the [Development Guide](./DEVELOPMENT.md).
