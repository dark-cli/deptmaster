# Linux Desktop App Setup

## Dependencies Installed

For Flutter Linux desktop development, you need:
- ✅ `clang` - C++ compiler
- ✅ `ninja-build` - Build system
- ✅ `cmake` - Build configuration (already installed)
- ✅ `gtk3-devel` - GTK3 development libraries
- ✅ `g++` - C++ compiler (already installed)

## Running the App

### Option 1: Using the script
```bash
cd /home/max/dev/debitum/mobile
./start_app.sh linux
```

### Option 2: Direct command
```bash
cd /home/max/dev/debitum/mobile
export PATH="$PATH:$HOME/flutter/bin"
flutter run -d linux
```

## Hot Reload

The Linux desktop app **supports hot reload**:
- Press `r` in terminal for hot reload
- Press `R` in terminal for hot restart
- Press `q` to quit

## Troubleshooting

If you get build errors:
1. Check dependencies: `flutter doctor`
2. Install missing packages: `sudo dnf install clang ninja-build gtk3-devel`
3. Clean build: `flutter clean && flutter pub get`

## Benefits of Linux Desktop

- ✅ Native performance
- ✅ Hot reload support
- ✅ Native look and feel
- ✅ Better debugging
- ✅ No browser limitations
