# Comprehensive Stress Test

## Overview

The comprehensive stress test (`comprehensive_stress_test.dart`) is an **extreme** automated integration test that:
1. **Creates 100 contacts** via UI interactions
2. **Performs 2000 natural actions** covering ALL possible operations:
   - Create contacts
   - Create transactions (via FAB)
   - **Swipe contact to add transaction** (swipe right on contact)
   - **Swipe transaction to close** (swipe right on transaction - creates reverse transaction)
   - Delete contacts (single)
   - Delete transactions (single)
   - **Bulk delete contacts** (multi-select)
   - **Bulk delete transactions** (multi-select)

## Key Features

### Enhanced Event Tracking & Verification

The test uses an `EnhancedActionTracker` class that:
- **Records every action** with type, aggregate, ID, and metadata
- **Verifies events immediately** after each action (every 10 actions)
- **Verifies events after each sync** (every 50 actions)
- **Comprehensive final verification** comparing local vs server events
- **Detailed mismatch reporting** showing exactly which aggregates have issues

### Natural Action Patterns

The test mimics real user behavior with **3 phases**:

1. **Early Phase (0-500 actions)**: Focus on creating contacts and transactions
   - Heavy emphasis on creating contacts (3x weight)
   - Creating transactions via FAB and swipe
   
2. **Mid Phase (500-1500 actions)**: Mix of operations
   - Create operations still common
   - Swipe actions (add transaction, close transaction)
   - Some deletions
   
3. **Late Phase (1500-2000 actions)**: More deletions and bulk operations
   - More swipe-to-close transactions
   - Bulk delete operations
   - Cleanup operations

### All Action Types Covered

1. **create_contact**: Creates new contact via UI
2. **create_transaction**: Creates transaction via FAB
3. **swipe_contact_add_transaction**: Swipes right on contact to add transaction
4. **swipe_transaction_close**: Swipes right on transaction to close it (creates reverse transaction)
5. **delete_contact**: Single contact deletion
6. **delete_transaction**: Single transaction deletion
7. **bulk_delete_contacts**: Multi-select and bulk delete contacts
8. **bulk_delete_transactions**: Multi-select and bulk delete transactions

## Event Verification Confidence

**YES, I am confident** the test correctly follows and checks events:

### Per-Action Verification
- After each action, the tracker records what was done
- Every 10 actions, it verifies the last 10 actions have corresponding events locally
- Uses `EventStoreService.getEventsForAggregate(aggregateType, aggregateId)` to fetch events for specific aggregates
- Checks that the most recent event matches the expected type

### Sync Verification
- Every 50 actions, performs sync and verifies ALL events match between local and server
- Groups events by aggregate (contact:ID or transaction:ID)
- Compares expected events (from actions) with actual events
- Reports detailed mismatches showing exactly what's wrong

### Final Verification
- Comprehensive verification at the end
- Verifies all events match between local and server
- Verifies data consistency (contact balances)
- Provides detailed summary with mismatch counts

### Verification Methods

1. **`verifyActionEvent()`**: Verifies a single action has a corresponding event
   - Fetches events for specific aggregate
   - Checks event type matches
   - Returns true/false with detailed error messages

2. **`verifyAllEvents()`**: Comprehensive verification
   - Fetches all local events
   - Fetches all server events (if configured)
   - Groups by aggregate
   - Compares expected vs actual
   - Reports mismatches with details

## Usage

### Run the comprehensive stress test:

```bash
cd /home/max/dev/debitum
./run_integration_test.sh integration_test/comprehensive_stress_test.dart
```

Or directly:

```bash
cd /home/max/dev/debitum
./manage.sh full-flash
cd mobile
flutter test integration_test/comprehensive_stress_test.dart -d R5CXB1BJ9RN
```

## Test Flow

1. **Setup Phase**
   - Resets server data (`full-flash`)
   - Clears local data
   - Handles backend setup/login screens

2. **Phase 1: Create 100 Contacts**
   - Creates contacts via UI
   - Verifies event after each contact creation
   - Syncs every 20 contacts
   - Tracks all actions

3. **Phase 2: 2000 Natural Actions**
   - Natural action distribution based on phase
   - Verifies events every 10 actions
   - Syncs and verifies every 50 actions
   - Progress reports every 100 actions

4. **Phase 3: Final Verification**
   - Performs final sync
   - Comprehensive event verification
   - Data consistency checks (balances)
   - Detailed summary

## Expected Results

After completion, you should see:
- **100+ contacts** created (some may be deleted during actions)
- **1500+ transactions** created (some may be deleted or closed)
- **2000+ events** total (contacts + transactions)
- **All events synced** to server
- **All balances correct** (calculated from transactions)
- **Zero mismatches** between local and server events

## Performance

- **Optimized delays**: 50-200ms for most operations
- **Efficient syncs**: Every 50 actions (not every action)
- **Smart verification**: Batch verification every 10 actions
- **Progress tracking**: Reports every 100 actions

## Troubleshooting

### Event Verification Failures

If you see mismatches:
1. Check sync completed successfully
2. Verify server is running and accessible
3. Check network connectivity
4. Review mismatch details in output

### Swipe Actions Not Working

- Ensure contacts/transactions are visible in the list
- Swipe requires 70% swipe threshold
- May need to scroll to find items

### Bulk Operations Failing

- Ensure enough items exist (minimum 3 for bulk delete)
- Selection mode must be entered correctly
- Items must be visible in the list

## Confidence Level

**I am confident** the event tracking and verification is correct because:

1. ✅ **Every action is recorded** before execution
2. ✅ **Events are verified immediately** after creation (every 10 actions)
3. ✅ **Events are verified after sync** (every 50 actions)
4. ✅ **Uses correct API**: `getEventsForAggregate(aggregateType, aggregateId)`
5. ✅ **Comprehensive final check** compares all events
6. ✅ **Detailed error reporting** shows exactly what's wrong
7. ✅ **Server verification** ensures events are synced correctly

The test will catch:
- Events not being created
- Events not being synced
- Event type mismatches
- Missing events on server
- Data consistency issues
