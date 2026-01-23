# Web Admin Panel Guide

## Overview

The Debt Tracker application includes a web-based admin panel for monitoring and debugging data. The admin panel provides a simple HTML interface to view events, contacts, transactions, and projection status.

## Accessing the Admin Panel

### Prerequisites

1. **Backend server must be running**
   ```bash
   ./manage.sh start-server
   ```

2. **Server runs on port 8000 by default**
   - Admin Panel: `http://localhost:8000/admin`
   - Health Check: `http://localhost:8000/health`
   - API Base: `http://localhost:8000/api`

### Opening the Admin Panel

Simply open your web browser and navigate to:

```
http://localhost:8000/admin
```

## Admin Panel Features

### 1. Events View
- View all events from the event store
- See complete audit trail of all changes
- Events are immutable and append-only
- Filter by event type, aggregate type, date range
- Click chart points to filter events

**API Endpoint**: `GET /api/admin/events`

### 2. Contacts View
- View all contacts from the `contacts_projection`
- See contact details: name, phone, email, notes
- View creation and update timestamps

**API Endpoint**: `GET /api/admin/contacts`

### 3. Transactions View
- View all transactions from the `transactions_projection`
- See transaction details: amount, currency, direction, description
- View associated contact IDs
- See transaction dates and timestamps

**API Endpoint**: `GET /api/admin/transactions`

### 4. Projection Status
- View projection rebuild status
- See last processed event ID
- Check if projections are up to date
- Manually trigger projection rebuild

**API Endpoint**: `GET /api/admin/projections/status`

### 5. Statistics Dashboard
- View debt chart (monthly view)
- See total contacts and transactions
- View balance statistics

## Troubleshooting

### Issue: http://localhost:8000/ Not Working

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

4. **Check server status**:
   ```bash
   ./manage.sh status
   ```

### Start the Server

If the server is not running:

```bash
./manage.sh start-server
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
| `/api/admin/projections/rebuild` | Rebuild projections (POST) |
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
./manage.sh start-server
```

#### 2. Database Not Running

If you see database connection errors:
```bash
# Start Docker services
./manage.sh start-services
```

#### 3. Server Crashed

Check server logs:
```bash
./manage.sh logs
```

Or check the terminal where you ran `./manage.sh start-server` for error messages.

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

# Get events (JSON)
curl http://localhost:8000/api/admin/events
```

### Next Steps

Once the server is running:
1. Open browser: `http://localhost:8000/admin`
2. You should see the admin panel interface
3. Click tabs to view Events, Contacts, Transactions
4. Use filters to narrow down results
5. Click chart points to filter events by date

## Related Documentation

- [API Reference](./API_REFERENCE.md) - Complete API documentation
- [Architecture](./ARCHITECTURE.md) - System architecture overview
- [Deployment](./DEPLOYMENT.md) - Production deployment guide
