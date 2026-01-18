# 🚀 Start the App

## One Command

```bash
cd /home/max/dev/debitum/mobile
./start_app.sh
```

That's it! The script will:
1. ✅ Check Flutter is installed
2. ✅ Build the web app
3. ✅ Start web server on port 8080
4. ✅ Show you the URL

## Prerequisites

1. **Backend running:**
   ```bash
   cd /home/max/dev/debitum/backend/rust-api
   DATABASE_URL="postgresql://debt_tracker:dev_password@localhost:5432/debt_tracker" \
   PORT=8000 cargo run
   ```

2. **Flutter in PATH:**
   ```bash
   export PATH="$PATH:$HOME/flutter/bin"
   # Or restart terminal (already added to ~/.zshrc)
   ```

## Open Browser

After running the script, open:
**http://localhost:8080**

You'll see your 59 contacts and 249 transactions! 🎉
