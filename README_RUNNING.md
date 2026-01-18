# Running the Debt Tracker App

## After Disabling SELinux

Once you've disabled SELinux temporarily, run:

```bash
./START_AFTER_SELINUX.sh
```

This will:
1. Start Docker containers (PostgreSQL + Redis)
2. Create database if needed
3. Run database migrations
4. Start the Rust API server

## Quick Test

After the server starts, test it:

```bash
./TEST_APP.sh
```

Or manually:

```bash
# Health check
curl http://localhost:8000/health

# Admin panel (open in browser)
# http://localhost:8000/admin

# API endpoints
curl http://localhost:8000/api/admin/contacts
curl http://localhost:8000/api/admin/transactions
curl http://localhost:8000/api/admin/events
```

## What to Expect

1. **Server starts** - You'll see logs showing:
   - "Starting Debt Tracker API server..."
   - "Database connection pool created"
   - "Seeding dummy data..." (first time only)
   - "Background scheduler started"
   - "Server listening on http://0.0.0.0:8000"

2. **Admin Panel** - Open http://localhost:8000/admin
   - Shows statistics dashboard
   - View events, contacts, transactions
   - Auto-refreshes every 30 seconds

3. **API Endpoints** - All working:
   - `/health` - Health check
   - `/api/admin/events` - Event store
   - `/api/admin/contacts` - Contacts
   - `/api/admin/transactions` - Transactions
   - `/api/admin/projections/status` - Projection status

## Flutter Mobile App

Once server is running:

```bash
cd mobile
flutter pub get
flutter run
```

The mobile app will:
- Show dummy data locally
- Can connect to API (when configured)

## Troubleshooting

If containers don't start:
```bash
docker-compose logs postgres
docker-compose logs redis
```

If database connection fails:
```bash
docker-compose exec postgres psql -U debt_tracker -d debt_tracker -c "SELECT 1;"
```

If server doesn't start:
- Check logs in terminal
- Verify DATABASE_URL is correct
- Make sure port 8000 is available

## Next Steps

Once everything is running:
1. ✅ Test admin panel
2. ✅ Test API endpoints  
3. ✅ Run Flutter app
4. ⏳ Implement authentication
