#!/bin/bash
# Mobile App Management Script
# Usage: ./mobile.sh <command> [options]

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/mobile"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_error() {
    echo -e "${RED}❌ $1${NC}" >&2
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# Add Flutter to PATH
export PATH="$PATH:$HOME/flutter/bin"

# Check Flutter
if ! command -v flutter &> /dev/null; then
    print_error "Flutter not found. Make sure it's in PATH:"
    echo "   export PATH=\"\$PATH:\$HOME/flutter/bin\""
    exit 1
fi

cmd_run() {
    local platform="${1:-android}"
    local device_id="${2:-}"
    local clear_data="${3:-false}"
    
    print_info "Running Flutter app ($platform)..."
    
    # Clear data if requested
    if [ "$clear_data" = "true" ]; then
        if [ "$platform" = "linux" ] || [ "$platform" = "android" ]; then
            print_info "Clearing app data..."
            if [ "$platform" = "linux" ]; then
                rm -rf ~/.local/share/debt_tracker_mobile 2>/dev/null || true
            elif [ "$platform" = "android" ]; then
                flutter clean
            fi
        else
            print_error "--clear flag only works with 'linux' or 'android' platform"
        fi
    fi
    
    if [ "$platform" = "web" ]; then
        print_info "Starting Flutter web app..."
        flutter run -d chrome
    elif [ "$platform" = "android" ]; then
        print_info "Starting Android app..."
        if [ -n "$device_id" ]; then
            flutter run -d "$device_id"
        else
            flutter run
        fi
    elif [ "$platform" = "linux" ]; then
        print_info "Starting Linux desktop app..."
        flutter run -d linux
    else
        print_error "Unknown platform: $platform"
        echo "Supported platforms: android, web, linux"
        exit 1
    fi
}

cmd_build() {
    local platform="${1:-web}"
    
    print_info "Building Flutter app ($platform)..."
    
    if [ "$platform" = "web" ]; then
        flutter build web --no-source-maps
        print_success "Web build complete! Output: build/web"
    elif [ "$platform" = "android" ]; then
        flutter build apk --release
        print_success "Android build complete! Output: build/app/outputs/flutter-apk/app-release.apk"
    elif [ "$platform" = "linux" ]; then
        flutter build linux --release
        print_success "Linux build complete! Output: build/linux/x64/release/bundle"
    else
        print_error "Unknown platform: $platform"
        exit 1
    fi
}

cmd_test() {
    local test_file="${1:-}"
    
    print_info "Running Flutter tests..."
    
    if [ -n "$test_file" ]; then
        flutter test "$test_file"
    else
        flutter test
    fi
    
    print_success "Tests complete"
}

cmd_setup() {
    print_info "Setting up Flutter app..."
    
    print_info "Installing dependencies..."
    flutter pub get
    
    print_info "Generating Hive adapters..."
    flutter pub run build_runner build --delete-conflicting-outputs
    
    print_success "Setup complete"
}

cmd_clean() {
    print_info "Cleaning Flutter build artifacts..."
    flutter clean
    print_success "Clean complete"
}

cmd_help() {
    cat <<EOF
Mobile App Management Script

Usage: $0 <command> [options]

Commands:
  run [platform] [device] [--clear]    Run Flutter app
                                        Platforms: android, web, linux
                                        Use --clear to clear app data
  
  build [platform]                      Build Flutter app
                                        Platforms: android, web, linux
  
  test [test_file]                      Run Flutter tests
  
  setup                                 Setup Flutter app (install deps, generate adapters)
  
  clean                                 Clean build artifacts
  
  help                                  Show this help message

Examples:
  $0 run android                        # Run Android app
  $0 run web                            # Run web app
  $0 run linux --clear                  # Run Linux app with cleared data
  $0 build android                      # Build Android APK
  $0 test                               # Run all tests
  $0 setup                              # Setup app

EOF
}

# Main command dispatcher
case "${1:-help}" in
    run)
        CLEAR_DATA=false
        PLATFORM="${2:-android}"
        DEVICE_ID="${3:-}"
        
        # Check for --clear flag
        for arg in "$@"; do
            if [ "$arg" = "--clear" ]; then
                CLEAR_DATA=true
            fi
        done
        
        cmd_run "$PLATFORM" "$DEVICE_ID" "$CLEAR_DATA"
        ;;
    build)
        cmd_build "${2:-web}"
        ;;
    test)
        cmd_test "${2:-}"
        ;;
    setup)
        cmd_setup
        ;;
    clean)
        cmd_clean
        ;;
    help|--help|-h)
        cmd_help
        ;;
    *)
        print_error "Unknown command: $1"
        echo ""
        cmd_help
        exit 1
        ;;
esac
