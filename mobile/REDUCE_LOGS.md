# How to Reduce Verbose Logs

The Android system generates a lot of verbose logs (VRI, InsetsController, BLASTBufferQueue, etc.) that clutter the console. Here are ways to reduce them:

## Option 1: Filter Logs with manage.sh (Recommended) ⭐

**This is the best method** - it keeps Flutter's interactive commands working!

1. Run Flutter normally:
   ```bash
   # Using manage.sh (recommended)
   ./scripts/manage.sh run-flutter-app android
   
   # Or directly with Flutter
   flutter run -d android
   ```

2. In a **separate terminal**, show filtered logs:
   ```bash
   # Using manage.sh (easiest)
   ./scripts/manage.sh show-android-logs
   
   # Or directly with adb
   adb logcat -s flutter:D DartVM:D
   
   # Or filter out specific Android system tags
   adb logcat | grep -v -E "(VRI|InsetsController|BLASTBufferQueue|SurfaceView|InputMethod|Choreographer|HWUI|ProfileInstaller|qdgralloc)"
   ```

**Benefits:**
- ✅ Flutter interactive commands work (r, R, h, etc.)
- ✅ Only shows relevant logs
- ✅ Easy to toggle on/off

## Option 2: Use Flutter's Built-in Controls

When Flutter is running, you can:

- Press `c` to clear the screen (removes old logs)
- Press `h` to see all available commands
- The Flutter output itself is already filtered (shows `I/flutter` logs)

## Option 3: Use manage.sh Command

```bash
./scripts/manage.sh show-android-logs
```

This runs the filtered log command directly. Use it in a separate terminal while your Flutter app is running.

**Note:** This is just a convenience wrapper around `adb logcat -s flutter:D DartVM:D`. The app runs normally so Flutter's interactive commands (r, R, h, etc.) work!

## Option 4: Reduce App Logging (Future)

The app uses `print()` statements for logging. To reduce app logs in the future:

1. Use the `Logger` utility in `lib/utils/logger.dart` (already created)
2. Replace verbose `print()` calls with conditional logging
3. Set `kDebugMode` checks around verbose logs

## Best Practice

**For development:** Use Option 1 (separate terminal with adb logcat filtering)
- ✅ Keeps Flutter interactive commands working
- ✅ Shows only relevant logs  
- ✅ Easy to toggle on/off
- ✅ No interference with Flutter's stdin

**For production:** Logs are automatically reduced (only errors/warnings)
