# Vault Index

Quick links to project documentation and references.

## Setup & Operations

- [Database Setup](database-setup.md) — Docker management, connection strings, quick start
- [Reading Guide](reading-guide.md) — Where to start learning the codebase

## Architecture & Design

- [Architecture](architecture.md) — High-level system design, event sourcing, sync protocol
- [Sync Architecture Deep Dive](sync-handler-deep-dive.md) — Detailed sync API implementation
- [UNDO Event Client Optimization](undo_event-client-optimization.md) — Delete unsync'd events instead of undoing
- [Permission System](permission-system-deep-dive.md) — User groups, contact groups, permission matrix
- [Middleware Architecture](middleware-architecture.md) — Auth, wallet context, rate limiting

## Database

- [Migration Guide](migration-guide.md) — All 21 migrations organized by phase
- [Migration Guidelines](migration-guidelines.md) — Standards for creating new migrations

## Implementation Plans

- [Sync Refactoring Plan](sync-refactoring-plan.md) — Phase 1-3 plan for modularizing sync.rs

## Status & Tracking

- [Todos (Backend)](todos.md) — Backend development tasks and known issues
- [Todos (Client)](client-todos.md) — Flutter/Dart mobile development tasks
- [Current State](current-state.md) — Latest codebase snapshot
- [Merged Features](merged-features.md) — Feature branches integrated into main

