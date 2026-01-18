# Development vs Production Mode

## Current Setup: Production Mode (No Hot Reload)

**What you're using now:**
```bash
./start_app.sh  # or ./RUN_WEB_APP.sh
```

This:
- Builds static files (`flutter build web`)
- Serves with Python HTTP server
- **No hot reload** - must rebuild after changes

## New Option: Development Mode (Hot Reload ✅)

**New script for development:**
```bash
./run_dev.sh
```

This:
- Uses Flutter's built-in web server
- **Supports hot reload** (press `r` in terminal)
- **Supports hot restart** (press `R` in terminal)
- Faster development cycle

## When to Use Each

### Development Mode (`./run_dev.sh`)
✅ Use when:
- Actively developing/editing code
- Want fast feedback
- Testing UI changes
- Need hot reload

### Production Mode (`./start_app.sh`)
✅ Use when:
- Testing final build
- Checking production behavior
- Deploying to server
- Want static file serving

## Quick Comparison

| Feature | Development Mode | Production Mode |
|---------|----------------|-----------------|
| Hot Reload | ✅ Yes | ❌ No |
| Rebuild Time | Fast (hot reload) | Slow (full rebuild) |
| Browser Refresh | Automatic | Manual |
| Production-like | ❌ No | ✅ Yes |
| Static Files | No | Yes |

## Recommendation

**For daily development:** Use `./run_dev.sh` (hot reload)  
**For final testing:** Use `./start_app.sh` (production build)
