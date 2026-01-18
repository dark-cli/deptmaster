#!/bin/bash
# Install Linux desktop dependencies for Flutter

set -e

echo "🔧 Installing Linux desktop dependencies for Flutter..."
echo ""

# Check if running as root or with sudo
if [ "$EUID" -eq 0 ]; then
    DNF_CMD="dnf"
else
    DNF_CMD="sudo dnf"
fi

echo "📦 Installing required packages..."
$DNF_CMD install -y \
    clang \
    ninja-build \
    cmake \
    gtk3-devel \
    pkg-config \
    libx11-devel \
    libxrandr-devel \
    libxinerama-devel \
    libxcursor-devel \
    libxi-devel \
    libxext-devel \
    mesa-libGL-devel

echo ""
echo "✅ Dependencies installed!"
echo ""
echo "🔍 Verifying installation..."
flutter doctor | grep -A 10 "Linux toolchain"

echo ""
echo "✅ Ready to run Linux desktop app!"
echo "   Run: cd mobile && ./start_app.sh linux"
