# Testing Guide

This document describes the testing strategy for the Debt Tracker application.

## Overview

The application uses a combination of:
- **Backend Integration Tests** (Rust) - Test API endpoints, database operations, and WebSocket broadcasts
- **Frontend Widget Tests** (Flutter/Dart) - Test UI components and user interactions
- **Frontend Unit Tests** (Flutter/Dart) - Test business logic and services

## Backend Tests (Rust)

### Setup

Backend tests require a test database. Set up a separate PostgreSQL database for testing:

```bash
# Create test database
createdb debt_tracker_test

# Set environment variable
export DATABASE_URL="postgresql://debt_tracker:dev_password@localhost:5432/debt_tracker_test"
```

### Running Tests

```bash
cd backend/rust-api
cargo test
```

### Test Structure

Tests are located in `backend/rust-api/tests/`:

- `integration_test.rs` - High-level integration tests
- `transaction_handlers_test.rs` - Tests for transaction CRUD operations

### Key Test Cases

#### Transaction Update
- ✅ Updates transaction in projection
- ✅ Creates TRANSACTION_UPDATED event
- ✅ Broadcasts WebSocket message
- ✅ Recalculates contact balance

#### Transaction Delete
- ✅ Soft deletes transaction (sets is_deleted = true)
- ✅ Creates TRANSACTION_DELETED event
- ✅ Broadcasts WebSocket message
- ✅ Recalculates contact balance

#### Contact Balance Recalculation
- ✅ Balance updates when transaction is created
- ✅ Balance updates when transaction is updated
- ✅ Balance updates when transaction is deleted
- ✅ Balance calculation is correct (lent - owed)

## Frontend Tests (Flutter)

### Running Tests

```bash
cd mobile
flutter test
```

### Test Structure

Tests are located in `mobile/test/`:

- `realtime_service_test.dart` - Tests for WebSocket real-time updates
- `contact_transactions_screen_test.dart` - Tests for transaction list UI
- `contacts_screen_test.dart` - Tests for contacts list UI

### Key Test Cases

#### Real-time Service
- ✅ Handles transaction_created events
- ✅ Handles transaction_updated events
- ✅ Handles transaction_deleted events
- ✅ Notifies listeners on events
- ✅ Reconnects on disconnect

#### Contact Transactions Screen
- ✅ Displays transactions for contact
- ✅ Reloads on real-time update
- ✅ Updates balance when transaction changes
- ✅ Shows FAB for adding transactions
- ✅ Opens edit screen on tap
- ✅ Deletes transaction on confirmation

#### Contacts Screen
- ✅ Reloads contacts on transaction update
- ✅ Reloads contacts on transaction delete
- ✅ Displays correct total balance
- ✅ Updates total balance when transactions change

## Test Coverage Goals

- **Backend**: 80%+ coverage for handlers and business logic
- **Frontend**: 70%+ coverage for critical UI components and services

## Continuous Integration

Tests should run automatically on:
- Pull requests
- Commits to main branch
- Before deployment

## Writing New Tests

When adding new features:

1. **Backend**: Add integration tests for new endpoints
2. **Frontend**: Add widget tests for new screens/components
3. **Services**: Add unit tests for new business logic

### Example: Testing a New Feature

```rust
// backend/rust-api/tests/my_feature_test.rs
#[tokio::test]
async fn test_my_new_feature() {
    // Arrange: Set up test data
    let pool = setup_test_db().await;
    
    // Act: Call the feature
    // ...
    
    // Assert: Verify the result
    // ...
}
```

```dart
// mobile/test/my_feature_test.dart
testWidgets('my new feature works', (WidgetTester tester) async {
  // Arrange
  // ...
  
  // Act
  // ...
  
  // Assert
  // ...
});
```

## TODO: Test Infrastructure

The following test infrastructure needs to be set up:

- [ ] Test database setup script
- [ ] Test data fixtures
- [ ] Mock WebSocket server for frontend tests
- [ ] CI/CD pipeline for automated testing
- [ ] Code coverage reporting

## Current Status

✅ Test structure created
✅ Test documentation written
⏳ Test implementations need to be completed (see TODO comments in test files)
⏳ Test infrastructure setup needed
