# Install Linux Desktop Build Tools

To run the Flutter Linux desktop app, you need to install build tools:

## Install Required Tools

```bash
sudo dnf install -y cmake ninja-build clang gtk3-devel pkg-config
```

Or if you prefer to install individually:

```bash
sudo dnf install -y cmake
sudo dnf install -y ninja-build
sudo dnf install -y clang
sudo dnf install -y gtk3-devel
sudo dnf install -y pkg-config
```

## Verify Installation

```bash
cmake --version
ninja --version
clang++ --version
pkg-config --version
```

## Then Run Flutter App

```bash
cd /home/max/dev/debitum/mobile
export PATH="$PATH:$HOME/flutter/bin"
flutter run -d linux
```

## Alternative: Fix Web App

If you prefer to use the web version, we can debug the dark screen issue. The problem might be:
- JavaScript errors in browser console
- CORS issues
- API connection problems

Let me know which you prefer!
