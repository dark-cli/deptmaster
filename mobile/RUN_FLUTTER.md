# Running Flutter App for Web and Mobile

## Install Flutter

### Option 1: Snap (Easiest - requires sudo password)

```bash
sudo snap install flutter --classic
flutter doctor
```

### Option 2: Manual Install (No sudo needed)

```bash
# Download Flutter to your home directory
cd ~
git clone https://github.com/flutter/flutter.git -b stable

# Add to PATH (add to ~/.zshrc to make permanent)
export PATH="$PATH:$HOME/flutter/bin"
echo 'export PATH="$PATH:$HOME/flutter/bin"' >> ~/.zshrc

# Reload shell config
source ~/.zshrc

# Verify installation
flutter doctor
```

### Option 3: Using FVM (Flutter Version Manager)

```bash
# Install FVM
dart pub global activate fvm

# Install Flutter
fvm install stable
fvm use stable

# Add to PATH
export PATH="$PATH:$HOME/.fvm/default/bin"
```

## Enable Web Support

After installing Flutter:

```bash
flutter config --enable-web
flutter doctor
```

You should see Chrome listed in devices.

## Setup the App

```bash
cd /home/max/dev/debitum/mobile

# Install dependencies
flutter pub get

# Generate Hive adapters
flutter pub run build_runner build --delete-conflicting-outputs
```

## Run the App

### For Web Browser:

```bash
flutter run -d chrome
```

Or specify a port:
```bash
flutter run -d chrome --web-port=8080
```

### For Android:

```bash
flutter run -d android
```

### For iOS (Mac only):

```bash
flutter run -d ios
```

### List Available Devices:

```bash
flutter devices
```

## Features

✅ **Auto-detects platform** - Uses correct API URL automatically:
- Web: `http://localhost:8000/api/admin`
- Android Emulator: `http://10.0.2.2:8000/api/admin`
- iOS Simulator: `http://localhost:8000/api/admin`

✅ **Hides Android contact URIs in web** - Phone numbers starting with `content://` are hidden in browser

✅ **Same codebase** - One app works for web, Android, and iOS

## Troubleshooting

**Flutter not found:**
- Make sure PATH includes Flutter: `echo $PATH | grep flutter`
- Restart terminal or run: `source ~/.zshrc`

**Web not enabled:**
- Run: `flutter config --enable-web`
- Check: `flutter devices` should show Chrome

**Dependencies missing:**
- Run: `flutter doctor` to see what's missing
- Install Chrome for web support
- Install Android Studio for Android development

**Can't connect to API:**
- Make sure backend is running: `curl http://localhost:8000/health`
- For Android emulator, use `10.0.2.2` instead of `localhost`
- For physical device, use your computer's IP address

## Quick Start

Once Flutter is installed:

```bash
cd /home/max/dev/debitum/mobile
flutter pub get
flutter pub run build_runner build --delete-conflicting-outputs
flutter run -d chrome
```

The app will open in Chrome and show your 59 contacts and 249 transactions!
