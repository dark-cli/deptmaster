# Flutter Web Hot Reload

## Current Setup (No Hot Reload)

**Current method:**
- `flutter build web` - builds static files
- `python3 -m http.server` - serves static files
- **No hot reload** - need to rebuild after changes

## Option 1: Use Flutter's Built-in Web Server (Hot Reload ✅)

Flutter has a built-in web server that supports hot reload:

```bash
cd /home/max/dev/debitum/mobile
export PATH="$PATH:$HOME/flutter/bin"
flutter run -d chrome
# or
flutter run -d web-server  # Runs on http://localhost:8080
```

**Benefits:**
- ✅ Hot reload (press `r` in terminal)
- ✅ Hot restart (press `R` in terminal)
- ✅ Automatic rebuild on save (with `--hot` flag)
- ✅ Fast development cycle

**Limitations:**
- Requires Chrome/Chromium installed
- Or uses `web-server` mode (no browser auto-open)

## Option 2: Keep Current Setup (Manual Rebuild)

**Current workflow:**
```bash
# 1. Make code changes
# 2. Rebuild
cd /home/max/dev/debitum/mobile
export PATH="$PATH:$HOME/flutter/bin"
flutter build web

# 3. Restart server (or it auto-serves new files)
# 4. Refresh browser
```

**Benefits:**
- ✅ Works with any static file server
- ✅ Production-like environment
- ✅ No browser requirements

**Limitations:**
- ❌ No hot reload
- ❌ Need to rebuild manually
- ❌ Slower development cycle

## Recommendation

For **development**, use Option 1 (hot reload):
```bash
flutter run -d web-server
```

For **testing production builds**, use Option 2 (current setup):
```bash
flutter build web && python3 -m http.server 8080 --directory build/web
```

## Quick Script for Hot Reload

I can create a script that uses `flutter run -d web-server` for you!
