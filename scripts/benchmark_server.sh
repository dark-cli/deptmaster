#!/bin/bash

# Server Benchmark Script
# Tests various endpoints to measure server response times

set -e

SERVER_URL="${SERVER_URL:-http://localhost:8000}"
USERNAME="${USERNAME:-max}"
PASSWORD="${PASSWORD:-12345678}"

echo "🔍 Server Benchmark - Testing response times"
echo "=============================================="
echo "Server: $SERVER_URL"
echo ""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to time an HTTP request
time_request() {
    local method=$1
    local endpoint=$2
    local data=$3
    local token=$4
    
    local headers=()
    if [ -n "$token" ]; then
        headers+=(-H "Authorization: Bearer $token")
    fi
    
    local start=$(date +%s%N)
    
    if [ "$method" = "GET" ]; then
        response=$(curl -s -w "\n%{http_code}" -o /tmp/benchmark_response.json \
            "${headers[@]}" \
            "$SERVER_URL$endpoint" 2>/dev/null)
    elif [ "$method" = "POST" ]; then
        response=$(curl -s -w "\n%{http_code}" -o /tmp/benchmark_response.json \
            -H "Content-Type: application/json" \
            "${headers[@]}" \
            -d "$data" \
            "$SERVER_URL$endpoint" 2>/dev/null)
    fi
    
    local end=$(date +%s%N)
    local duration=$(( (end - start) / 1000000 )) # Convert to milliseconds
    
    local http_code=$(echo "$response" | tail -n1)
    local body=$(cat /tmp/benchmark_response.json 2>/dev/null || echo "")
    
    echo "$duration $http_code"
}

# Test 1: Health Check
echo "📊 Test 1: Health Check (GET /health)"
result=$(time_request "GET" "/health" "")
time=$(echo $result | cut -d' ' -f1)
code=$(echo $result | cut -d' ' -f2)
if [ "$code" = "200" ]; then
    echo -e "   ${GREEN}✅${NC} Response time: ${time}ms (HTTP $code)"
else
    echo -e "   ${RED}❌${NC} Failed (HTTP $code)"
    exit 1
fi
echo ""

# Test 2: Login
echo "📊 Test 2: Login (POST /api/auth/login)"
login_data="{\"username\":\"$USERNAME\",\"password\":\"$PASSWORD\"}"
result=$(time_request "POST" "/api/auth/login" "$login_data")
time=$(echo $result | cut -d' ' -f1)
code=$(echo $result | cut -d' ' -f2)

if [ "$code" = "200" ]; then
    echo -e "   ${GREEN}✅${NC} Response time: ${time}ms (HTTP $code)"
    # Extract token
    TOKEN=$(cat /tmp/benchmark_response.json | grep -o '"token":"[^"]*' | cut -d'"' -f4)
    if [ -z "$TOKEN" ]; then
        echo -e "   ${YELLOW}⚠️${NC} Could not extract token from response"
        TOKEN=""
    else
        echo "   Token extracted (length: ${#TOKEN})"
    fi
else
    echo -e "   ${RED}❌${NC} Login failed (HTTP $code)"
    echo "   Response: $(cat /tmp/benchmark_response.json)"
    exit 1
fi
echo ""

if [ -z "$TOKEN" ]; then
    echo -e "${RED}❌ Cannot continue without auth token${NC}"
    exit 1
fi

# Test 3: Get Sync Hash
echo "📊 Test 3: Get Sync Hash (GET /api/sync/hash)"
result=$(time_request "GET" "/api/sync/hash" "" "$TOKEN")
time=$(echo $result | cut -d' ' -f1)
code=$(echo $result | cut -d' ' -f2)
if [ "$code" = "200" ]; then
    echo -e "   ${GREEN}✅${NC} Response time: ${time}ms (HTTP $code)"
    hash=$(cat /tmp/benchmark_response.json | grep -o '"hash":"[^"]*' | cut -d'"' -f4 || echo "N/A")
    echo "   Hash: ${hash:0:20}..."
else
    echo -e "   ${RED}❌${NC} Failed (HTTP $code)"
fi
echo ""

# Test 4: Get Sync Events (empty)
echo "📊 Test 4: Get Sync Events - Empty (GET /api/sync/events)"
result=$(time_request "GET" "/api/sync/events" "" "$TOKEN")
time=$(echo $result | cut -d' ' -f1)
code=$(echo $result | cut -d' ' -f2)
if [ "$code" = "200" ]; then
    echo -e "   ${GREEN}✅${NC} Response time: ${time}ms (HTTP $code)"
    event_count=$(cat /tmp/benchmark_response.json | grep -o '"events":\[[^]]*\]' | grep -o '\[.*\]' | grep -o ',' | wc -l || echo "0")
    echo "   Events returned: $event_count"
else
    echo -e "   ${RED}❌${NC} Failed (HTTP $code)"
fi
echo ""

# Test 5: Post Sync Events (single event)
echo "📊 Test 5: Post Sync Events - Single Event (POST /api/sync/events)"
event_data='[{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "aggregate_id": "660e8400-e29b-41d4-a716-446655440001",
  "aggregate_type": "contact",
  "event_type": "CREATED",
  "event_data": {"name": "Benchmark Contact", "timestamp": "2026-01-24T00:00:00Z"},
  "timestamp": "2026-01-24T00:00:00Z",
  "version": 1
}]'
result=$(time_request "POST" "/api/sync/events" "$event_data" "$TOKEN")
time=$(echo $result | cut -d' ' -f1)
code=$(echo $result | cut -d' ' -f2)
if [ "$code" = "200" ] || [ "$code" = "201" ]; then
    echo -e "   ${GREEN}✅${NC} Response time: ${time}ms (HTTP $code)"
    accepted=$(cat /tmp/benchmark_response.json | grep -o '"accepted":\[[^]]*\]' | grep -o '\[.*\]' | grep -o ',' | wc -l || echo "0")
    echo "   Events accepted: $((accepted + 1))"
else
    echo -e "   ${YELLOW}⚠️${NC} Response (HTTP $code): $(cat /tmp/benchmark_response.json | head -c 200)"
fi
echo ""

# Test 6: Post Sync Events (10 events)
echo "📊 Test 6: Post Sync Events - 10 Events (POST /api/sync/events)"
events_array="["
for i in {1..10}; do
    if [ $i -gt 1 ]; then
        events_array+=","
    fi
    uuid=$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "550e8400-e29b-41d4-a716-44665544$(printf %04d $i)")
    events_array+="{
      \"id\": \"$uuid\",
      \"aggregate_id\": \"660e8400-e29b-41d4-a716-44665544$(printf %04d $i)\",
      \"aggregate_type\": \"contact\",
      \"event_type\": \"CREATED\",
      \"event_data\": {\"name\": \"Contact $i\", \"timestamp\": \"2026-01-24T00:00:00Z\"},
      \"timestamp\": \"2026-01-24T00:00:00Z\",
      \"version\": 1
    }"
done
events_array+="]"
event_data="$events_array"

result=$(time_request "POST" "/api/sync/events" "$event_data" "$TOKEN")
time=$(echo $result | cut -d' ' -f1)
code=$(echo $result | cut -d' ' -f2)
if [ "$code" = "200" ] || [ "$code" = "201" ]; then
    echo -e "   ${GREEN}✅${NC} Response time: ${time}ms (HTTP $code)"
    accepted=$(cat /tmp/benchmark_response.json | grep -o '"accepted":\[[^]]*\]' | grep -o '\[.*\]' | grep -o ',' | wc -l || echo "0")
    echo "   Events accepted: $((accepted + 1))"
else
    echo -e "   ${YELLOW}⚠️${NC} Response (HTTP $code): $(cat /tmp/benchmark_response.json | head -c 200)"
fi
echo ""

# Test 7: Get Sync Events (with data)
echo "📊 Test 7: Get Sync Events - With Data (GET /api/sync/events)"
result=$(time_request "GET" "/api/sync/events" "" "$TOKEN")
time=$(echo $result | cut -d' ' -f1)
code=$(echo $result | cut -d' ' -f2)
if [ "$code" = "200" ]; then
    echo -e "   ${GREEN}✅${NC} Response time: ${time}ms (HTTP $code)"
    event_count=$(cat /tmp/benchmark_response.json | python3 -c "import sys, json; data=json.load(sys.stdin); print(len(data.get('events', [])))" 2>/dev/null || echo "N/A")
    echo "   Events returned: $event_count"
else
    echo -e "   ${RED}❌${NC} Failed (HTTP $code)"
fi
echo ""

# Test 8: Multiple sequential requests (warmup effect)
echo "📊 Test 8: Sequential Requests (10x Get Sync Hash - warmup test)"
total_time=0
for i in {1..10}; do
    result=$(time_request "GET" "/api/sync/hash" "" "$TOKEN")
    time=$(echo $result | cut -d' ' -f1)
    total_time=$((total_time + time))
    if [ $i -eq 1 ]; then
        echo "   Request 1: ${time}ms (cold start)"
    elif [ $i -eq 10 ]; then
        echo "   Request 10: ${time}ms"
    fi
done
avg_time=$((total_time / 10))
echo "   Average: ${avg_time}ms"
echo ""

# Summary
echo "=============================================="
echo "📊 Benchmark Summary"
echo "=============================================="
echo ""
echo "Key Metrics:"
echo "  - Health Check: Should be < 50ms"
echo "  - Login: Should be < 500ms"
echo "  - Get Sync Hash: Should be < 100ms"
echo "  - Get Sync Events (empty): Should be < 100ms"
echo "  - Post Sync Events (1 event): Should be < 200ms"
echo "  - Post Sync Events (10 events): Should be < 500ms"
echo ""
echo "If server times are fast but Flutter is slow,"
echo "the bottleneck is likely in Flutter's HTTP client."
echo ""

# Cleanup
rm -f /tmp/benchmark_response.json
