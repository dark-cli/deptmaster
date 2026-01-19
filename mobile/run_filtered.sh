#!/bin/bash
# Run Flutter app with filtered logs (hides Android system messages)
# Usage: ./run_filtered.sh [device_id]

DEVICE="${1:-}"

# Get Flutter path
FLUTTER_CMD="flutter"
if [ -f "$HOME/flutter/bin/flutter" ]; then
    FLUTTER_CMD="$HOME/flutter/bin/flutter"
fi

if [ -z "$DEVICE" ]; then
    # Run Flutter normally, but pipe output through filter
    echo "🚀 Running Flutter app with filtered logs..."
    echo "   (Hiding Android system messages like gralloc, Surface, etc.)"
    echo ""
    
    # Run Flutter and filter out Android system logs
    $FLUTTER_CMD run 2>&1 | grep -v -E "(qdgralloc|Gralloc|GraphicBuffer|AHardwareBuffer|Surface|VRI\[|SV\[|Insets|ImeFocus|HWUI|SurfaceComposer|CacheManager|SurfaceView|EGL_emulation|TrafficStats|OpenGLRenderer)" | grep -v "^W/" | grep -v "^D/" | grep -v "^V/"
else
    $FLUTTER_CMD run -d "$DEVICE" 2>&1 | grep -v -E "(qdgralloc|Gralloc|GraphicBuffer|AHardwareBuffer|Surface|VRI\[|SV\[|Insets|ImeFocus|HWUI|SurfaceComposer|CacheManager|SurfaceView|EGL_emulation|TrafficStats|OpenGLRenderer)" | grep -v "^W/" | grep -v "^D/" | grep -v "^V/"
fi
