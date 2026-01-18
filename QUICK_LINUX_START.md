# Quick Start: Linux Desktop App

## Install Dependencies (One Time)

```bash
sudo dnf install -y clang ninja-build gtk3-devel
```

## Run the App

```bash
cd /home/max/dev/debitum/mobile
./start_app.sh linux
```

That's it! The app will:
1. Build (first time takes ~1-2 minutes)
2. Open in a window
3. Support hot reload (press `r` in terminal)

## Hot Reload Commands

While the app is running:
- `r` - Hot reload (fast, preserves state)
- `R` - Hot restart (full restart)
- `q` - Quit

**Much faster than rebuilding web!** 🚀
