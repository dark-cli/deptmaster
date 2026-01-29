# Development Guide

This guide covers development setup, testing, admin panel usage, and database management.

## Quick Start

```bash
# Start services
./manage.sh start-services

# Start server
./manage.sh start-server

# Run mobile app
./manage.sh run-app android

# Run tests
./manage.sh test-app
```

## Backend Development (Rust)

### Project Structure

```
backend/rust-api/
├── src/
│   ├── main.rs                 # Entry point
│   ├── config.rs               # Configuration
│   ├── handlers/               # API route handlers
│   ├── models/                 # Data models
│   ├── services/               # Business logic
│   └── database/              # Database layer
├── migrations/                # SQL migrations
└── tests/                     # Integration tests
```

### Running the Server

```bash
# Build
./manage.sh build

# Start server
./manage.sh start-server

# View logs
./manage.sh logs

# Check status
./manage.sh status
```

### Environment Variables

```bash
DATABASE_URL=postgresql://debt_tracker:dev_password@localhost:5432/debt_tracker
PORT=8000
RUST_LOG=info
EVENTSTORE_URL=http://localhost:2113
EVENTSTORE_USERNAME=admin
EVENTSTORE_PASSWORD=changeit
```

## Frontend Development (Flutter)

### Setup

```bash
cd mobile

# Install dependencies
flutter pub get

# Generate Hive adapters
flutter pub run build_runner build --delete-conflicting-outputs
```

### Running the App

```bash
# Android
./scripts/manage.sh run-flutter-app android

# Web
./scripts/manage.sh run-flutter-web dev

# Linux Desktop
./scripts/manage.sh run-flutter-app linux
```

#### Reducing Verbose Android Logs

When running on Android, you may see many verbose Android system logs (VRI, InsetsController, BLASTBufferQueue, etc.). These are normal but can clutter the console.

**To filter logs:**
1. Run Flutter normally: `./scripts/manage.sh run-flutter-app android`
2. In a **separate terminal**, show filtered logs:
   ```bash
   ./scripts/manage.sh show-android-logs
   ```

This shows only Flutter/Dart logs without interfering with Flutter's interactive commands (r for reload, R for restart, etc.).

**See `mobile/REDUCE_LOGS.md` for more options.**

### Project Structure

```
mobile/
├── lib/
│   ├── main.dart              # Entry point
│   ├── screens/               # UI screens
│   ├── services/              # Business logic
│   ├── models/                # Data models
│   ├── widgets/               # Reusable widgets
│   └── utils/                 # Utilities
└── test/                      # Tests
```

## Testing

### Backend Tests (Rust)

#### Setup

```bash
# Create test database
docker exec -i debt_tracker_postgres psql -U debt_tracker -d postgres -c "CREATE DATABASE debt_tracker_test;"

# Run migrations
export DATABASE_URL="postgresql://debt_tracker:dev_password@localhost:5432/debt_tracker_test"
cd backend/rust-api
sqlx migrate run
```

#### Running Tests

```bash
export TEST_DATABASE_URL="postgresql://debt_tracker:dev_password@localhost:5432/debt_tracker_test"
cargo test

# Run specific test
cargo test test_update_transaction
```

### Frontend Tests (Flutter)

#### Setup

```bash
cd mobile
flutter pub get
flutter pub run build_runner build --delete-conflicting-outputs
```

#### Running Tests

```bash
# All tests
flutter test

# Specific test file
flutter test test/contact_transactions_screen_test.dart

# With coverage
flutter test --coverage
```

#### UI Testing

Flutter provides comprehensive UI/widget testing:

```dart
testWidgets('button tap works', (WidgetTester tester) async {
  await tester.pumpWidget(MyButton());
  await tester.tap(find.byType(ElevatedButton));
  await tester.pump();
  expect(find.text('Clicked!'), findsOneWidget);
});
```

**Common patterns**:
- `find.byType(Widget)` - Find widget by type
- `find.text('Hello')` - Find by text
- `tester.tap()` - Simulate tap
- `tester.enterText()` - Enter text
- `tester.pumpAndSettle()` - Wait for animations

## Admin Panel

### Accessing

1. **Start server**:
   ```bash
   ./manage.sh start-server
   ```

2. **Open browser**:
   ```
   http://localhost:8000/admin
   ```

### Features

- **Events View**: View all events, filter by type/date
- **Contacts View**: View all contacts from projection
- **Transactions View**: View all transactions
- **Statistics**: View debt chart and totals
- **Projection Status**: Check projection health

### Troubleshooting

**Server not responding**:
```bash
# Check if running
./manage.sh status

# Check logs
./manage.sh logs

# Restart
./manage.sh restart-server
```

**Port already in use**:
```bash
lsof -ti:8000 | xargs kill -9
./manage.sh start-server
```

## Database Management

### Reset Database

```bash
# Reset everything
./manage.sh reset

# Reset and import backup
./manage.sh reset backup.zip

# Full flash (reset + rebuild)
./manage.sh full-flash backup.zip
```

### Import Data

```bash
# Import from Debitum backup
./manage.sh import backup.zip
```

### Migrations

Migrations are in `backend/rust-api/migrations/`:

```bash
# Run migrations manually
cd backend/rust-api
sqlx migrate run --database-url "postgresql://..."
```

### Reset EventStore

```bash
./manage.sh reset-eventstore
```

## Migration from Debitum

### Using Import Script

```bash
# Import from Debitum backup ZIP
./manage.sh import debitum-backup-*.zip
```

The script will:
1. Extract the backup ZIP
2. Find SQLite database
3. Migrate contacts and transactions
4. Create events in EventStore
5. Rebuild projections

### Manual Migration

See `scripts/migrate_debitum_via_api_fast.py` for the migration script.

## Common Tasks

### Check System Requirements

```bash
./manage.sh check
```

### Install Dependencies

```bash
./manage.sh install-deps
```

### View Server Status

```bash
./manage.sh status
```

### View Logs

```bash
./manage.sh logs
```

## Related Documentation

- [Architecture](./ARCHITECTURE.md) - System architecture
- [API Reference](./API.md) - API endpoints
- [Deployment Guide](./DEPLOYMENT.md) - Production deployment
