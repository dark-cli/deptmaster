#!/usr/bin/env bash
# Download and install Android NDK (r27d LTS) for Linux into $HOME/Android/Sdk/ndk.
# Usage:
#   ./scripts/install-android-ndk.sh              # install only
#   ./scripts/install-android-ndk.sh run          # install then run Flutter app on Android
#   source scripts/install-android-ndk.sh         # install and set ANDROID_NDK_HOME in current shell

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
NDK_URL="https://dl.google.com/android/repository/android-ndk-r27d-linux.zip"
NDK_DIR="${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}"
NDK_PARENT="$NDK_DIR/ndk"
NDK_NAME="android-ndk-r27d"
ZIP="/tmp/android-ndk-r27d-linux.zip"
DO_RUN=false
[ "${1:-}" = "run" ] && DO_RUN=true

if [ -d "$NDK_PARENT/$NDK_NAME" ]; then
  echo "NDK already installed at $NDK_PARENT/$NDK_NAME"
  export ANDROID_NDK_HOME="$NDK_PARENT/$NDK_NAME"
  if [ "$DO_RUN" = true ]; then
    exec "$SCRIPT_DIR/manage.sh" run-flutter-app android --clear-app-data "${@:2}"
  fi
  echo "Export for current shell: export ANDROID_NDK_HOME=$NDK_PARENT/$NDK_NAME"
  echo "Then: ./scripts/manage.sh run-flutter-app android --clear-app-data"
  exit 0
fi

mkdir -p "$NDK_PARENT"
if [ ! -f "$ZIP" ]; then
  echo "Downloading Android NDK r27d (~633 MB)..."
  curl -L -o "$ZIP" "$NDK_URL"
fi
echo "Extracting..."
unzip -q -o "$ZIP" -d "$NDK_PARENT"
rm -f "$ZIP"
echo "Done. NDK at $NDK_PARENT/$NDK_NAME"
export ANDROID_NDK_HOME="$NDK_PARENT/$NDK_NAME"
if [ "$DO_RUN" = true ]; then
  echo "Running Flutter app on Android..."
  exec "$SCRIPT_DIR/manage.sh" run-flutter-app android --clear-app-data "${@:2}"
fi
echo ""
echo "Run: export ANDROID_NDK_HOME=$NDK_PARENT/$NDK_NAME"
echo "Then: ./scripts/manage.sh run-flutter-app android --clear-app-data"
echo "Or next time: ./scripts/install-android-ndk.sh run"
