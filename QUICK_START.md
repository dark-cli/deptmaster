# Quick Start Guide

## 1. Start Backend Server

```bash
cd /home/max/dev/debitum
./START_SERVER.sh
```

This will:
- ✅ Kill any existing servers on port 8000
- ✅ Start the Rust API server
- ✅ Show logs

**Keep this terminal open!**

## 2. Start Flutter Web App (New Terminal)

Open a **new terminal** and run:

```bash
cd /home/max/dev/debitum/mobile
./start_app.sh
```

This will:
- ✅ Build the Flutter web app
- ✅ Start web server on port 8080

## 3. Open in Browser

- **Web App**: http://localhost:8080
- **Admin Panel**: http://localhost:8000/admin

## Stop Servers

**Backend:**
- Press `Ctrl+C` in the backend terminal

**Web App:**
- Press `Ctrl+C` in the web app terminal

Or kill all:
```bash
lsof -ti:8000 | xargs kill -9
lsof -ti:8080 | xargs kill -9
```

## Troubleshooting

**Port 8000 in use:**
```bash
./START_SERVER.sh  # This kills existing processes
```

**Port 8080 in use:**
```bash
lsof -ti:8080 | xargs kill -9
```

**Backend not responding:**
- Check if Docker is running: `docker ps`
- Check database: `docker-compose exec postgres psql -U debt_tracker -d debt_tracker -c "SELECT COUNT(*) FROM contacts_projection;"`
