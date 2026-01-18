#!/bin/bash
# Run Flutter web app with hot reload support

set -e

# Add Flutter to PATH
export PATH="$PATH:$HOME/flutter/bin"

cd "$(dirname "$0")"

echo "🔍 Checking Flutter..."
if ! command -v flutter &> /dev/null; then
    echo "❌ Flutter not found. Make sure it's in PATH:"
    echo "   export PATH=\"\$PATH:\$HOME/flutter/bin\""
    exit 1
fi

echo "✅ Flutter found"
echo ""

echo "🌐 Starting Flutter web app with hot reload..."
echo "   App will be available at: http://localhost:8080"
echo ""
echo "   Hot reload commands:"
echo "   - Press 'r' in terminal for hot reload"
echo "   - Press 'R' in terminal for hot restart"
echo "   - Press 'q' to quit"
echo ""

# Run with web-server mode (no browser auto-open, but supports hot reload)
flutter run -d web-server --web-port 8080
