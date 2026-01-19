#!/bin/bash
# Filter Android system logs to show only Flutter app logs
# Usage: ./filter_logs.sh [device_id]

DEVICE="${1:-}"

if [ -z "$DEVICE" ]; then
    # Get first connected device
    DEVICE=$(adb devices | grep -v "List" | grep "device" | head -1 | cut -f1)
    if [ -z "$DEVICE" ]; then
        echo "❌ No Android device found"
        exit 1
    fi
    echo "📱 Using device: $DEVICE"
fi

echo "🔍 Filtering logs (hiding Android system messages)..."
echo "   Showing only Flutter/Dart logs"
echo ""

# Filter out Android system logs and show only Flutter/Dart logs
adb -s "$DEVICE" logcat -c  # Clear log buffer
adb -s "$DEVICE" logcat | grep -E "(flutter|dart|I/flutter|D/flutter|E/flutter|W/flutter)" | grep -v -E "(qdgralloc|Gralloc|GraphicBuffer|AHardwareBuffer|Surface|VRI|SV|Insets|ImeFocus|HWUI|SurfaceComposer|CacheManager)"
