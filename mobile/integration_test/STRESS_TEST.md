# Automated Stress Test

## Overview

The stress test (`stress_test.dart`) is an automated integration test that:
1. **Creates 20 contacts** via UI interactions
2. **Performs 500 random actions** covering all CRUD operations:
   - Create contacts
   - Update contacts (placeholder - needs UI implementation)
   - Delete contacts
   - Create transactions
   - Update transactions (placeholder - needs UI implementation)
   - Delete transactions

## Features

### Smart Event Tracking

The test uses an `ActionTracker` class that:
- Records every action performed (type, aggregate type, aggregate ID, data)
- Groups actions by aggregate (contact/transaction)
- Verifies events match between local and server
- Provides detailed verification reports

### Event Verification

The test automatically verifies:
- **Local events**: All actions have corresponding events in local EventStore
- **Server events**: All actions have corresponding events on the server
- **Event counts**: Expected number of events per aggregate
- **Data consistency**: Contact balances match calculated transaction totals

### Sync Management

- Syncs every 10 contacts during creation phase (optimized for speed)
- Syncs every 25 actions during random action phase (optimized for speed)
- Performs final sync and verification at the end

### Performance Optimizations

- Reduced UI delays (100-200ms instead of 300-500ms)
- Faster page navigation (100ms instead of 500ms)
- Less frequent syncs (every 25 actions instead of 10)
- Minimal delays after form submissions

## Usage

### Run the stress test:

```bash
cd /home/max/dev/debitum
./run_integration_test.sh integration_test/stress_test.dart
```

Or directly:

```bash
cd /home/max/dev/debitum
./manage.sh full-flash
cd mobile
flutter test integration_test/stress_test.dart -d R5CXB1BJ9RN
```

## Test Flow

1. **Setup Phase**
   - Resets server data (`full-flash`)
   - Clears local data
   - Handles backend setup/login screens

2. **Phase 1: Create 20 Contacts**
   - Creates contacts via UI
   - Syncs every 5 contacts
   - Tracks all actions

3. **Phase 2: 500 Random Actions**
   - Randomly selects action type based on current state
   - Weighted towards create operations (3x weight)
   - Ensures minimum 5 contacts remain
   - Syncs every 25 actions (optimized for speed)
   - Verifies progress every 50 actions

4. **Phase 3: Final Verification**
   - Performs final sync
   - Verifies all events match between local and server
   - Verifies data consistency (balances)
   - Prints comprehensive summary

## Action Selection Logic

The test intelligently selects actions based on:
- **Current state**: Number of contacts/transactions available
- **Constraints**: Maintains minimum 5 contacts
- **Weighting**: Create operations are 3x more likely than update/delete

### Action Types:

1. **create_contact**: Creates a new contact (if < 30 total)
2. **update_contact**: Updates existing contact (if contacts exist)
3. **delete_contact**: Deletes contact (if > 5 contacts)
4. **create_transaction**: Creates transaction (if contacts exist)
5. **update_transaction**: Updates transaction (if transactions exist)
6. **delete_transaction**: Deletes transaction (if transactions exist)

## Event Verification

The `ActionTracker.verifyEvents()` method:

1. Fetches all local events from EventStore
2. Fetches all server events via API
3. Groups events by aggregate (contact:ID or transaction:ID)
4. Compares expected events (from actions) with actual events
5. Reports mismatches and verification status

### Verification Output:

```
🔍 Verifying events...
📊 Local events: 140
📊 Server events: 140
✅ Verified: 35 aggregates, ❌ Mismatches: 0
```

## Expected Results

After completion, you should see:
- **20+ contacts** created (some may be deleted during random actions)
- **400+ transactions** created (some may be deleted)
- **500+ events** total (contacts + transactions)
- **All events synced** to server
- **All balances correct** (calculated from transactions)

## Troubleshooting

### Test fails with "Expected X events, found Y"

- Check if sync completed successfully
- Verify server is running and accessible
- Check for network issues

### Transactions not appearing

- Ensure transactions screen has local listeners (already fixed)
- Check sync status in logs
- Verify events are being created locally

### Contacts being deleted too quickly

- The test maintains minimum 5 contacts
- Adjust `createdContacts.length > 5` threshold if needed

## Future Enhancements

- [ ] Implement contact update UI interaction
- [ ] Implement transaction update UI interaction
- [ ] Add more action types (bulk operations, etc.)
- [ ] Add performance metrics (time per action, sync duration)
- [ ] Add concurrent action support
- [ ] Add offline/online scenario testing
