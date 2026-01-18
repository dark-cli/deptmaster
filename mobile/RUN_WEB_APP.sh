#!/bin/bash
# Run Flutter web app

set -e

# Add Flutter to PATH
export PATH="$PATH:$HOME/flutter/bin"

cd "$(dirname "$0")"

echo "🔨 Building Flutter web app..."
flutter build web --no-source-maps

# Remove any remaining source map references
./remove_sourcemaps.sh 2>/dev/null || true

echo ""
echo "✅ Build complete!"
echo ""
echo "📝 To run the web app, use:"
echo "   python3 -m http.server 8080 --directory build/web"
echo ""
echo "🌐 Then open in browser: http://localhost:8080"
echo ""
echo "   Note: You are responsible for starting/stopping the server"
