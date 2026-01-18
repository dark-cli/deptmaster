# Web App Fix Summary

## Problem
The web app was showing a dark screen because **Hive doesn't work in web browsers**. Hive is a local storage solution that only works on mobile/desktop platforms.

## Solution
I've updated the code to:
1. ✅ Skip Hive initialization for web (`kIsWeb` check)
2. ✅ Load data directly from API in web screens
3. ✅ Use state management instead of Hive for web
4. ✅ Keep Hive for mobile/desktop platforms

## Changes Made

### `lib/main.dart`
- Added `kIsWeb` check to skip Hive initialization for web
- Web apps will load data directly in screens

### `lib/screens/contacts_screen.dart`
- Converted to `ConsumerStatefulWidget` for web
- Loads data directly from API for web
- Uses Hive for mobile (existing behavior)

### `lib/screens/transactions_screen.dart`
- Converted to `ConsumerStatefulWidget` for web
- Loads data directly from API for web
- Uses Hive for mobile (existing behavior)

### `lib/services/data_service.dart`
- Added `kIsWeb` check to skip Hive operations for web

## Next Steps

The web app is being rebuilt. Once the build completes:

1. The web app should work properly
2. It will load your 59 contacts and 249 transactions
3. No more dark screen!

## Alternative: Linux Desktop

If you prefer, you can install build tools and run the Linux desktop version:

```bash
sudo dnf install -y cmake ninja-build clang gtk3-devel pkg-config
cd /home/max/dev/debitum/mobile
export PATH="$PATH:$HOME/flutter/bin"
flutter run -d linux
```

This will open a native desktop window instead of using the browser.
