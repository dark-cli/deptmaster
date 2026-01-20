# Running Flutter App on Android Emulator

## Step 1: Install Android Studio (if not already installed)

If you don't have Android Studio installed:

```bash
# On Fedora
sudo dnf install android-studio
```

Or download from: https://developer.android.com/studio

## Step 2: Create an Android Virtual Device (AVD)

### Option A: Using Android Studio GUI

1. **Open Android Studio**
2. **Go to Tools → Device Manager** (or click the Device Manager icon in the toolbar)
3. **Click "Create Device"**
4. **Select a device definition** (e.g., "Pixel 5" or "Pixel 6")
5. **Select a system image**:
   - Choose a recent API level (e.g., API 33, 34, or 35)
   - If you see "Download" next to an image, click it to download
   - Recommended: **API 33 (Android 13)** or **API 34 (Android 14)**
6. **Click "Next"** and then **"Finish"**

### Option B: Using Command Line (avdmanager)

```bash
# List available system images
sdkmanager --list | grep "system-images"

# Install a system image (example for API 33)
sdkmanager "system-images;android-33;google_apis;x86_64"

# Create AVD
avdmanager create avd -n "pixel_5_api33" -k "system-images;android-33;google_apis;x86_64" -d "pixel_5"
```

## Step 3: Start the Emulator

### Option A: From Android Studio
- Open **Device Manager** in Android Studio
- Click the **▶️ Play button** next to your AVD

### Option B: From Command Line

```bash
# List available emulators
flutter emulators

# Launch a specific emulator
flutter emulators --launch <emulator_id>

# Or use emulator command directly
emulator -avd <avd_name> &
```

### Option C: Using Android Studio's emulator command

```bash
# Find your AVD name first
emulator -list-avds

# Launch it
emulator -avd <avd_name> &
```

## Step 4: Verify Emulator is Running

```bash
flutter devices
```

You should see your emulator listed, for example:
```
Android SDK built for x86_64 (mobile) • emulator-5554 • android-x86 • Android 13 (API 33)
```

## Step 5: Run Your Flutter App

Once the emulator is running:

```bash
cd /home/max/dev/debitum/mobile

# Make sure dependencies are installed
flutter pub get

# Generate Hive adapters (if needed)
flutter pub run build_runner build --delete-conflicting-outputs

# Run on the emulator
flutter run -d android
```

Or if you have multiple devices, specify the emulator:

```bash
flutter run -d emulator-5554
```

## Quick Start (Once Emulator is Set Up)

```bash
# 1. Start emulator (if not already running)
flutter emulators --launch <emulator_id>

# 2. Wait for emulator to boot (30-60 seconds)

# 3. Run the app
cd /home/max/dev/debitum/mobile
flutter run -d android
```

## API Configuration for Android Emulator

The app is already configured to use the correct API URL for Android emulator:
- **Android Emulator**: `http://10.0.2.2:8000/api/admin` (already set in `api_service.dart`)
- This is a special IP that the emulator uses to access `localhost` on your host machine

**Make sure your backend is running:**
```bash
cd /home/max/dev/debitum/backend/rust-api
DATABASE_URL="postgresql://debt_tracker:dev_password@localhost:5432/debt_tracker" \
PORT=8000 cargo run
```

## Troubleshooting

### No emulators found
- Make sure you've created at least one AVD in Android Studio
- Check: `flutter emulators` should list your AVDs

### Emulator won't start
- Check if virtualization is enabled in BIOS (for Intel/AMD)
- Try: `emulator -avd <name> -verbose` to see error messages
- Make sure you have enough RAM (emulator needs 2-4GB)

### App won't install on emulator
- Make sure emulator is fully booted (wait for home screen)
- Check: `adb devices` should show the emulator
- Try: `flutter clean && flutter pub get`

### Can't connect to API from emulator
- Backend must be running on `localhost:8000`
- Emulator uses `10.0.2.2` to access host's `localhost`
- Check: `curl http://localhost:8000/health` from your computer

### Slow emulator performance
- Use x86_64 system images (faster than ARM)
- Enable hardware acceleration in AVD settings
- Allocate more RAM to emulator (2-4GB recommended)

## Alternative: Use Physical Android Device

If you prefer using a physical device:

1. **Enable Developer Options** on your phone:
   - Go to Settings → About Phone
   - Tap "Build Number" 7 times

2. **Enable USB Debugging**:
   - Settings → Developer Options → USB Debugging

3. **Connect via USB** and run:
   ```bash
   flutter run -d android
   ```

4. **For API connection**, you'll need to use your computer's IP address instead of `10.0.2.2`:
   - Find your IP: `hostname -I` or `ip addr show`
   - Update `api_service.dart` to use `http://YOUR_IP:8000/api/admin`
