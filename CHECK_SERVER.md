# Check Web Server Status

## Current Status

The server appears to be running on http://localhost:8080

## How to Stop It

### Option 1: Find the Process
```bash
# Check what's using port 8080
lsof -i:8080

# Or
netstat -tlnp | grep 8080

# Or
ss -tlnp | grep 8080
```

### Option 2: Kill by Port
```bash
# Kill whatever is on port 8080
lsof -ti:8080 | xargs kill -9
```

### Option 3: Kill Python HTTP Servers
```bash
# Kill all python http servers
pkill -f "python3 -m http.server"
pkill -f "http.server 8080"
```

### Option 4: Use Helper Script
```bash
cd /home/max/dev/debitum
./STOP_SERVER.sh
```

## If Running in Terminal

If you started it in a terminal:
- Go to that terminal window
- Press `Ctrl+C`

## Verify It's Stopped

```bash
curl http://localhost:8080
```

If you get "Connection refused", it's stopped.

## Note

I won't automatically stop it - you control the server. Use the commands above when you want to stop it.
