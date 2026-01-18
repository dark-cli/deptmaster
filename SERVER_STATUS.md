# Web Server Status

## Current Status

The web server is running on **http://localhost:8080**

## How to Stop It

### Quick Stop (if you want):
```bash
# Kill the process on port 8080
lsof -ti:8080 | xargs kill

# Or use the helper script
cd /home/max/dev/debitum
./STOP_SERVER.sh
```

### If Running in Terminal:
- Go to the terminal where you started it
- Press `Ctrl+C`

### Manual Check:
```bash
# See what's running on port 8080
lsof -i:8080

# Kill specific process
kill <PID>
```

## Note

Since you want to control the server yourself, I won't automatically stop it. Use the commands above when you're ready to stop it.
