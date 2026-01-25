# Running Rust Server Directly (Development Mode)

For faster development and testing, you can run the Rust server directly on your machine instead of rebuilding Docker containers.

## Prerequisites

1. **Cargo installed** (Rust toolchain) - ✅ Already installed at `/home/max/.cargo/bin/cargo`
2. **PostgreSQL and Redis running in Docker** - These need to be running for the server to connect

## Quick Start

### Step 1: Make sure database services are running
```bash
cd /home/max/dev/debitum/backend
docker-compose up -d postgres redis
```

### Step 2: Stop the Docker API container (if running)
```bash
docker-compose stop api
# Or if you want to keep it but use different port:
# Just run dev server on different port (see below)
```

### Step 3: Run the development server
```bash
cd /home/max/dev/debitum
./scripts/run-server-dev.sh
```

The server will start on `http://localhost:8000` by default.

## Configuration

The script uses these defaults (can be overridden with environment variables):
- `DATABASE_URL`: `postgresql://debt_tracker:dev_password@localhost:5432/debt_tracker`
- `REDIS_URL`: `redis://localhost:6379`
- `PORT`: `8000`
- `RUST_LOG`: `debug`

### Custom Configuration

You can override any setting:
```bash
PORT=8001 RUST_LOG=info ./scripts/run-server-dev.sh
```

Or create a `.env` file in `backend/rust-api/` directory:
```bash
DATABASE_URL=postgresql://debt_tracker:dev_password@localhost:5432/debt_tracker
REDIS_URL=redis://localhost:6379
PORT=8000
RUST_LOG=debug
```

## Auto-reload (Optional)

For automatic reload on code changes, install `cargo-watch`:
```bash
cargo install cargo-watch
```

The script will automatically use it if available.

## Benefits

- ⚡ **Much faster** - No Docker rebuild (saves ~10-15 seconds per change)
- 🔄 **Auto-reload** - With cargo-watch, changes reload automatically
- 🐛 **Better debugging** - Direct access to logs and debugging tools
- 📝 **Easier testing** - Quick iteration cycle

## Troubleshooting

### "Connection refused" errors
- Make sure PostgreSQL and Redis are running: `docker-compose ps`
- Check they're accessible: `docker-compose up -d postgres redis`

### Port already in use
- Stop the Docker API container: `docker-compose stop api`
- Or use a different port: `PORT=8001 ./scripts/run-server-dev.sh`

### Compilation errors
- Make sure you're in the right directory: `cd backend/rust-api`
- Try cleaning: `cargo clean && cargo build`
