#!/bin/bash
# Run Flutter with filtered logs (only Flutter/Dart logs, no Android system logs)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR/mobile"

# Add Flutter to PATH
export PATH="$PATH:$HOME/flutter/bin"

# Get device/platform from args
PLATFORM="${1:-android}"
DEVICE_ID="${2:-}"

# Filter logs to only show Flutter/Dart output
# This filters out Android system logs (VRI, InsetsController, etc.)
if [ "$PLATFORM" = "android" ]; then
    # For Android, use adb logcat filtering
    echo "📱 Running Flutter on Android with filtered logs..."
    echo "   (Only showing Flutter/Dart logs, hiding Android system logs)"
    echo ""
    
    # Start Flutter in background and filter its output
    flutter run -d "$DEVICE_ID" 2>&1 | grep -E "(flutter|I/flutter|Dart VM|Performing|Reloaded|Error|Exception|❌|✅|⚠️|🔄|📤|📥)" || true
else
    # For other platforms, just run normally (they don't have Android system logs)
    echo "🚀 Running Flutter on $PLATFORM..."
    flutter run -d "$PLATFORM"
fi
