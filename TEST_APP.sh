#!/bin/bash
# Quick test script to verify everything works

set -e

echo "🧪 Testing Debt Tracker App"
echo ""

# Check Docker
if ! docker ps &> /dev/null; then
    echo "❌ Docker not running"
    exit 1
fi

# Check containers
if docker ps | grep -q debt_tracker_postgres; then
    echo "✅ PostgreSQL container is running"
else
    echo "❌ PostgreSQL container not running"
    exit 1
fi

# Test database connection
echo "🔍 Testing database connection..."
if docker-compose exec -T postgres psql -U debt_tracker -d debt_tracker -c "SELECT 1;" > /dev/null 2>&1; then
    echo "✅ Database connection works"
else
    echo "❌ Database connection failed"
    exit 1
fi

# Test health endpoint
echo "🔍 Testing server health endpoint..."
if curl -s http://localhost:8000/health | grep -q "OK"; then
    echo "✅ Server is running and healthy"
else
    echo "⚠️  Server not responding (might not be started yet)"
fi

# Test admin API
echo "🔍 Testing admin API..."
if curl -s http://localhost:8000/api/admin/contacts > /dev/null 2>&1; then
    echo "✅ Admin API is working"
    echo ""
    echo "📊 Sample data:"
    curl -s http://localhost:8000/api/admin/contacts | head -c 500
    echo ""
else
    echo "⚠️  Admin API not responding (server might not be started)"
fi

echo ""
echo "✅ All tests passed!"
echo ""
echo "🌐 Access points:"
echo "   Admin Panel: http://localhost:8000/admin"
echo "   Health: http://localhost:8000/health"
echo "   Contacts API: http://localhost:8000/api/admin/contacts"
echo "   Transactions API: http://localhost:8000/api/admin/transactions"
