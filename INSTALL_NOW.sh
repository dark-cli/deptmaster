#!/bin/bash
# Install Linux desktop dependencies for Flutter

echo "🔧 Installing Linux desktop dependencies..."
echo ""
echo "This will install:"
echo "  - clang (C++ compiler)"
echo "  - ninja-build (build system)"
echo "  - gtk3-devel (GTK3 development libraries)"
echo ""
echo "Run this command:"
echo "  sudo dnf install -y clang ninja-build gtk3-devel"
echo ""
read -p "Press Enter to continue (or Ctrl+C to cancel)..."

sudo dnf install -y clang ninja-build gtk3-devel

echo ""
echo "✅ Installation complete!"
echo ""
echo "Now you can run:"
echo "  cd /home/max/dev/debitum/mobile"
echo "  ./start_app.sh linux"
