# Installing Flutter for Web and Mobile

## Quick Install (Recommended)

### Option 1: Using Snap (Easiest)

```bash
sudo snap install flutter --classic
flutter doctor
```

### Option 2: Manual Install

```bash
# Download Flutter
cd ~
git clone https://github.com/flutter/flutter.git -b stable

# Add to PATH
export PATH="$PATH:$HOME/flutter/bin"
echo 'export PATH="$PATH:$HOME/flutter/bin"' >> ~/.zshrc

# Verify
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

## Verify Installation

```bash
flutter --version
flutter devices  # Should show Chrome
```

## Run the App

Once Flutter is installed:

```bash
cd /home/max/dev/debitum/mobile
flutter pub get
flutter pub run build_runner build --delete-conflicting-outputs
flutter run -d chrome  # For web
flutter run -d android # For Android
flutter run -d ios     # For iOS
```

## Troubleshooting

**Flutter not found:**
- Make sure PATH includes Flutter bin directory
- Restart terminal or run: `source ~/.zshrc`

**Web not enabled:**
- Run: `flutter config --enable-web`
- Check: `flutter devices` should show Chrome

**Dependencies:**
- Chrome browser (for web)
- Android Studio (for Android)
- Xcode (for iOS, Mac only)
