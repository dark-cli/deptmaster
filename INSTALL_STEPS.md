# Step-by-Step: Install Linux Dependencies

## Current Status

The error shows that `ninja` and `clang++` are not found. You need to install them.

## Step 1: Install Packages

Open a terminal and run:

```bash
sudo dnf install -y clang ninja-build gtk3-devel
```

**Note**: You'll need to enter your password for `sudo`.

## Step 2: Verify Installation

After installation, verify the packages are available:

```bash
which clang++ ninja
pkg-config --exists gtk+-3.0 && echo "GTK3 OK" || echo "GTK3 missing"
```

You should see paths for `clang++` and `ninja`, and "GTK3 OK".

## Step 3: Clean Flutter Build

Before running again, clean the build:

```bash
cd /home/max/dev/debitum/mobile
export PATH="$PATH:$HOME/flutter/bin"
flutter clean
flutter pub get
```

## Step 4: Run the App

Now try running again:

```bash
./start_app.sh linux
```

## If Still Not Working

If you still get errors after installing:

1. **Check Flutter doctor:**
   ```bash
   flutter doctor -v
   ```
   Look at the "Linux toolchain" section.

2. **Check if packages are actually installed:**
   ```bash
   rpm -q clang ninja-build gtk3-devel
   ```

3. **Try finding ninja manually:**
   ```bash
   find /usr -name "ninja" 2>/dev/null
   ```

4. **If ninja is in a non-standard location**, you might need to add it to PATH or create a symlink.

## Alternative: Check Package Names

Sometimes package names differ. Try:

```bash
dnf search ninja
dnf search clang
```

Make sure you install the exact package names that Flutter expects.
