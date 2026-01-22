#!/bin/bash
# Clear app data before running Flutter app on Linux

set -e

APP_NAME="debt_tracker_mobile"

echo "🧹 Clearing app data for $APP_NAME..."

# Common locations for Flutter Linux app data
DATA_DIRS=(
    "$HOME/.local/share/$APP_NAME"
    "$HOME/.config/$APP_NAME"
    "$HOME/.local/share/flutter/$APP_NAME"
)

CLEARED=false

for dir in "${DATA_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        echo "   Removing: $dir"
        rm -rf "$dir"
        CLEARED=true
    fi
done

if [ "$CLEARED" = true ]; then
    echo "✅ App data cleared successfully!"
else
    echo "ℹ️  No app data found to clear (app may not have been run yet)"
fi

echo ""
echo "📝 You can now run: flutter run -d linux"
