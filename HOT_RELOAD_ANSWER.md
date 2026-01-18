# Hot Reload for Flutter Web

## Current Setup: ❌ No Hot Reload

**What you're using now:**
- `flutter build web` - creates static files
- `python3 -m http.server` - serves static files
- **Must rebuild** after every code change
- **Must refresh browser** manually

## Solution: Use Development Mode ✅

I've updated your `start_app.sh` script to support hot reload!

### Option 1: Development Mode (Hot Reload)

```bash
cd /home/max/dev/debitum/mobile
./start_app.sh web dev
```

**Features:**
- ✅ Hot reload (press `r` in terminal)
- ✅ Hot restart (press `R` in terminal)
- ✅ Fast development cycle
- ✅ No manual rebuild needed

### Option 2: Production Mode (Current)

```bash
cd /home/max/dev/debitum/mobile
./start_app.sh web prod
# or just
./start_app.sh web
```

**Features:**
- ✅ Production-like build
- ✅ Static file serving
- ❌ No hot reload (must rebuild)

## Quick Comparison

| Mode | Command | Hot Reload | Rebuild Time |
|------|---------|------------|--------------|
| **Development** | `./start_app.sh web dev` | ✅ Yes | Instant (hot reload) |
| **Production** | `./start_app.sh web prod` | ❌ No | ~30 seconds (full rebuild) |

## Recommendation

**For development:** Use `./start_app.sh web dev`  
**For testing production:** Use `./start_app.sh web prod`

## Try It Now!

1. Stop current server (Ctrl+C if running)
2. Run: `./start_app.sh web dev`
3. Make a code change
4. Press `r` in terminal
5. See changes instantly! 🎉
