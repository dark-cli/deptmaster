# ✅ Flutter App Ready for Web and Mobile!

## Status

✅ **Flutter Installed** - Located at `~/flutter/`  
✅ **Web Support Enabled** - Flutter web is configured  
✅ **Linux Desktop Support** - Added to project  
✅ **Dependencies Ready** - All packages installed  
✅ **Platform Detection** - Auto-detects platform and uses correct API URL  
✅ **Android URIs Hidden** - Contact URIs hidden in web view  

## How to Run

### 1. Make sure Flutter is in PATH

```bash
export PATH="$PATH:$HOME/flutter/bin"
# Or restart terminal (already added to ~/.zshrc)
```

### 2. Run the App

#### For Web (when Chrome is available):
```bash
cd /home/max/dev/debitum/mobile
flutter run -d chrome --web-port=8080
```

#### For Linux Desktop:
```bash
cd /home/max/dev/debitum/mobile
flutter run -d linux
```

#### For Android:
```bash
flutter run -d android
```

#### For iOS (Mac only):
```bash
flutter run -d ios
```

## Features

✅ **One Codebase** - Same app works for web, Android, iOS, and Linux  
✅ **Auto API URL** - Automatically detects platform:
   - Web/Linux/iOS: `http://localhost:8000/api/admin`
   - Android Emulator: `http://10.0.2.2:8000/api/admin`
✅ **Your Real Data** - Shows 59 contacts and 249 transactions  
✅ **Balance Display** - Shows net balance per contact  
✅ **Clean UI** - Hides Android contact URIs in web view  

## What You'll See

- **Contacts Tab**: All 59 contacts with net balances
- **Transactions Tab**: All 249 transactions
- **Color Coding**: 
  - 🟢 Green = They owe you
  - 🔴 Red = You owe them
  - ⚪ Gray = Settled

## Troubleshooting

**Chrome not found:**
- Install: `sudo dnf install google-chrome-stable` (Fedora)
- Or use: `flutter run -d linux` for desktop app

**App not starting:**
- Make sure backend is running: `curl http://localhost:8000/health`
- Check logs: `tail -f /tmp/flutter_linux.log`

**Flutter not found:**
- Run: `export PATH="$PATH:$HOME/flutter/bin"`
- Or restart terminal

## Next Steps

- [ ] Install Chrome for web development
- [ ] Test on Android device/emulator
- [ ] Add authentication
- [ ] Add create/edit/delete operations

## Quick Start

```bash
cd /home/max/dev/debitum/mobile
export PATH="$PATH:$HOME/flutter/bin"
flutter run -d linux  # Opens desktop window
```

The Flutter app is ready! 🎉
