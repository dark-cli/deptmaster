---
tags:
  - database
  - docker
  - setup
  - operations
  - scripts
---

# Database Setup & Management Script

**Quick reference for running the database using the management script.**

---

## Quick Start (90 seconds)

```bash
# Full system reset: database + migrations + admin user + default data
./scripts/manage.sh reset-database-complete

# Done! Database is ready at: postgresql://debt_tracker:dev_password@localhost:5432/debt_tracker
```

Default credentials after reset:
- Admin: `admin` / `admin123`
- User: `max` / `12345678`

---

## Management Script

**Location:** `./scripts/manage.sh`

**What it does:**
- Manages PostgreSQL + Redis Docker containers
- Handles database migrations and schema setup
- Creates default users and admin accounts
- Starts/stops API server
- Rebuilds projections from events
- Imports backups

---

## Common Commands

### Setup & Reset

| Command | What it does |
|---------|-------------|
| `reset-database-complete` | **Recommended for first run.** Starts Docker, resets DB, runs migrations, creates admin user |
| `reset-database-only` | Reset database (keep server running) |
| `start-docker-services` | Start PostgreSQL + Redis (no API) |
| `stop-docker-services` | Stop PostgreSQL + Redis |

### Server Management

| Command | What it does |
|---------|-------------|
| `start-server-docker` | Start API server (Docker DB + local API) |
| `start-server-direct` | Start API server directly (cargo run, live reload) |
| `stop-server` | Stop API server |
| `restart-server` | Restart API server |

### Status & Debugging

| Command | What it does |
|---------|-------------|
| `status` | Show what's running (Docker services, API server) |
| `logs` | Tail API server logs |
| `rebuild-database-projections` | Rebuild projections from events |

---

## Development Workflow

### Scenario 1: Fresh Start

```bash
# One command does everything
./scripts/manage.sh reset-database-complete

# Now you have:
# ✅ PostgreSQL running on localhost:5432
# ✅ Redis running on localhost:6379
# ✅ Database created and migrated
# ✅ Admin user created (admin / admin123)
```

### Scenario 2: Reset Between Test Runs

```bash
# Clear database, keep server running
./scripts/manage.sh reset-database-only
```

### Scenario 3: Full Development Setup

```bash
# Terminal 1: Start everything
./scripts/manage.sh reset-database-complete

# Terminal 2: Start API server
./scripts/manage.sh start-server-docker

# Terminal 3: Watch logs
./scripts/manage.sh logs

# Terminal 4: Run tests
cd crates/server && cargo test
```

### Scenario 4: Live Reloading Development

```bash
# Start database
./scripts/manage.sh start-docker-services

# Start API server with auto-reload (if cargo-watch installed)
USE_CARGO_WATCH=1 ./scripts/manage.sh start-server-direct

# Ctrl+C to stop, edits automatically trigger rebuild
```

---

## What Gets Created

After `reset-database-complete`:

**Docker Containers:**
- PostgreSQL 14 (port 5432)
- Redis 7 (port 6379)

**Database:**
- Name: `debt_tracker`
- User: `debt_tracker`
- Password: `dev_password`

**Default Users:**
- Admin: `admin` / `admin123` (superuser)
- Regular: `max` / `12345678` (demo user)

**Migrations:**
All 21 migrations run automatically (001-021, organized by phase)

---

## Flags & Options

```bash
# Verbose output
./scripts/manage.sh reset-database-complete --verbose

# Skip server build (use existing binary)
./scripts/manage.sh start-server-docker --skip-server-build

# View available commands
./scripts/manage.sh --help
```

---

## Verify It Works

```bash
# Check services are running
./scripts/manage.sh status

# Connect to database
psql -h localhost -U debt_tracker -d debt_tracker
# Password: dev_password

# Useful queries:
\dt                    # List tables
SELECT * FROM users_projection;
SELECT * FROM wallets;
\q                     # Quit
```

---

## Troubleshooting

### "Port 5432 already in use"

```bash
./scripts/manage.sh stop-docker-services
sleep 2
./scripts/manage.sh reset-database-complete
```

### "Docker not running"

Start Docker Desktop or Docker daemon, then retry.

### "Containers exited with error"

```bash
# Full reset
docker-compose down -v
./scripts/manage.sh reset-database-complete
```

### "Database seems corrupted"

```bash
# Nuclear option - remove everything and start fresh
./scripts/manage.sh stop-docker-services
docker-compose down -v
./scripts/manage.sh reset-database-complete
```

---

## Under the Hood

**What the script does:**

1. Checks Docker is running
2. Starts PostgreSQL + Redis containers
3. Waits for services to be healthy (10s timeout)
4. Stops any running API server
5. Drops old database (if exists)
6. Creates fresh database
7. Runs all migrations (001-021)
8. Creates admin user (`admin` / `admin123`)
9. Creates default user (`max` / `12345678`)
10. Returns database ready to use

**File:** `./scripts/manage.sh` (2500+ lines, handles all infrastructure)

**Docker config:** `./docker-compose.yml`

---

## Related

- [[migration-guide.md]] — Database schema and migrations
- [[architecture.md]] — Event sourcing design
- [[reading-guide.md]] — How to understand the codebase

