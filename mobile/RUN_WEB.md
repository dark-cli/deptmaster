# Running Flutter App in Browser

## Flutter Not Found

Flutter is not currently in your PATH. You need to either:

### Option 1: Install Flutter (if not installed)

1. **Download Flutter:**
   ```bash
   cd ~
   git clone https://github.com/flutter/flutter.git -b stable
   ```

2. **Add to PATH:**
   ```bash
   export PATH="$PATH:$HOME/flutter/bin"
   # Add to ~/.zshrc or ~/.bashrc to make permanent
   echo 'export PATH="$PATH:$HOME/flutter/bin"' >> ~/.zshrc
   ```

3. **Enable web support:**
   ```bash
   flutter config --enable-web
   ```

4. **Run the app:**
   ```bash
   cd /home/max/dev/debitum/mobile
   flutter pub get
   flutter pub run build_runner build --delete-conflicting-outputs
   flutter run -d chrome
   ```

### Option 2: Use Existing Flutter Installation

If Flutter is already installed somewhere:

1. **Find Flutter:**
   ```bash
   find ~ -name "flutter" -type f 2>/dev/null
   ```

2. **Add to PATH temporarily:**
   ```bash
   export PATH="$PATH:/path/to/flutter/bin"
   ```

3. **Run the app:**
   ```bash
   cd /home/max/dev/debitum/mobile
   flutter run -d chrome
   ```

### Option 3: Use Docker (Alternative)

If you prefer Docker, we can create a Dockerfile for Flutter web.

## Quick Test

Once Flutter is in PATH:

```bash
cd /home/max/dev/debitum/mobile
flutter --version
flutter devices  # Should show Chrome
flutter run -d chrome
```

The app will:
- Open in Chrome automatically
- Connect to `http://localhost:8000/api/admin`
- Show your 59 contacts and 249 transactions
- Display balances

## API Configuration

The API URL is already set to `http://localhost:8000/api/admin` for web browser.

Make sure the backend is running:
```bash
cd /home/max/dev/debitum/backend/rust-api
DATABASE_URL="postgresql://debt_tracker:dev_password@localhost:5432/debt_tracker" \
PORT=8000 cargo run
```

## Troubleshooting

**CORS errors:**
- The backend needs CORS headers for web requests
- We may need to add CORS middleware to the Rust backend

**Can't connect to API:**
- Make sure backend is running on port 8000
- Check browser console for errors
- Try: `curl http://localhost:8000/api/admin/contacts`
