# Admin Panel Troubleshooting

## Issue: http://localhost:8000/ Not Working

### Solution

The root path `/` redirects to `/admin`. Use one of these URLs:

1. **Admin Panel** (recommended):
   ```
   http://localhost:8000/admin
   ```

2. **Health Check**:
   ```
   http://localhost:8000/health
   ```

### Check if Server is Running

1. **Check port 8000**:
   ```bash
   lsof -ti:8000
   # Should show a process ID if server is running
   ```

2. **Test health endpoint**:
   ```bash
   curl http://localhost:8000/health
   # Should return: "OK"
   ```

3. **Check server process**:
   ```bash
   ps aux | grep "debt-tracker-api"
   # Should show the Rust server process
   ```

### Start the Server

If the server is not running:

```bash
cd /home/max/dev/debitum
./START_SERVER.sh
```

Wait for the message:
```
Server listening on http://0.0.0.0:8000
```

### Available Routes

| Route | Description |
|-------|-------------|
| `/` | Redirects to `/admin` |
| `/admin` | Admin panel HTML interface |
| `/health` | Health check endpoint |
| `/api/admin/contacts` | Get all contacts (JSON) |
| `/api/admin/transactions` | Get all transactions (JSON) |
| `/api/admin/events` | Get all events (JSON) |
| `/api/admin/projections/status` | Get projection status (JSON) |
| `/api/contacts` | Create contact (POST) |
| `/api/transactions` | Create transaction (POST) |
| `/ws` | WebSocket connection |

### Common Issues

#### 1. Port Already in Use

If you see "Address already in use":
```bash
# Kill process on port 8000
lsof -ti:8000 | xargs kill -9

# Or use the start script which handles this
./START_SERVER.sh
```

#### 2. Database Not Running

If you see database connection errors:
```bash
# Start Docker services
cd backend
docker-compose up -d
```

#### 3. Server Crashed

Check server logs in the terminal where you ran `./START_SERVER.sh` for error messages.

#### 4. Browser Cache

Try:
- Hard refresh: `Ctrl+Shift+R` (Linux) or `Cmd+Shift+R` (Mac)
- Clear browser cache
- Try incognito/private mode

### Testing with curl

```bash
# Health check
curl http://localhost:8000/health

# Get contacts (JSON)
curl http://localhost:8000/api/admin/contacts

# Get transactions (JSON)
curl http://localhost:8000/api/admin/transactions
```

### Next Steps

Once the server is running:
1. Open browser: `http://localhost:8000/admin`
2. You should see the admin panel interface
3. Click tabs to view Events, Contacts, Transactions
