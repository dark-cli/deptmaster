# Running Tests

## Prerequisites

1. Ensure `build_runner` has been run to generate Hive adapters:
```bash
cd mobile
flutter pub run build_runner build --delete-conflicting-outputs
```

2. For integration tests that require backend:
   - Ensure backend server is running
   - Configure backend IP and port in the app settings

## Running Unit Tests

```bash
cd mobile

# Run all unit tests
flutter test test/unit/

# Run specific test file
flutter test test/unit/state_builder_test.dart

# Run with verbose output
flutter test test/unit/ --verbose
```

## Running Integration Tests

```bash
cd mobile

# Run all integration tests
flutter test integration_test/

# Run specific integration test
flutter test integration_test/app_test.dart

# Run on specific device
flutter test integration_test/app_test.dart -d <device-id>

# List available devices
flutter devices
```

## Running All Tests

```bash
cd mobile
flutter test
```

## Test Coverage

To generate test coverage report:

```bash
cd mobile
flutter test --coverage
genhtml coverage/lcov.info -o coverage/html
```

Then open `coverage/html/index.html` in a browser.

## Troubleshooting

### "Adapter not found" errors
Run `build_runner` to generate adapters:
```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

### Integration tests fail with "Backend not configured"
Configure backend in app settings or skip backend-dependent tests.

### Tests fail with Hive errors
Ensure Hive is properly initialized. Tests should handle this automatically, but if issues persist, check that adapters are registered.
