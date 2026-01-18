#!/bin/bash
# Stop the web server on port 8080 (if you want to)

echo "🔍 Checking for server on port 8080..."

PID=$(lsof -ti:8080 2>/dev/null | head -1)

if [ -z "$PID" ]; then
    echo "✅ No server running on port 8080"
else
    echo "📋 Found process: $PID"
    echo ""
    echo "To stop it, run:"
    echo "  kill $PID"
    echo ""
    echo "Or kill all python http servers:"
    echo "  pkill -f 'python3 -m http.server 8080'"
    echo ""
    read -p "Do you want me to stop it? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        kill $PID 2>/dev/null
        echo "✅ Stopped server (PID: $PID)"
    else
        echo "ℹ️  Server still running - you can stop it manually"
    fi
fi
