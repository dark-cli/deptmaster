# Parallel Testing Guide

This guide explains how to run tests in parallel for both backend (Rust) and frontend (Flutter) tests, leveraging the multi-wallet system for true parallel execution.

## Backend Tests (Rust/Cargo)

### Default Behavior

By default, `cargo test` runs tests **in parallel** using multiple threads (one per CPU core).

### Run All Tests in Parallel

```bash
cd backend/rust-api
cargo test --lib --tests --no-fail-fast
```

**Options:**
- `--lib` - Run library tests
- `--tests` - Run integration tests
- `--no-fail-fast` - Continue running all tests even if one fails
- `--ignored` - Include tests marked with `#[ignore]`

### Control Parallelism

**Set number of test threads:**
```bash
# Use 4 threads (default is number of CPU cores)
cargo test --lib --tests -- --test-threads=4

# Use 8 threads for faster execution (if you have enough cores)
cargo test --lib --tests -- --test-threads=8

# Run sequentially (1 thread) - useful for debugging
cargo test --lib --tests -- --test-threads=1
```

**Set number of compilation jobs:**
```bash
# Use 4 parallel compilation jobs
cargo test --lib --tests -j 4
```

### Run Specific Test Files in Parallel

```bash
# Run all wallet-related tests in parallel
cargo test --test wallet_management_test --test wallet_isolation_test --test wallet_context_middleware_test --no-fail-fast

# Run all tests matching a pattern
cargo test --lib --tests wallet --no-fail-fast
```

### Example: Run All Backend Tests with Maximum Parallelism

```bash
cd backend/rust-api

# Set test database URL
export TEST_DATABASE_URL="postgresql://debt_tracker:dev_password@localhost:5432/debt_tracker_test"

# Run all tests in parallel (uses all CPU cores)
cargo test --lib --tests --no-fail-fast -- --test-threads=$(nproc)
```

## Frontend Tests (Flutter)

### Why Integration Tests Pass Only When Run One-at-a-Time

**Flutter integration tests use a single device.** When you run `flutter test integration_test/`, Flutter discovers multiple test **files** and runs them **in parallel** by default. Each integration test file must:

1. **Build** the app
2. **Launch** the app on the device (e.g. Linux desktop)
3. **Attach** a debug connection to the running app
4. **Execute** the tests

There is only **one device** (one Linux desktop, or one emulator). When several test files run in parallel, they all try to launch the app and attach to that same device at the same time. Only one process can have the app running and be attached at a time, so the others get:

- **"Unable to start the app on the device"**
- **"Error waiting for a debug connection: The log reader stopped unexpectedly, or never started."**

So integration tests **pass when run one file at a time** (no device contention) and **can fail when run all together** (multiple files competing for the same device). This is a Flutter/infrastructure limitation, not a bug in your tests.

**To get all integration tests to pass:** run them **sequentially** (one file after another), or run each file in a separate terminal on a separate device. The guide below shows both parallel (for unit tests) and sequential (for integration tests) options.

### Default Behavior

By default, `flutter test` runs **test files in parallel**, but tests within each file run **sequentially**. For integration tests, parallel file execution causes device contention (see above).

### Run All Tests in Parallel

```bash
cd mobile
flutter test -d linux
```

This runs all test files concurrently, executing all tests across multiple files simultaneously.

### Control Parallelism

**Set concurrency level:**
```bash
# Run 4 test files in parallel (default is number of CPU cores)
flutter test -d linux --concurrency=4

# Run 8 test files in parallel
flutter test -d linux --concurrency=8

# Run sequentially (1 file at a time) - useful for debugging
flutter test -d linux --concurrency=1
```

### Run Integration Tests So All Pass (Sequentially)

Because integration tests share one device, run them **one file at a time** so every file passes:

```bash
cd mobile

# Run each integration test file one after another (no device contention)
for f in integration_test/multi_app/scenarios/*.dart integration_test/multi_app/performance_test.dart integration_test/multi_app/flutter_http_benchmark.dart integration_test/multi_app/state_rebuild_benchmark.dart; do
  flutter test "$f" || exit 1
done
```

Or run a single file: `flutter test integration_test/multi_app/performance_test.dart`

**Note:** `--concurrency=1` is **ignored** for integration tests by Flutter, so you must run files in a loop (as above) to get sequential execution.

### Run Integration Tests in Parallel (May Fail on Single Device)

```bash
cd mobile

# Run all integration test scenarios in parallel (may fail: device contention)
flutter test integration_test/multi_app/scenarios/ -d linux --concurrency=4

# Run specific test suites in parallel (each in separate terminal)
# Terminal 1:
flutter test integration_test/multi_app/scenarios/basic_sync_scenarios.dart -d linux

# Terminal 2:
flutter test integration_test/multi_app/scenarios/offline_online_scenarios.dart -d linux

# Terminal 3:
flutter test integration_test/multi_app/scenarios/conflict_scenarios.dart -d linux

# Terminal 4:
flutter test integration_test/multi_app/scenarios/stress_scenarios.dart -d linux
```

### Example: Run All Flutter Tests with Maximum Parallelism

```bash
cd mobile

# Run all tests with maximum concurrency
flutter test -d linux --concurrency=$(nproc)

# Run integration tests with maximum concurrency
flutter test integration_test/multi_app/scenarios/ -d linux --concurrency=$(nproc)
```

## Multi-Wallet Parallel Testing

With the multi-wallet system, each test can have its own isolated user and wallet, enabling true parallel execution without data conflicts.

### Test Setup Pattern

Each test should:
1. Create unique users for each app instance
2. Create a shared wallet for the test
3. Add all users to the wallet
4. Use namespaced Hive boxes (automatically handled)

**Example test setup:**
```dart
setUp(() async {
  // Create unique users
  final user1 = await TestUserWalletHelpers.createTestUser(testIndex: 1);
  final user2 = await TestUserWalletHelpers.createTestUser(testIndex: 2);
  final user3 = await TestUserWalletHelpers.createTestUser(testIndex: 3);
  
  // Create shared wallet for this test
  final wallet = await TestUserWalletHelpers.createTestWallet(testIndex: testIndex);
  
  // Add all users to wallet
  await TestUserWalletHelpers.addUserToWallet(
    walletId: wallet['id']!,
    userId: user1['id']!,
    role: 'member',
  );
  await TestUserWalletHelpers.addUserToWallet(
    walletId: wallet['id']!,
    userId: user2['id']!,
    role: 'member',
  );
  await TestUserWalletHelpers.addUserToWallet(
    walletId: wallet['id']!,
    userId: user3['id']!,
    role: 'member',
  );
  
  // Create app instances with unique users and shared wallet
  app1 = await AppInstance.create(
    id: 'app1',
    username: user1['email']!,
    password: 'test123456',
    walletId: wallet['id']!,
  );
  app2 = await AppInstance.create(
    id: 'app2',
    username: user2['email']!,
    password: 'test123456',
    walletId: wallet['id']!,
  );
  app3 = await AppInstance.create(
    id: 'app3',
    username: user3['email']!,
    password: 'test123456',
    walletId: wallet['id']!,
  );
  
  // Initialize and login (each app has its own user and wallet)
  await Future.wait([
    app1!.initialize(),
    app2!.initialize(),
    app3!.initialize(),
  ]);
  
  await Future.wait([
    app1!.login(),
    app2!.login(),
    app3!.login(),
  ]);
});
```

### Benefits

- **No Data Conflicts**: Each test has isolated users and wallets
- **True Parallelism**: Tests can run simultaneously without interference
- **Faster Execution**: All tests run in parallel instead of sequentially
- **No Cleanup Needed**: Each test uses its own namespace

## Running Both Backend and Frontend Tests in Parallel

### Option 1: Separate Terminals

**Terminal 1 - Backend Tests:**
```bash
cd backend/rust-api
export TEST_DATABASE_URL="postgresql://debt_tracker:dev_password@localhost:5432/debt_tracker_test"
cargo test --lib --tests --no-fail-fast -- --test-threads=$(nproc)
```

**Terminal 2 - Frontend Tests:**
```bash
cd mobile
flutter test -d linux --concurrency=$(nproc)
```

### Option 2: Background Jobs

```bash
# Start backend tests in background
cd backend/rust-api
export TEST_DATABASE_URL="postgresql://debt_tracker:dev_password@localhost:5432/debt_tracker_test"
cargo test --lib --tests --no-fail-fast -- --test-threads=$(nproc) > backend_tests.log 2>&1 &

# Start frontend tests
cd mobile
flutter test -d linux --concurrency=$(nproc)

# Wait for backend tests to finish
wait
```

### Option 3: Using GNU Parallel (Advanced)

```bash
# Install GNU parallel: sudo apt install parallel

# Run both test suites in parallel
parallel -j 2 ::: \
  "cd backend/rust-api && export TEST_DATABASE_URL='postgresql://debt_tracker:dev_password@localhost:5432/debt_tracker_test' && cargo test --lib --tests --no-fail-fast" \
  "cd mobile && flutter test -d linux --concurrency=$(nproc)"
```

## Performance Tips

### Backend Tests

1. **Use test database**: Always use a separate test database
2. **Reuse connections**: Tests share the same database connection pool
3. **Parallel compilation**: Use `-j $(nproc)` for faster builds
4. **Test filtering**: Run only relevant tests during development

### Frontend Tests

1. **Concurrency**: Match concurrency to CPU cores (`--concurrency=$(nproc)`)
2. **Test isolation**: Use unique users/wallets per test
3. **Skip slow tests**: Use `@skip` for tests that don't need to run every time
4. **Group related tests**: Put related tests in the same file

## Troubleshooting

### Backend Tests Failing in Parallel

**Problem**: Tests fail when run in parallel but pass sequentially.

**Solution**: 
- Ensure each test uses unique data (different wallet IDs, user IDs)
- Check for shared state between tests
- Use `--test-threads=1` to debug, then fix isolation issues

### Frontend Tests Timing Out

**Problem**: Tests timeout when run in parallel.

**Solution**:
- Reduce concurrency: `--concurrency=2`
- Increase timeout: `--timeout=60s`
- Check for resource contention (database connections, network)

### Database Connection Errors

**Problem**: "Too many connections" errors when running tests in parallel.

**Solution**:
- Increase PostgreSQL `max_connections` in `docker-compose.yml`
- Use connection pooling in tests
- Reduce parallelism if needed

## Example: Complete Parallel Test Run

```bash
#!/bin/bash
# Run all tests in parallel

set -e

echo "🚀 Starting parallel test execution..."

# Start server (required for tests)
cd /home/max/dev/debitum
./scripts/manage.sh start-server-direct

# Wait for server to be ready
sleep 5

# Backend tests (background)
echo "📦 Running backend tests..."
cd backend/rust-api
export TEST_DATABASE_URL="postgresql://debt_tracker:dev_password@localhost:5432/debt_tracker_test"
cargo test --lib --tests --no-fail-fast -- --test-threads=$(nproc) &
BACKEND_PID=$!

# Frontend tests
echo "📱 Running frontend tests..."
cd ../../mobile
flutter test -d linux --concurrency=$(nproc) &
FRONTEND_PID=$!

# Wait for both to complete
wait $BACKEND_PID
BACKEND_EXIT=$?

wait $FRONTEND_PID
FRONTEND_EXIT=$?

# Report results
if [ $BACKEND_EXIT -eq 0 ] && [ $FRONTEND_EXIT -eq 0 ]; then
  echo "✅ All tests passed!"
  exit 0
else
  echo "❌ Some tests failed"
  exit 1
fi
```

## Summary

- **Backend**: `cargo test` runs in parallel by default, control with `--test-threads=N`
- **Frontend**: `flutter test` runs test files in parallel, control with `--concurrency=N`
- **Multi-Wallet**: Enables true parallel testing with isolated data per test
- **Maximum Speed**: Use `$(nproc)` to match CPU core count for optimal parallelism
