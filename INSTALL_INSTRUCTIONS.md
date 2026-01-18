# Install Linux Desktop Dependencies

## The Problem

You're missing these required packages:
- ❌ `clang` - C++ compiler
- ❌ `ninja-build` - Build system  
- ❌ `gtk3-devel` - GTK3 development libraries

## The Solution

Run this command to install everything:

```bash
sudo dnf install -y clang ninja-build gtk3-devel
```

## After Installation

1. **Verify installation:**
   ```bash
   cd /home/max/dev/debitum/mobile
   export PATH="$PATH:$HOME/flutter/bin"
   flutter doctor
   ```
   
   Look for "Linux toolchain" - should show ✅ for all items.

2. **Run the app:**
   ```bash
   ./start_app.sh linux
   ```

## What Each Package Does

- **clang**: C++ compiler needed to build native Linux code
- **ninja-build**: Fast build system used by Flutter
- **gtk3-devel**: GTK3 GUI library headers for building desktop apps

## Alternative: Check What's Missing

If you want to see what's installed:
```bash
rpm -q clang ninja-build gtk3-devel
```

If a package shows "not installed", install it with the command above.
