# Debt Tracker Documentation

This folder contains all documentation for the Debt Tracker application.

## Documentation Index

### Core Documentation

- **[Architecture](./ARCHITECTURE.md)** - System architecture and design overview
- **[API Reference](./API_REFERENCE.md)** - Complete API endpoint documentation
- **[Deployment Guide](./DEPLOYMENT.md)** - Production deployment instructions

### Feature Documentation

- **[Real-Time Sync Implementation](./REALTIME_SYNC_IMPLEMENTATION.md)** - Complete technical documentation of real-time updates and offline sync
- **[Implementation Summary](./IMPLEMENTATION_SUMMARY.md)** - Quick summary of real-time sync implementation

### Project Planning

- **[Project Plan](./PROJECT_PLAN.md)** - Initial project planning and requirements
- **[Additional Considerations](./ADDITIONAL_CONSIDERATIONS.md)** - Non-functional requirements
- **[Debitum Strengths](./DEBITUM_STRENGTHS.md)** - Analysis of original Debitum app features

### Development

- **[Development Checklist](./DEVELOPMENT_CHECKLIST.md)** - Development tasks and status
- **[Migration Guide](./MIGRATION.md)** - Data migration documentation
- **[FAQ](./FAQ.md)** - Frequently asked questions
- **[TODO](./TODO.md)** - Pending tasks and future enhancements
- **[Changelog](./CHANGELOG.md)** - Version history and changes

### Quick Reference

- **[Real-Time Ready](./REALTIME_READY.md)** - Quick overview of real-time features
- **[Real-Time Complete](./REALTIME_COMPLETE.md)** - Summary of real-time implementation
- **[Real-Time Sync Implemented](./REALTIME_SYNC_IMPLEMENTED.md)** - Initial implementation notes

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
