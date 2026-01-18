# Run Linux Desktop App

## Step 1: Install Dependencies

You need to install the required packages first:

```bash
sudo dnf install -y clang ninja-build gtk3-devel
```

This will install:
- `clang` - C++ compiler for Linux
- `ninja-build` - Build system
- `gtk3-devel` - GTK3 development libraries

## Step 2: Verify Installation

Check that everything is ready:

```bash
cd /home/max/dev/debitum/mobile
export PATH="$PATH:$HOME/flutter/bin"
flutter doctor
```

Look for the "Linux toolchain" section - it should show ✅ for all items.

## Step 3: Run the App

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

Once running, you can use hot reload:
- Press `r` in terminal for **hot reload**
- Press `R` in terminal for **hot restart**
- Press `q` to **quit**

## What to Expect

1. First build takes ~1-2 minutes (compiling native code)
2. A window will open with your Flutter app
3. Terminal shows hot reload commands
4. Make code changes and press `r` to see updates instantly!

## Troubleshooting

If you see errors:
- **"ninja not found"**: Install with `sudo dnf install ninja-build`
- **"clang not found"**: Install with `sudo dnf install clang`
- **"GTK3 not found"**: Install with `sudo dnf install gtk3-devel`
- **Build errors**: Try `flutter clean && flutter pub get`
