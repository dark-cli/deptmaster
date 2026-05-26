# Conventions

## Event Naming

Events are named in SCREAMING_SNAKE_CASE with aggregate type prefix:
- `CONTACT_CREATED`, `CONTACT_UPDATED`, `CONTACT_DELETED`
- `TRANSACTION_CREATED`, `TRANSACTION_UPDATED`, `TRANSACTION_DELETED`
- `UNDO` (special event type for undoing previous events)

## Event Structure (Backend)

```rust
{
  "id": "uuid",
  "aggregate_type": "contact" | "transaction",
  "aggregate_id": "uuid",
  "event_type": "CREATED" | "UPDATED" | "DELETED",
  "event_data": { /* JSONB payload */ },
  "timestamp": "ISO8601",
  "version": u32
}
```

## Backend (Rust)

- **Module organization**: handlers/, services/, models/, middleware/, database/, background/, utils/
- **Handler pattern**: Each aggregate (contacts, transactions) has its own handler file
- **Service layer**: Projection snapshots, seed data, core business logic
- **Middleware**: Auth, rate limit, security headers
- **Naming**: snake_case for functions/variables, PascalCase for structs/enums

## Mobile (Dart)

- **Service organization**: Services for local DB, sync, realtime, API, auth
- **Screen-based**: Each feature has a screen and optional edit screen
- **V2 pattern**: Newer services use V2 (SyncServiceV2, LocalDatabaseServiceV2)
- **Naming**: camelCase for functions/variables, PascalCase for classes

## Database Naming

- **Tables**: snake_case (events, contacts_projection, transactions_projection)
- **Columns**: snake_case (aggregate_id, event_type, is_deleted, created_at)
- **Indexes**: Indexed by user, aggregate type, timestamp for fast queries

## Service Patterns

### Backend Services
- **Initialization**: Usually in main.rs with PostgreSQL connection pool
- **State Sharing**: AppState contains DB pool + broadcast sender
- **Error Handling**: Result<T, StatusCode> pattern with HTTP status codes

### Mobile Services
- **Singleton Pattern**: Services instantiated once and reused
- **Event-Driven**: Services communicate via events (SyncServiceV2 listens to RealtimeService)
- **Local-First**: All reads/writes hit local Hive first, then sync

## Testing

- Integration tests in `tests/` directory
- Test helpers for database setup (test_helpers.rs)
- Unit tests for specific handlers (transaction_handlers_test.rs)

## Projection Pattern

Projections are **actively maintained**, not rebuilt from events:
- On CREATE: INSERT into projection table
- On UPDATE: UPDATE projection table directly
- On DELETE: Set is_deleted = true (soft delete)

Snapshots used only for optimization during rebuilds.

## Related Notes
- [[auth.md]] - JWT authentication and middleware
- [[architecture.md]] - System architecture
- [[decisions.md]] - Why these patterns were chosen
