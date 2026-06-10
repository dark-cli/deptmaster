# Debt Tracker Web Client

Simple HTML/JavaScript web client for Debt Tracker.

## Features

- ✅ View all contacts with net balances
- ✅ View all transactions
- ✅ Real-time statistics
- ✅ Beautiful, modern UI
- ✅ Responsive design
- ✅ Pull to refresh

## Running

### Option 1: Python HTTP Server (Simple)

```bash
cd backend/rust-api/static/app
python3 -m http.server 8080
```

Then open: http://localhost:8080

### Option 2: Any Web Server

Just serve the `web/app` directory with any web server:
- Nginx
- Apache
- Node.js `http-server`
- etc.

## API Connection

The app connects to: `http://localhost:8000/api/admin`

Make sure the backend is running:
```bash
cd backend/rust-api
DATABASE_URL="postgresql://debt_tracker:dev_password@localhost:5432/debt_tracker" \
PORT=8000 cargo run
```

## Features

### Contacts View
- Shows all contacts
- Displays net balance per contact
- Color-coded:
  - 🟢 Green = They owe you
  - 🔴 Red = You owe them
  - ⚪ Gray = Settled (zero)

### Transactions View
- Shows all transactions
- Displays contact name, amount, date
- Color-coded by direction (owed/lent)

### Statistics
- Total contacts
- Total transactions
- Net balance across all contacts

## Troubleshooting

**Can't connect to API:**
- Make sure backend is running on port 8000
- Check browser console for CORS errors
- Verify: `curl http://localhost:8000/api/admin/contacts`

**Data not showing:**
- Check browser console for errors
- Try refresh button
- Verify backend is running

## Next Steps

- [ ] Add create/edit/delete operations
- [ ] Add authentication
- [ ] Add search functionality
- [ ] Add filters
- [ ] Add charts/graphs
