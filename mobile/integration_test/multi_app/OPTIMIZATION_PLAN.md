# Optimization Plan

## Date: 2026-01-24

### Already Optimized ✅

1. ✅ **Moved ensureTestUserExists to setUpAll** - Saves ~1.2s per test
2. ✅ **Added login check before user creation** - Skips expensive Rust binary
3. ✅ **Skipped WebSocket during login** - Saves ~20-30s per test setup
4. ✅ **Fixed sync loop to run immediately** - Saves ~1s per sync (now 30-65ms)
5. ✅ **State rebuild is fast** - 0-3ms (already optimized)

### Potential Optimizations

#### High Impact (Easy to Implement)

### 1. Cache Hive Box References ⚠️ **RECOMMENDED**
**Current**: Opens boxes every time in `_rebuildState()` and `syncLocalToServer()`
**Impact**: Saves ~5-10ms per sync operation
**Complexity**: Low
**Files**: `mobile/lib/services/sync_service_v2.dart`

```dart
// Cache box references
static Box<Contact>? _contactsBox;
static Box<Transaction>? _transactionsBox;
static Box<Event>? _eventsBox;

// Use cached boxes or open if null
_contactsBox ??= await Hive.openBox<Contact>('contacts');
```

**Savings**: ~5-10ms per sync × multiple syncs = ~20-50ms per test

---

### 2. Use putAll for Batch Writes ⚠️ **RECOMMENDED**
**Current**: Individual `put()` calls in a loop
**Impact**: Saves ~1-2ms per state rebuild (negligible but cleaner)
**Complexity**: Low
**Files**: `mobile/lib/services/sync_service_v2.dart`

```dart
// Instead of:
for (final contact in state.contacts) {
  await contactsBox.put(contact.id, contact);
}

// Use:
final contactMap = <String, Contact>{};
for (final contact in state.contacts) {
  contactMap[contact.id] = contact;
}
await contactsBox.putAll(contactMap);
```

**Savings**: ~1-2ms per state rebuild (minimal but cleaner code)

---

### 3. Parallel App Initialization ⚠️ **RECOMMENDED**
**Current**: Sequential initialization (app1, then app2, then app3)
**Impact**: Saves ~50-100ms per test setup
**Complexity**: Low-Medium
**Files**: `mobile/integration_test/multi_app/scenarios/basic_sync_scenarios.dart`

```dart
// Instead of:
await app1!.initialize();
await app2!.initialize();
await app3!.initialize();

// Use:
await Future.wait([
  app1!.initialize(),
  app2!.initialize(),
  app3!.initialize(),
]);
```

**Savings**: ~50-100ms per test setup

---

#### Medium Impact

### 4. Reduce Sync Loop Polling Interval
**Current**: 1 second polling interval
**Impact**: Faster detection of sync completion (saves ~500ms in tests)
**Complexity**: Low
**Files**: `mobile/lib/services/sync_service_v2.dart`

```dart
// Change from:
Timer.periodic(const Duration(seconds: 1), ...)

// To:
Timer.periodic(const Duration(milliseconds: 500), ...)
// or even:
Timer.periodic(const Duration(milliseconds: 250), ...)
```

**Savings**: ~500ms per sync wait in tests (faster detection)
**Trade-off**: Slightly more CPU usage (negligible)

---

### 5. Enable API Endpoint for Server Reset ⚠️ **HIGHEST IMPACT**
**Current**: Using manage.sh fallback (5-10s per reset)
**Impact**: Saves 5-10s per test = 20-40s for 4 tests
**Complexity**: Requires server restart
**Action**: Restart server to enable `/api/dev/clear-database` endpoint

**Savings**: 20-40 seconds for 4 tests (HUGE!)

---

#### Low Impact

### 6. Reduce Number of Apps in Some Tests
**Current**: All tests use 3 apps
**Impact**: Saves ~0.7s per test (one less login)
**Complexity**: Low (but may reduce test coverage)
**Files**: Test files

**Savings**: ~0.7s per test × number of tests

---

### 7. Optimize Event Marking as Synced
**Current**: Individual `put()` calls for each event
**Impact**: Saves ~1-2ms per sync
**Complexity**: Low
**Files**: `mobile/lib/services/sync_service_v2.dart`

```dart
// Instead of:
for (final eventId in accepted) {
  final event = eventsBox.get(eventId);
  if (event != null) {
    final syncedEvent = Event(...);
    await eventsBox.put(eventId, syncedEvent);
  }
}

// Use:
final syncedEvents = <String, Event>{};
for (final eventId in accepted) {
  final event = eventsBox.get(eventId);
  if (event != null) {
    syncedEvents[eventId] = Event(...);
  }
}
await eventsBox.putAll(syncedEvents);
```

**Savings**: ~1-2ms per sync (minimal)

---

### Implementation Priority

1. **Cache Hive Box References** - Easy, saves ~20-50ms per test
2. **Use putAll for Batch Writes** - Easy, cleaner code
3. **Parallel App Initialization** - Easy, saves ~50-100ms per test
4. **Reduce Sync Loop Polling** - Easy, saves ~500ms per sync wait
5. **Enable API Endpoint** - Requires server restart, saves 20-40s (HUGE!)
6. **Optimize Event Marking** - Easy, minimal savings
7. **Reduce App Count** - Easy, but reduces coverage

### Expected Total Savings

**Current**: ~45 seconds for 4 basic sync tests

**After Optimizations 1-4**: ~44 seconds (saves ~1s)
**After Optimization 5 (API endpoint)**: ~5-10 seconds (saves 35-40s) ⚠️ **BIGGEST WIN**
**After All Optimizations**: ~4-9 seconds for 4 tests

### Recommendation

**Immediate Actions**:
1. Cache Hive box references (5 min)
2. Use putAll for batch writes (5 min)
3. Parallel app initialization (5 min)
4. Reduce sync loop polling to 500ms (2 min)

**High Impact Action**:
5. Restart server to enable API endpoint (saves 35-40s!)

**Total Time Investment**: ~20 minutes
**Total Savings**: ~35-40 seconds per test run (80-90% improvement!)
