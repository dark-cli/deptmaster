# Quick Start - Run the App

## Simple Script

Just run:

```bash
cd /home/max/dev/debitum/mobile
./start_app.sh
```

This will:
1. Build the Flutter web app
2. Start a web server on port 8080
3. Open http://localhost:8080 in your browser

## Options

### Web (Default)
```bash
./start_app.sh web
# or just
./start_app.sh
```

### Linux Desktop
```bash
./start_app.sh linux
```

(Requires: `sudo dnf install -y cmake ninja-build clang gtk3-devel pkg-config`)

## Make Sure Backend is Running

Before running the app, start the backend:

```bash
cd /home/max/dev/debitum/backend/rust-api
DATABASE_URL="postgresql://debt_tracker:dev_password@localhost:5432/debt_tracker" \
PORT=8000 cargo run
```

## What's Fixed

✅ Removed `isSettled` and `settledAt` from Transaction model  
✅ Fixed Hive initialization for web  
✅ Web app loads data directly from API  
✅ All compilation errors fixed  

## Troubleshooting

**Flutter not found:**
```bash
export PATH="$PATH:$HOME/flutter/bin"
```

**Build fails:**
```bash
flutter clean
flutter pub get
./start_app.sh
```

**Backend not running:**
Check: `curl http://localhost:8000/health`
