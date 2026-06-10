# Backend Tests

## Setup

1. Create a test database:
```bash
docker exec -i debt_tracker_postgres psql -U debt_tracker -d postgres -c "CREATE DATABASE debt_tracker_test;"
```

2. Run migrations on test database:
```bash
export DATABASE_URL="postgresql://debt_tracker:dev_password@localhost:5432/debt_tracker_test"
cd backend/rust-api
sqlx migrate run
```

3. Run tests:
```bash
cargo test
```

## Test Files

- `integration_test.rs` - High-level integration tests for API endpoints
- `transaction_handlers_test.rs` - Unit tests for transaction handler functions

## Writing Tests

Each test should:
1. Set up test data (contacts, transactions)
2. Execute the operation being tested
3. Verify the result (database state, events, WebSocket broadcasts)

Example:
```rust
#[tokio::test]
async fn test_update_transaction() {
    // 1. Create test contact and transaction
    // 2. Call update_transaction handler
    // 3. Verify:
    //    - Transaction projection updated
    //    - Event created
    //    - WebSocket message sent
    //    - Contact balance recalculated
}
```

## Note

The current test files contain TODO placeholders. They need to be implemented with:
- Test database connection setup
- Helper functions for creating test data
- Actual test implementations
- Assertions
