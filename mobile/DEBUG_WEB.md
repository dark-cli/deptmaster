# Debug Web App Dark Screen

## Check Browser Console

Open browser developer tools (F12) and check:
1. **Console tab** - Look for JavaScript errors
2. **Network tab** - Check if API calls are failing
3. **Application tab** - Check if resources are loading

## Common Issues

### 1. CORS Error
If you see CORS errors, the backend needs to allow web origins.

### 2. API Connection Failed
Check if backend is running:
```bash
curl http://localhost:8000/health
```

### 3. JavaScript Error
Check browser console for specific errors.

## Quick Fix: Rebuild Web App

```bash
cd /home/max/dev/debitum/mobile
export PATH="$PATH:$HOME/flutter/bin"
flutter clean
flutter pub get
flutter build web
python3 -m http.server 8080 --directory build/web
```

## Or Use Linux Desktop

Install build tools and run desktop version:
```bash
sudo dnf install -y cmake ninja-build clang gtk3-devel pkg-config
cd /home/max/dev/debitum/mobile
export PATH="$PATH:$HOME/flutter/bin"
flutter run -d linux
```
