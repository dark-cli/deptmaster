#!/bin/bash
# Check and install Linux desktop dependencies

echo "🔍 Checking for required packages..."
echo ""

MISSING=0

# Check clang
if ! command -v clang++ &> /dev/null; then
    echo "❌ clang++ not found"
    MISSING=1
else
    echo "✅ clang++ found: $(which clang++)"
fi

# Check ninja
if ! command -v ninja &> /dev/null; then
    echo "❌ ninja not found"
    MISSING=1
else
    echo "✅ ninja found: $(which ninja)"
fi

# Check GTK3
if ! pkg-config --exists gtk+-3.0 2>/dev/null; then
    echo "❌ GTK3 development libraries not found"
    MISSING=1
else
    echo "✅ GTK3 development libraries found"
fi

echo ""

if [ $MISSING -eq 1 ]; then
    echo "📦 Installing missing packages..."
    echo ""
    echo "Run this command:"
    echo "  sudo dnf install -y clang ninja-build gtk3-devel"
    echo ""
    echo "Or if you prefer to install manually:"
    echo "  sudo dnf install clang"
    echo "  sudo dnf install ninja-build"
    echo "  sudo dnf install gtk3-devel"
else
    echo "✅ All dependencies are installed!"
    echo ""
    echo "If you're still getting errors, try:"
    echo "  cd /home/max/dev/debitum/mobile"
    echo "  flutter clean"
    echo "  flutter pub get"
    echo "  flutter run -d linux"
fi
