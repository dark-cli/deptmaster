# Source Map Error Fix

## Issue
Browser console shows:
```
Source map error: Error: JSON.parse: unexpected character at line 1 column 1 of the JSON data
Source Map URL: flutter.js.map
```

## Root Cause

Even with `--no-source-maps` flag, Flutter's `flutter_bootstrap.js` and `flutter.js` files still contain commented-out source map references like:
```javascript
//# sourceMappingURL=flutter.js.map
```

The browser devtools tries to load these files, but they don't exist, causing the error.

## Solution Applied

### 1. Post-Build Script
Created `mobile/remove_sourcemaps.sh` that removes all source map references after build:
```bash
#!/bin/bash
cd build/web
find . -name "*.js" -type f -exec sed -i 's|//# sourceMappingURL=.*\.map||g' {} \;
```

### 2. Integrated into Build Scripts
- `start_app.sh` - Automatically runs `remove_sourcemaps.sh` after build
- `RUN_WEB_APP.sh` - Automatically runs `remove_sourcemaps.sh` after build

### 3. Manual Fix (if needed)
```bash
cd mobile
./remove_sourcemaps.sh
```

## Verification

After building, verify source maps are removed:
```bash
cd mobile/build/web
grep -r "sourceMappingURL" . | wc -l
# Should be 0
```

## Notes

- Source maps are only needed for debugging
- Production builds should always use `--no-source-maps`
- Development mode (`flutter run`) will always generate source maps
- The error doesn't affect app functionality, but removing it cleans up console
- The fix is automatically applied when using build scripts
