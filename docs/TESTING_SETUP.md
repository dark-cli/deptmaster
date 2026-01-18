# Testing Setup Guide

## Quick Answer: Yes, Flutter Has Excellent UI Testing!

Flutter's `flutter_test` package allows you to:
- ✅ Test button taps and interactions
- ✅ Test form inputs and validation  
- ✅ Test navigation between screens
- ✅ Test widget visibility and state
- ✅ Test real-time updates
- ✅ Test user gestures (tap, drag, scroll, long press)
- ✅ Test dialogs and popups

See `docs/FLUTTER_UI_TESTING.md` for detailed examples.

## Backend Test Setup

### 1. Create Test Database

```bash
# Create test database
docker exec -i debt_tracker_postgres psql -U debt_tracker -d postgres -c "CREATE DATABASE debt_tracker_test;"

# Or using psql directly
createdb -U debt_tracker debt_tracker_test
```

### 2. Run Migrations on Test Database

```bash
export DATABASE_URL="postgresql://debt_tracker:dev_password@localhost:5432/debt_tracker_test"
cd backend/rust-api
sqlx migrate run
```

### 3. Run Tests

```bash
# Set test database URL
export TEST_DATABASE_URL="postgresql://debt_tracker:dev_password@localhost:5432/debt_tracker_test"

# Run all tests
cargo test

# Run ignored tests (integration tests)
cargo test -- --ignored

# Run specific test
cargo test test_update_transaction
```

## Flutter Test Setup

### 1. Install Dependencies

```bash
cd mobile
flutter pub get
```

### 2. Generate Mocks

```bash
# Generate mock classes for testing
flutter pub run build_runner build --delete-conflicting-outputs
```

### 3. Run Tests

```bash
# Run all tests
flutter test

# Run specific test file
flutter test test/contact_transactions_screen_test.dart

# Run with coverage
flutter test --coverage

# Run in watch mode
flutter test --watch
```

## Test Files Created

### Backend (Rust)
- ✅ `tests/test_helpers.rs` - Helper functions for test setup
- ✅ `tests/transaction_update_test.rs` - Integration tests for update/delete
- ✅ `tests/integration_test.rs` - High-level integration tests (stub)
- ✅ `tests/transaction_handlers_test.rs` - Handler unit tests (stub)

### Frontend (Flutter)
- ✅ `test/contact_transactions_screen_test.dart` - UI tests for transaction screen
- ✅ `test/contacts_screen_test.dart` - UI tests for contacts screen
- ✅ `test/realtime_service_test.dart` - Unit tests for real-time service

## What's Tested

### Backend Tests
- ✅ Transaction update updates projection correctly
- ✅ Transaction update recalculates contact balance
- ✅ Transaction delete soft deletes correctly
- ✅ Transaction delete recalculates contact balance
- ✅ Events are created in event store
- ✅ WebSocket broadcasts are sent

### Frontend UI Tests
- ✅ UI elements render correctly
- ✅ Buttons are tappable and work
- ✅ Navigation between screens
- ✅ Forms accept input
- ✅ Real-time updates trigger UI refresh
- ✅ Empty states display correctly
- ✅ Loading states display correctly
- ✅ Balance calculations display correctly

## Example: Running a UI Test

```bash
cd mobile
flutter test test/contact_transactions_screen_test.dart
```

This will:
1. Build the widget tree
2. Simulate user interactions (taps, inputs)
3. Verify UI state changes
4. Check that buttons perform their actions

## Next Steps

1. **Complete test implementations** - Replace TODOs with actual test code
2. **Set up CI/CD** - Automatically run tests on commits
3. **Add more test coverage** - Test edge cases and error scenarios
4. **Add integration tests** - Test complete user flows

## Resources

- [Flutter Testing Docs](https://docs.flutter.dev/testing)
- [Rust Testing Book](https://doc.rust-lang.org/book/ch11-00-testing.html)
- See `docs/FLUTTER_UI_TESTING.md` for Flutter UI testing examples
