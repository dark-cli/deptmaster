# Multi-App Sync Testing Framework

## Overview

This test framework simulates multiple app instances programmatically to test event synchronization, storage, and conflict resolution across multiple devices syncing to the same server. All tests use the **real server** (not mocks) and provide comprehensive coverage of sync scenarios.

### Key Features

- **Real Server Testing**: All tests use the actual running server at `http://localhost:8000`
- **Multi-Instance Simulation**: Simulates multiple app instances with isolated state
- **Network Simulation**: Simulates offline/online states and connection failures
- **Comprehensive Validation**: Validates event consistency, ordering, and data integrity
- **Performance Monitoring**: Tracks sync times, retry counts, and throughput
- **Server Verification**: Verifies server-side state via API

## How to Run Tests

### Prerequisites

1. **Server Running**: The backend server must be running at `http://localhost:8000`
2. **Database**: PostgreSQL must be running (via Docker)
3. **Flutter**: Flutter SDK installed and configured
4. **Dependencies**: All Flutter dependencies installed

### Step-by-Step Guide

#### 1. Start the Server

```bash
cd /home/max/dev/debitum
./scripts/manage.sh start-server-direct
```

Verify server is running:
```bash
curl http://localhost:8000/health
```

#### 2. Navigate to Mobile Directory

```bash
cd /home/max/dev/debitum/mobile
```

#### 3. Run Tests

**Run All Test Scenarios:**
```bash
flutter test integration_test/multi_app/scenarios/ -d linux
```

**Run Specific Test Suite:**
```bash
# Basic sync scenarios
flutter test integration_test/multi_app/scenarios/basic_sync_scenarios.dart -d linux

# Offline/online scenarios
flutter test integration_test/multi_app/scenarios/offline_online_scenarios.dart -d linux

# Conflict scenarios
flutter test integration_test/multi_app/scenarios/conflict_scenarios.dart -d linux

# Connection breakdown scenarios
flutter test integration_test/multi_app/scenarios/connection_scenarios.dart -d linux

# Resync scenarios
flutter test integration_test/multi_app/scenarios/resync_scenarios.dart -d linux

# Stress scenarios
flutter test integration_test/multi_app/scenarios/stress_scenarios.dart -d linux

# Server-side scenarios
flutter test integration_test/multi_app/scenarios/server_side_scenarios.dart -d linux
```

**Run Specific Test:**
```bash
flutter test integration_test/multi_app/scenarios/basic_sync_scenarios.dart -d linux --name "1.1 Single App Create"
```

**Run with Verbose Output:**
```bash
flutter test integration_test/multi_app/scenarios/ -d linux --verbose
```

**Run with Coverage:**
```bash
flutter test integration_test/multi_app/scenarios/ -d linux --coverage
```

### What Happens During Tests

Each test automatically:
1. **Resets Server**: Calls `manage.sh reset-database-complete` to reset the database
2. **Creates Test User**: Ensures the test user (`max` / `12345678`) exists
3. **Clears Local Data**: Clears all Hive boxes
4. **Creates App Instances**: Creates multiple simulated app instances
5. **Initializes Instances**: Initializes and logs in all instances
6. **Runs Test Scenario**: Executes the test scenario
7. **Validates Results**: Verifies event consistency, sync status, etc.
8. **Cleans Up**: Disconnects and cleans up all instances

### Expected Test Duration

- **Basic Sync Scenarios**: ~2-3 minutes
- **Offline/Online Scenarios**: ~3-4 minutes
- **Conflict Scenarios**: ~3-4 minutes
- **Connection Scenarios**: ~4-5 minutes
- **Resync Scenarios**: ~4-5 minutes
- **Stress Scenarios**: ~5-10 minutes
- **Server-Side Scenarios**: ~2-3 minutes

**Total**: ~25-35 minutes for all tests

## Test Content

### 1. Basic Sync Scenarios (`basic_sync_scenarios.dart`)

Tests fundamental synchronization behavior when all apps are online.

- **1.1 Single App Create → Multi-App Sync**: Verifies events created in one app propagate to all other apps
- **1.2 Concurrent Creates**: Tests simultaneous event creation across multiple apps
- **1.3 Update Propagation**: Tests update event propagation and conflict resolution
- **1.4 Delete Propagation**: Tests delete event propagation across all apps

### 2. Offline/Online Scenarios (`offline_online_scenarios.dart`)

Tests synchronization behavior when apps go offline and come back online.

- **2.1 Offline Create → Online Sync**: Verifies offline events sync when app comes online
- **2.2 Multiple Offline Creates**: Tests multiple apps creating events offline
- **2.3 Offline Update → Online Sync**: Tests offline updates sync correctly
- **2.4 Partial Offline**: Tests behavior when some apps are offline while others are online

### 3. Conflict Scenarios (`conflict_scenarios.dart`)

Tests conflict detection and resolution.

- **3.1 Simultaneous Updates**: Tests conflict resolution for simultaneous updates
- **3.2 Update-Delete Conflict**: Tests update-delete conflict resolution (delete wins)
- **3.3 Offline Update Conflict**: Tests offline update conflicts when app comes online

### 4. Connection Breakdown Scenarios (`connection_scenarios.dart`)

Tests retry logic and recovery from connection failures.

- **4.1 Sync Interruption**: Tests sync retry after connection interruption
- **4.2 Multiple Sync Failures**: Tests retry logic with multiple connection failures
- **4.3 Server Unavailable**: Tests behavior when server is unavailable and comes back

### 5. Resync Scenarios (`resync_scenarios.dart`)

Tests full and incremental resync after disconnection.

- **5.1 Full Resync After Disconnect**: Tests full resync after extended disconnect
- **5.2 Hash Mismatch Resync**: Tests hash mismatch detection and full resync
- **5.3 Incremental Resync**: Tests incremental resync with timestamp-based fetching

### 6. Stress Scenarios (`stress_scenarios.dart`)

Tests system behavior under high load.

- **6.1 High Volume Concurrent Operations**: 5 apps each create 20 contacts simultaneously (100 total)
- **6.2 Rapid Create-Update-Delete**: Tests rapid sequence of operations on same aggregate
- **6.3 Mixed Operations Stress**: Tests mixed create/update/delete operations across all apps

### 7. Server-Side Scenarios (`server_side_scenarios.dart`)

Tests server-side functionality via API.

- **Server 1: Event Storage**: Verifies events stored correctly in database
- **Server 2: Event Retrieval**: Tests event retrieval with/without timestamp
- **Server 3: Event Acceptance**: Tests event acceptance and validation
- **Server 4: Hash Calculation**: Tests sync hash calculation and changes
- **Server 5: Projection Consistency**: Verifies projections match events
- **Server 6: Event Count and Statistics**: Tests event counting and statistics

## Architecture

### Components

1. **AppInstance** - Simulated app with isolated state (shared Hive boxes, isolated auth/config)
2. **SyncMonitor** - Tracks sync state across all instances
3. **EventValidator** - Validates event consistency, ordering, and data integrity
4. **ServerVerifier** - Verifies server-side state via API
5. **NetworkInterceptor** - Simulates network failures for offline testing
6. **RealtimeServiceTestHelper** - Controls WebSocket reconnection behavior
7. **PerformanceMonitor** - Tracks performance metrics (sync times, retry counts, throughput)

### Test Structure

```
mobile/integration_test/multi_app/
├── app_instance.dart              # Simulated app instance
├── sync_monitor.dart              # Sync state monitoring
├── event_validator.dart           # Event validation
├── server_verifier.dart           # Server verification
├── network_interceptor.dart       # Network failure simulation
├── realtime_service_test_helper.dart  # WebSocket control
├── performance_monitor.dart       # Performance monitoring
├── README.md                      # This file
└── scenarios/
    ├── basic_sync_scenarios.dart   # Basic sync tests
    ├── offline_online_scenarios.dart  # Offline/online tests
    ├── conflict_scenarios.dart    # Conflict resolution tests
    ├── connection_scenarios.dart # Connection breakdown tests
    ├── resync_scenarios.dart     # Resync tests
    ├── stress_scenarios.dart      # Stress tests
    └── server_side_scenarios.dart # Server-side tests
```

## Monitoring and Reporting

### PerformanceMonitor
- Tracks sync times, operation times, retry counts
- Generates performance reports with statistics
- Per-instance and overall metrics

### SyncMonitor
- Real-time sync status tracking
- Event count monitoring
- Consistency validation
- Conflict detection

### EventValidator
- Event consistency validation
- Event ordering validation
- Duplicate detection
- Data integrity checks
- Comprehensive validation reports

## Troubleshooting

### Server Not Running
**Error**: `Connection refused` or `Server not ready`

**Solution**:
```bash
cd /home/max/dev/debitum
./scripts/manage.sh start-server-direct
curl http://localhost:8000/health
```

### Test User Not Found
**Error**: `Login failed: Invalid username or password`

**Solution**: The test automatically creates the user, but if it fails:
```bash
cd /home/max/dev/debitum/backend/rust-api
cargo run --bin reset_password -- max 12345678
```

### Sync Timeout
**Error**: `Sync timeout - not all instances synced`

**Solution**:
- Check server logs for errors
- Verify network connectivity
- Increase timeout in test if needed
- Check if server is under heavy load

### Hive Box Locked
**Error**: `HiveError: Box is already open`

**Solution**: Tests handle this automatically. If persistent:
- Restart test runner
- Close any running Flutter apps

## Quick Reference

```bash
# Start server
cd /home/max/dev/debitum
./scripts/manage.sh start-server-direct

# Run all tests
cd mobile
flutter test integration_test/multi_app/scenarios/ -d linux

# Run specific suite
flutter test integration_test/multi_app/scenarios/basic_sync_scenarios.dart -d linux

# Run with verbose output
flutter test integration_test/multi_app/scenarios/ -d linux --verbose
```

## Notes

- All instances share the same Hive boxes (realistic - they sync to same server)
- Auth state is shared (all instances use same user - fine for sync testing)
- Network interceptor integrated for offline simulation
- WebSocket reconnection control integrated for offline simulation
- All tests use real server (not mocks)
- Server is reset before each test using `manage.sh reset-database-complete`
- Tests can be run on other platforms (Android, iOS) but Linux is recommended for development
