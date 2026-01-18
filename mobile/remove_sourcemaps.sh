#!/bin/bash
# Remove source map references from Flutter web build

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build/web"

if [ ! -d "$BUILD_DIR" ]; then
    echo "⚠️  Build directory not found: $BUILD_DIR"
    exit 0
fi

cd "$BUILD_DIR" || exit 0

# Remove source map references from JS files
# Use perl for better compatibility (handles inline code better than sed)
find . -name "*.js" -type f -print0 | while IFS= read -r -d '' file; do
    perl -i -pe 's|//# sourceMappingURL=.*\.map||g; s|// @sourceMappingURL=.*\.map||g; s|//sourceMappingURL=.*\.map||g' "$file"
done

# Also check for any remaining references
REMAINING=$(grep -r "sourceMappingURL" . 2>/dev/null | wc -l)
if [ "$REMAINING" -eq 0 ]; then
    echo "✅ Removed all source map references"
else
    echo "⚠️  Found $REMAINING remaining source map references"
    grep -r "sourceMappingURL" . 2>/dev/null | head -3
fi
