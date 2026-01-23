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

# For Android, second arg is device ID (if not dev/prod)
# For web, second arg is mode (dev/prod)
if [ "$PLATFORM" = "android" ]; then
    DEVICE_ID="${ARGS[1]:-}"
    MODE="prod"  # Android doesn't use mode
elif [ "$PLATFORM" = "web" ]; then
    MODE="${ARGS[1]:-prod}"
    DEVICE_ID=""
else
    MODE="prod"
    DEVICE_ID=""
fi

# Clear data if requested (for Linux or Android)
if [ "$CLEAR_DATA" = true ]; then
    if [ "$PLATFORM" = "linux" ] || [ "$PLATFORM" = "android" ]; then
        echo "🧹 Clearing app data..."
        ./clear_data.sh "$PLATFORM"
        echo ""
    else
        echo "⚠️  --clear flag only works with 'linux' or 'android' platform"
        echo ""
    fi
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

elif [ "$PLATFORM" = "android" ]; then
    echo "📱 Running Android app..."
    
    # Use provided device ID or let Flutter auto-detect
    if [ -n "$DEVICE_ID" ]; then
        echo "   Using device: $DEVICE_ID"
        flutter run -d "$DEVICE_ID"
    else
        echo "   Auto-detecting device..."
        flutter run -d android
    fi

else
    echo "Usage: $0 [web|linux|android] [dev|prod|DEVICE_ID] [--clear]"
    echo ""
    echo "  web [dev]      - Run web app with hot reload (default: prod)"
    echo "  web [prod]     - Build and serve web app (default)"
    echo "  linux          - Run Linux desktop app"
    echo "  android [ID]   - Run Android app (optionally specify device ID)"
    echo "  --clear        - Clear app data before running (Linux/Android only)"
    echo ""
    echo "Examples:"
    echo "  $0 web dev              - Development mode with hot reload"
    echo "  $0 web prod             - Production build (current default)"
    echo "  $0 web                  - Production build (same as 'prod')"
    echo "  $0 linux --clear        - Run Linux app with cleared data"
    echo "  $0 android --clear      - Run Android app with cleared data (auto-detect device)"
    echo "  $0 android R5CXB1BJ9RN --clear  - Run on specific device with cleared data"
    exit 1
fi
