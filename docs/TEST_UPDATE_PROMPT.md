# Test Update Prompt for Multi-Wallet System

## Context

The backend has been updated to support a multi-wallet system. Each wallet is an isolated container with its own event log, transactions, and contacts. Users can subscribe to multiple wallets and switch between them.

## Backend Changes Summary

### Database Changes
- New tables: `wallets`, `wallet_users`
- Added `wallet_id` column to: `events`, `contacts_projection`, `transactions_projection`, `projection_snapshots`, `client_sync_state`
- All queries now filter by `wallet_id` for data isolation

### API Changes
- **New endpoints:**
  - `GET /api/wallets` - List wallets user has access to
  - `GET /api/wallets/:id` - Get wallet details
  - `POST /api/admin/wallets` - Create wallet (admin)
  - `PUT /api/admin/wallets/:id` - Update wallet (admin)
  - `DELETE /api/admin/wallets/:id` - Delete wallet (admin)
  - `POST /api/admin/wallets/:id/users` - Add user to wallet (admin)
  - `PUT /api/admin/wallets/:id/users/:user_id` - Update user role in wallet (admin)
  - `DELETE /api/admin/wallets/:id/users/:user_id` - Remove user from wallet (admin)

- **Updated endpoints (now require wallet_id):**
  - All `/api/contacts/*` endpoints
  - All `/api/transactions/*` endpoints
  - All `/api/sync/*` endpoints

### Middleware Changes
- New `wallet_context_middleware` extracts `wallet_id` from:
  - Query parameter: `?wallet_id=...`
  - Header: `X-Wallet-Id: ...`
  - Path parameter (if route has `:wallet_id`)

### Request Requirements
All wallet-scoped endpoints now require `wallet_id` to be provided. The middleware validates:
1. Wallet exists and is active
2. User has access to the wallet
3. Returns appropriate error codes if validation fails

## Test Update Requirements

### 1. Update Existing Integration Tests

**Files to update:**
- `backend/rust-api/tests/integration_test.rs`
- `backend/rust-api/tests/transaction_handlers_test.rs`
- `backend/rust-api/tests/transaction_update_test.rs`
- `backend/rust-api/tests/undo_event_test.rs`
- Any other test files that test contacts, transactions, or sync endpoints

**Changes needed:**
1. **Create test wallets** before running tests
2. **Add users to wallets** with appropriate roles
3. **Include `wallet_id` in all requests** (query param or header)
4. **Update assertions** to account for wallet-scoped data
5. **Test wallet isolation** - verify data from one wallet doesn't leak to another

### 2. Test Wallet Management

**New test cases needed:**
- Create wallet
- List user wallets
- Get wallet details
- Update wallet (admin)
- Delete wallet (admin)
- Add user to wallet (admin)
- Remove user from wallet (admin)
- Update user role in wallet (admin)
- Test wallet access control (user can't access wallet they're not in)

### 3. Test Wallet Isolation

**Critical test cases:**
- Create contact in wallet A, verify it doesn't appear in wallet B
- Create transaction in wallet A, verify it doesn't appear in wallet B
- Sync events for wallet A, verify wallet B events are not included
- Test that users can only access wallets they're subscribed to
- Test that wallet-scoped queries return correct data

### 4. Test Parallel Execution (Key Requirement)

**Important:** The multi-wallet system enables parallel test execution. Each test should:
- Create its own unique wallet(s)
- Use unique user(s) for each test
- Not interfere with other tests running concurrently

**Test structure:**
```rust
#[tokio::test]
async fn test_contact_creation() {
    // Create unique wallet for this test
    let wallet = create_test_wallet("test-wallet-1").await;
    let user = create_test_user("user-1").await;
    add_user_to_wallet(&user, &wallet, "owner").await;
    
    // Use wallet_id in requests
    let response = create_contact(&wallet.id, &user.token).await;
    // ... assertions
}
```

### 5. Update Test Helpers

**Helper functions needed:**
- `create_test_wallet(name: &str) -> Wallet`
- `create_test_user(username: &str) -> User`
- `add_user_to_wallet(user_id: &Uuid, wallet_id: &Uuid, role: &str)`
- `get_wallet_context_header(wallet_id: &Uuid) -> HeaderMap`
- `get_wallet_query_param(wallet_id: &Uuid) -> String`

### 6. Migration Test Updates

**Update migration tests:**
- Test that existing data is migrated to default wallet
- Test that new data requires explicit wallet_id
- Test that wallet_id cannot be NULL after migration

### 7. Sync Test Updates

**Update sync-related tests:**
- Test that `get_sync_hash` returns wallet-specific hash
- Test that `get_sync_events` only returns events for specified wallet
- Test that `post_sync_events` validates wallet_id in event data
- Test that sync state is wallet-scoped

### 8. Projection Rebuild Test Updates

**Update projection tests:**
- Test that `rebuild_projections_from_events` is wallet-scoped
- Test that snapshots are wallet-scoped
- Test that projection rebuilds don't affect other wallets

## Example Test Update Pattern

### Before:
```rust
#[tokio::test]
async fn test_create_contact() {
    let response = client
        .post("/api/contacts")
        .json(&contact_data)
        .send()
        .await;
    // ... assertions
}
```

### After:
```rust
#[tokio::test]
async fn test_create_contact() {
    // Setup: Create wallet and user
    let wallet = create_test_wallet("test-wallet").await;
    let user = create_test_user("test-user").await;
    add_user_to_wallet(&user.id, &wallet.id, "owner").await;
    
    // Test: Include wallet_id in request
    let response = client
        .post(&format!("/api/contacts?wallet_id={}", wallet.id))
        .header("Authorization", format!("Bearer {}", user.token))
        .json(&contact_data)
        .send()
        .await;
    // ... assertions
}
```

## Key Testing Principles

1. **Isolation:** Each test should use unique wallets/users to avoid conflicts
2. **Parallel Safety:** Tests should be able to run concurrently without data conflicts
3. **Wallet Scoping:** Verify all data operations are properly scoped to wallets
4. **Access Control:** Test that users can only access wallets they're subscribed to
5. **Error Handling:** Test appropriate error responses for invalid wallet_id, missing access, etc.

## Priority Order

1. **High Priority:**
   - Update existing integration tests to include wallet_id
   - Test wallet isolation (data doesn't leak between wallets)
   - Test wallet access control

2. **Medium Priority:**
   - Test wallet management endpoints
   - Test parallel execution capability
   - Update sync-related tests

3. **Low Priority:**
   - Test edge cases (empty wallets, deleted wallets, etc.)
   - Performance tests with multiple wallets
   - Stress tests with many concurrent wallets

## Notes

- The migration script creates a "Default Wallet" and migrates existing data to it
- For tests, it's better to create fresh wallets rather than relying on default wallet
- Use unique identifiers (UUIDs, timestamps) in test wallet/user names to avoid conflicts
- Consider using test fixtures or factories for common test setup patterns

## Questions to Consider

1. Should tests clean up created wallets/users after completion?
2. How should we handle test database state between test runs?
3. Should we have a test helper that automatically creates wallet context for requests?
4. How do we test the migration from single-wallet to multi-wallet system?
