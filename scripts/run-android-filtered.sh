#!/bin/bash
# Run Flutter Android app with filtered logs in a separate terminal
# This script starts Flutter normally (so interactive commands work) and provides
# instructions for filtering logs in a separate terminal

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR/mobile"

# Add Flutter to PATH
export PATH="$PATH:$HOME/flutter/bin"

DEVICE_ID="${1:-}"

echo "📱 Running Flutter on Android..."
echo ""
echo "💡 To filter Android system logs, open a SEPARATE terminal and run:"
echo "   adb logcat -s flutter:D DartVM:D"
echo ""
echo "   This will show only Flutter/Dart logs without interfering with"
echo "   Flutter's interactive commands (r for reload, R for restart, etc.)"
echo ""
echo "🚀 Starting Flutter (interactive commands will work normally)..."
echo ""

# Run Flutter normally so interactive commands work
if [ -n "$DEVICE_ID" ]; then
    flutter run -d "$DEVICE_ID"
else
    flutter run
fi
