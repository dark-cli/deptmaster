#!/bin/bash
# Clear app data before running Flutter app on Linux or Android

set -e

APP_NAME="debt_tracker_mobile"
ANDROID_PACKAGE="com.example.debt_tracker_mobile"
PLATFORM="${1:-linux}"

if [ "$PLATFORM" = "android" ]; then
    echo "🧹 Clearing Android app data for $ANDROID_PACKAGE..."
    
    # Check if adb is available
    if ! command -v adb &> /dev/null; then
        echo "❌ adb not found. Make sure Android SDK platform-tools are in PATH"
        exit 1
    fi
    
    # Check if device is connected
    if ! adb devices | grep -q "device$"; then
        echo "❌ No Android device connected. Please connect a device and enable USB debugging"
        exit 1
    fi
    
    # Clear app data
    echo "   Running: adb shell pm clear $ANDROID_PACKAGE"
    if adb shell pm clear "$ANDROID_PACKAGE" 2>/dev/null; then
        echo "✅ Android app data cleared successfully!"
    else
        echo "⚠️  Failed to clear app data (app may not be installed yet)"
    fi
    
elif [ "$PLATFORM" = "linux" ]; then
    echo "🧹 Clearing Linux app data for $APP_NAME..."
    
    # Check if app is running and stop it first (to unlock files)
    # Look for Flutter app processes related to our app
    if pgrep -f "debt_tracker_mobile" > /dev/null || pgrep -f "com.example.debt_tracker_mobile" > /dev/null; then
        echo "   ⚠️  App appears to be running, attempting to stop it first..."
        pkill -f "debt_tracker_mobile" 2>/dev/null || true
        pkill -f "com.example.debt_tracker_mobile" 2>/dev/null || true
        sleep 2  # Give it a moment to release file locks
    fi
    
    # Common locations for Flutter Linux app data
    # Hive uses the package name format: com.example.debt_tracker_mobile
    # SharedPreferences may also use this or the app name
    DATA_DIRS=(
        "$HOME/.local/share/com.example.debt_tracker_mobile"
        "$HOME/.local/share/$APP_NAME"
        "$HOME/.config/com.example.debt_tracker_mobile"
        "$HOME/.config/$APP_NAME"
        "$HOME/.local/share/flutter/$APP_NAME"
        "$HOME/.local/share/flutter/com.example.debt_tracker_mobile"
    )
    
    CLEARED=false
    
    for dir in "${DATA_DIRS[@]}"; do
        if [ -d "$dir" ]; then
            echo "   Removing directory: $dir"
            # Force remove even if some files are locked (will remove what it can)
            rm -rf "$dir" 2>/dev/null || {
                echo "   ⚠️  Some files may be locked, trying again..."
                sleep 1
                rm -rf "$dir" 2>/dev/null || true
            }
            CLEARED=true
        fi
    done
    
    # Also remove specific Hive box files if they exist in the directory
    # Hive stores boxes as: contacts.hive, transactions.hive, events.hive
    HIVE_BOXES=(
        "$HOME/.local/share/com.example.debt_tracker_mobile/contacts.hive"
        "$HOME/.local/share/com.example.debt_tracker_mobile/transactions.hive"
        "$HOME/.local/share/com.example.debt_tracker_mobile/events.hive"
        "$HOME/.local/share/com.example.debt_tracker_mobile/contacts.hive.lock"
        "$HOME/.local/share/com.example.debt_tracker_mobile/transactions.hive.lock"
        "$HOME/.local/share/com.example.debt_tracker_mobile/events.hive.lock"
        "$HOME/.local/share/$APP_NAME/contacts.hive"
        "$HOME/.local/share/$APP_NAME/transactions.hive"
        "$HOME/.local/share/$APP_NAME/events.hive"
        "$HOME/.local/share/$APP_NAME/contacts.hive.lock"
        "$HOME/.local/share/$APP_NAME/transactions.hive.lock"
        "$HOME/.local/share/$APP_NAME/events.hive.lock"
    )
    
    for file in "${HIVE_BOXES[@]}"; do
        if [ -f "$file" ]; then
            echo "   Removing Hive file: $file"
            rm -f "$file"
            CLEARED=true
        fi
    done
    
    # Also check for box files without .hive extension (some Hive versions)
    for box_name in "contacts" "transactions" "events"; do
        for base_dir in "$HOME/.local/share/com.example.debt_tracker_mobile" "$HOME/.local/share/$APP_NAME"; do
            if [ -f "$base_dir/$box_name" ]; then
                echo "   Removing Hive box: $base_dir/$box_name"
                rm -f "$base_dir/$box_name"
                rm -f "$base_dir/$box_name.lock"
                CLEARED=true
            fi
        done
    done
    
    if [ "$CLEARED" = true ]; then
        echo "✅ Linux app data cleared successfully!"
        echo ""
        echo "   Verified: Data directories removed"
        # Double-check that the main directory is gone
        if [ ! -d "$HOME/.local/share/com.example.debt_tracker_mobile" ]; then
            echo "   ✅ Confirmed: Main data directory removed"
        else
            echo "   ⚠️  Warning: Main data directory still exists (may be locked)"
        fi
    else
        echo "ℹ️  No app data found to clear (app may not have been run yet)"
        echo "   Checked directories:"
        for dir in "${DATA_DIRS[@]}"; do
            if [ -d "$dir" ]; then
                echo "     ⚠️  Still exists: $dir"
            else
                echo "     ✓ Not found: $dir"
            fi
        done
    fi
else
    echo "Usage: $0 [linux|android]"
    echo ""
    echo "  linux   - Clear Linux app data (default)"
    echo "  android - Clear Android app data using adb"
    exit 1
fi

echo ""
