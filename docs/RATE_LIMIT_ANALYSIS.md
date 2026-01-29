# Rate Limiting Issue Analysis

## What Happened?

### The Problem
The admin page was sending **too many requests** to `/api/admin/events/latest` in a very short time, causing the server to return **HTTP 429 (Too Many Requests)** errors.

### The Logs Show:
```
2026-01-29T14:50:02.570851Z ... status=429
2026-01-29T14:50:02.571233Z ... status=429
2026-01-29T14:50:02.571661Z ... status=429
... (many more 429 errors in rapid succession)
```

## Why Did It Happen?

### 1. **Which Client?**
- **Admin Page** (not Flutter app)
- The Flutter app uses WebSocket and doesn't have this issue

### 2. **Why So Many Requests?**

The admin page had multiple functions calling the same endpoint:

1. **`validateAuth()`** - Validates if user is still logged in
   - Called on: login, page load, WebSocket reconnection, periodic checks
   - Makes request to: `/api/admin/events/latest`

2. **`startSmartUpdates()`** - Starts real-time update system
   - Called on: login, WebSocket reconnection
   - Makes request to: `/api/admin/events/latest` to get initial event ID

3. **`checkForUpdates()`** - Checks if new events exist
   - Called on: WebSocket message received
   - Makes request to: `/api/admin/events/latest`

**The Problem:** All these functions were calling the same endpoint, and when WebSocket reconnected multiple times (due to errors), each reconnection triggered all three functions, causing a flood of requests.

### 3. **Why Did They Fail?**

**NOT wrong auth information** - The auth token was valid!

**It was a client bug** - The admin page JavaScript was:
- Making too many requests too quickly
- Not handling rate limits gracefully
- Reconnecting WebSocket too aggressively (every 2 seconds)
- Each reconnection triggered multiple API calls

### 4. **Rate Limit Configuration**

From the code:
- **Default rate limit:** Configurable via `RATE_LIMIT_REQUESTS` env var
- **Authenticated users:** Get 5x the default limit
- **Window:** Configurable via `RATE_LIMIT_WINDOW` env var (in seconds)

Example: If default is 100 requests per 60 seconds:
- Unauthenticated: 100 requests/60s
- Authenticated: 500 requests/60s

But the admin page was making **dozens of requests per second**, quickly exceeding even the higher authenticated limit.

## What Is "Caching Auth" and How Does It Work?

### Before (The Problem):
```javascript
async function validateAuth() {
    // Every time this is called, it makes an API request
    const response = await fetch('/api/admin/events/latest');
    return response.ok;
}

// Called 10 times in 1 second = 10 API requests!
validateAuth(); // Request 1
validateAuth(); // Request 2
validateAuth(); // Request 3
// ... etc
```

### After (The Fix):
```javascript
let lastAuthValidation = null;      // When we last checked
let authValidationCache = null;      // Cached result (true/false)
const AUTH_CACHE_DURATION = 60000;  // Cache for 60 seconds

async function validateAuth() {
    const now = Date.now();
    
    // Check if we have a cached result that's still fresh
    if (authValidationCache !== null && 
        lastAuthValidation !== null && 
        (now - lastAuthValidation) < AUTH_CACHE_DURATION) {
        // Use cached result - NO API REQUEST!
        return authValidationCache;
    }
    
    // Only make API request if cache is expired
    const response = await fetch('/api/admin/events/latest');
    authValidationCache = (response.status === 200);
    lastAuthValidation = now;
    return authValidationCache;
}

// Called 10 times in 1 second = 1 API request!
validateAuth(); // Request 1, caches result
validateAuth(); // Uses cache, no request
validateAuth(); // Uses cache, no request
// ... etc - all use cache for 60 seconds
```

### How It Works:

1. **First call:** Makes API request, stores result in cache
2. **Subsequent calls (within 60 seconds):** Returns cached result immediately, no API request
3. **After 60 seconds:** Cache expires, next call makes new API request

**Result:** Instead of 10 requests per second, we make 1 request per 60 seconds!

## The Fixes Applied

### 1. **Auth Validation Caching**
- Cache auth validation results for 60 seconds
- Prevents repeated API calls for the same check

### 2. **Rate Limit Handling**
- When server returns 429, use cached result instead of failing
- Skip update checks if rate limited (WebSocket handles updates anyway)

### 3. **Longer Reconnection Delays**
- Changed from 2 seconds to 5 seconds
- Prevents rapid reconnection attempts

### 4. **Smarter Update Checking**
- If rate limited, skip the check (WebSocket will notify of updates anyway)
- Don't fail completely, just skip the redundant check

## Summary

| Question | Answer |
|----------|--------|
| **What failed?** | Too many API requests to `/api/admin/events/latest` |
| **Why failed?** | Client bug - admin page making requests too frequently |
| **Was it wrong auth?** | No, auth token was valid |
| **Which client?** | Admin page (web browser) |
| **What is caching?** | Storing the result of auth check for 60 seconds to avoid repeated API calls |
| **How does it work?** | First call makes API request, subsequent calls use cached result until 60 seconds pass |
