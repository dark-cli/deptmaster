# Debt Tracker Documentation

This folder contains all documentation for the Debt Tracker application.

## Documentation Index

### Core Documentation

- **[Architecture](./ARCHITECTURE.md)** - System architecture and design overview
- **[API Reference](./API_REFERENCE.md)** - Complete API endpoint documentation
- **[Deployment Guide](./DEPLOYMENT.md)** - Production deployment instructions

### Feature Documentation

- **[Real-Time Sync](./REALTIME.md)** - Real-time updates and offline sync implementation
- **[EventStore Integration](./EVENTSTORE.md)** - Event sourcing with EventStore
- **[Event Audit Trail](./EVENT_AUDIT_TRAIL.md)** - Event sourcing patterns and audit trail
- **[Implementation Summary](./IMPLEMENTATION_SUMMARY.md)** - Quick summary of real-time sync implementation

### Development

- **[Testing Guide](./TESTING.md)** - Testing strategy and setup (Backend & Frontend)
- **[Admin Panel](./ADMIN_PANEL.md)** - Web admin panel guide and troubleshooting
- **[Migration Guide](./MIGRATION.md)** - Data migration documentation
- **[Rust Backend](./RUST_BACKEND.md)** - Backend development guide
- **[Reset Database](./RESET_DATABASE.md)** - Database reset and import guide

### Project Planning

- **[Project Plan](./PROJECT_PLAN.md)** - Initial project planning and requirements
- **[Additional Considerations](./ADDITIONAL_CONSIDERATIONS.md)** - Non-functional requirements
- **[Debitum Strengths](./DEBITUM_STRENGTHS.md)** - Analysis of original Debitum app features
- **[Database Solution Comparison](./DATABASE_SOLUTION_COMPARISON.md)** - Database technology comparison

### Reference

- **[Development Checklist](./DEVELOPMENT_CHECKLIST.md)** - Development tasks and status
- **[FAQ](./FAQ.md)** - Frequently asked questions
- **[TODO](./TODO.md)** - Pending tasks and future enhancements
- **[Changelog](./CHANGELOG.md)** - Version history and changes

## Project Overview

Debt Tracker is a cross-platform debt management application with:
- **Real-time synchronization** using WebSockets
- **Offline-first** architecture with local storage
- **Event-sourced** database for complete audit trail
- **Cross-platform** support (Web, iOS, Android, Linux Desktop)

## Architecture

### Backend
- **Language**: Rust
- **Framework**: Axum
- **Database**: PostgreSQL (event store + projections)
- **Event Store**: EventStore DB (for event sourcing)
- **Real-time**: WebSocket with broadcast channels

### Frontend
- **Framework**: Flutter (Dart)
- **State Management**: Riverpod
- **Offline Storage**: Hive (mobile/desktop)
- **Real-time**: WebSocket client

## Key Features

1. **Real-Time Updates**: Changes appear instantly across all connected clients
2. **Offline Support**: Works without internet, syncs when back online
3. **Event Sourcing**: Complete audit trail of all changes
4. **Cross-Platform**: Single codebase for web, mobile, and desktop

## Getting Started

See the main project README for setup instructions.

## Contributing

When adding new features, please document them in this folder following the existing format.
