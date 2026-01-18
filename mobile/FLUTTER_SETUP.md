# Flutter Setup Complete! ✅

## What's Done

✅ **Flutter Installed** - Flutter is now in `~/flutter/`  
✅ **Web Support Enabled** - Flutter web is configured  
✅ **Dependencies Installed** - All packages are ready  
✅ **Hive Adapters Generated** - Local storage ready  
✅ **Platform Detection** - Auto-detects web/mobile and uses correct API URL  
✅ **Android URIs Hidden** - Contact URIs hidden in web view  

## Running the App

### Add Flutter to PATH (Permanent)

Add this to your `~/.zshrc`:
```bash
export PATH="$PATH:$HOME/flutter/bin"
```

Then reload:
```bash
source ~/.zshrc
```

### Run on Web (Chrome)

If Chrome is installed:
```bash
cd /home/max/dev/debitum/mobile
export PATH="$PATH:$HOME/flutter/bin"
flutter run -d chrome --web-port=8080
```

### Run on Linux Desktop

```bash
cd /home/max/dev/debitum/mobile
export PATH="$PATH:$HOME/flutter/bin"
flutter run -d linux
```

### Run on Android

```bash
flutter run -d android
```

### Run on iOS (Mac only)

```bash
flutter run -d ios
```

## Features

✅ **Same Codebase** - One app works for web, Android, iOS, and Linux  
✅ **Auto API URL** - Automatically uses:
   - `localhost:8000` for web/Linux/iOS
   - `10.0.2.2:8000` for Android emulator  
✅ **Hides Android URIs** - Phone numbers starting with `content://` are hidden in web  
✅ **Shows Your Data** - 59 contacts and 249 transactions from your Debitum backup  

## Quick Start

```bash
# Add Flutter to PATH (one time)
echo 'export PATH="$PATH:$HOME/flutter/bin"' >> ~/.zshrc
source ~/.zshrc

# Run the app
cd /home/max/dev/debitum/mobile
flutter run -d linux  # or chrome, android, ios
```

## Troubleshooting

**Chrome not found:**
- Install Chrome: `sudo dnf install google-chrome-stable` (Fedora)
- Or use Linux desktop: `flutter run -d linux`
- Or use Firefox: Install Flutter web support for Firefox

**Flutter not found:**
- Make sure PATH includes Flutter: `echo $PATH | grep flutter`
- Run: `export PATH="$PATH:$HOME/flutter/bin"`

**Can't connect to API:**
- Make sure backend is running: `curl http://localhost:8000/health`
- For Android emulator, the app automatically uses `10.0.2.2`

## Next Steps

- [ ] Install Chrome for web development
- [ ] Set up Android Studio for mobile development
- [ ] Add authentication
- [ ] Add create/edit/delete operations
