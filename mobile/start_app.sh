#!/bin/bash
# Start Flutter app - Web or Linux Desktop

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

# Check for --clear flag
CLEAR_DATA=false
ARGS=()
for arg in "$@"; do
    if [ "$arg" = "--clear" ]; then
        CLEAR_DATA=true
    else
        ARGS+=("$arg")
    fi
done

# Check which platform to use
PLATFORM="${ARGS[0]:-web}"
MODE="${ARGS[1]:-prod}"

# Clear data if requested (only for Linux)
if [ "$CLEAR_DATA" = true ] && [ "$PLATFORM" = "linux" ]; then
    echo "🧹 Clearing app data..."
    ./clear_data.sh
    echo ""
fi

if [ "$PLATFORM" = "web" ]; then
    if [ "$MODE" = "dev" ]; then
        echo "🌐 Starting Flutter web app in DEVELOPMENT mode (hot reload)..."
        echo "   App will be available at: http://localhost:8080"
        echo ""
        echo "   Hot reload commands:"
        echo "   - Press 'r' in terminal for hot reload"
        echo "   - Press 'R' in terminal for hot restart"
        echo "   - Press 'q' to quit"
        echo ""
        flutter run -d web-server --web-port 8080
    else
        echo "🌐 Building for web (PRODUCTION mode)..."
        flutter build web --no-source-maps
        
        # Remove any remaining source map references
        ./remove_sourcemaps.sh 2>/dev/null || true

        echo ""
        echo "✅ Build complete!"
        echo ""
        echo "✅ Build complete!"
        echo ""
        echo "📝 To run the web app, use:"
        echo "   python3 -m http.server 8080 --directory build/web"
        echo ""
        echo "   Or for hot reload: $0 web dev"
        echo ""
        echo "   Note: You are responsible for starting/stopping the server"
    fi

elif [ "$PLATFORM" = "linux" ]; then
    echo "🖥️  Running Linux desktop app..."
    echo "   (Make sure build tools are installed: cmake, ninja, clang, gtk3-devel)"
    echo ""

    flutter run -d linux

else
    echo "Usage: $0 [web|linux] [dev|prod] [--clear]"
    echo ""
    echo "  web [dev]   - Run web app with hot reload (default: prod)"
    echo "  web [prod]  - Build and serve web app (default)"
    echo "  linux       - Run Linux desktop app"
    echo "  --clear     - Clear app data before running (Linux only)"
    echo ""
    echo "Examples:"
    echo "  $0 web dev        - Development mode with hot reload"
    echo "  $0 web prod       - Production build (current default)"
    echo "  $0 web            - Production build (same as 'prod')"
    echo "  $0 linux --clear  - Run Linux app with cleared data"
    exit 1
fi
