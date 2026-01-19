# Filtering Android System Logs

## Quick Solution

Use the provided script to run Flutter with filtered logs:

```bash
cd mobile
./run_filtered.sh
```

This will hide Android system messages like `gralloc`, `Surface`, `VRI`, etc.

## Alternative Methods

### 1. Use ADB Logcat with Filters

Run your app normally, then in another terminal:

```bash
# Show only Flutter/Dart logs
adb logcat | grep -E "(flutter|dart|I/flutter)"

# Or hide specific tags
adb logcat | grep -v -E "(qdgralloc|Gralloc|Surface|VRI)"
```

### 2. Configure Android Studio

1. Open **Logcat** panel
2. Click the filter dropdown
3. Select "Show only selected application"
4. Or create a custom filter: `package:com.example.debt_tracker_mobile`

### 3. Configure VS Code

1. Open Debug Console
2. Use the filter box to hide specific tags
3. Or install a log filtering extension

### 4. Run in Release Mode

Release mode shows fewer system logs:

```bash
flutter run --release
```

## Note

These Android system logs (`gralloc`, `Surface`, etc.) are **harmless** and don't affect your app. They're just verbose system messages from Android's graphics subsystem.
