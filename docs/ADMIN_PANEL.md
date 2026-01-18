# Web Admin Panel Guide

## Overview

The Debt Tracker application includes a web-based admin panel for monitoring and debugging data. The admin panel provides a simple HTML interface to view events, contacts, transactions, and projection status.

## Accessing the Admin Panel

### Prerequisites

1. **Backend server must be running**
   ```bash
   ./START_SERVER.sh
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
- View status of all projections
- Check projection health
- Verify event processing

**API Endpoint**: `GET /api/admin/projections/status`

## API Endpoints

All admin endpoints are prefixed with `/api/admin/`:

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/admin/events` | GET | Get all events from event store |
| `/api/admin/contacts` | GET | Get all contacts from projection |
| `/api/admin/transactions` | GET | Get all transactions from projection |
| `/api/admin/projections/status` | GET | Get projection status |

## Example: Direct API Access

You can also access the API directly using `curl`:

```bash
# Get all contacts
curl http://localhost:8000/api/admin/contacts

# Get all transactions
curl http://localhost:8000/api/admin/transactions

# Get all events
curl http://localhost:8000/api/admin/events

# Get projection status
curl http://localhost:8000/api/admin/projections/status
```

## Troubleshooting

### Admin Panel Not Loading

1. **Check if server is running**:
   ```bash
   curl http://localhost:8000/health
   # Should return: "OK"
   ```

2. **Check server logs**:
   - Look for errors in the terminal where `START_SERVER.sh` is running
   - Verify database connection is working

3. **Check port**:
   - Default port is 8000
   - Can be changed via `PORT` environment variable
   - Check `.env` file or environment variables

### CORS Issues

- Admin panel should work from `localhost:8000`
- CORS is configured to be permissive in development
- If accessing from different origin, check CORS settings

## Development

The admin panel HTML is located at:
```
backend/rust-api/static/admin/index.html
```

The admin panel handler is in:
```
backend/rust-api/src/handlers/admin.rs
```

## Security Note

⚠️ **Important**: The admin panel is currently **unauthenticated** and should only be used in development or behind proper authentication in production.

For production deployment:
- Add authentication (JWT tokens)
- Restrict access to authorized users only
- Consider IP whitelisting
- Use HTTPS
