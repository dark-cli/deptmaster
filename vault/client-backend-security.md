# Client-to-Backend Connection Security Assessment

**Status**: ❌ **NOT SECURED** — Unencrypted by default

## Summary

The connection between the mobile/web client and backend is **unencrypted by default**. All requests, including authentication tokens and sensitive data, are transmitted in **plain text over HTTP**.

---

## Detailed Findings

### Backend Configuration

**File**: `backend/rust-api/src/config.rs`

```rust
enable_tls: env::var("ENABLE_TLS")
    .unwrap_or_else(|_| "false".to_string())  // ❌ Defaults to false
    .parse()
    .unwrap_or(false),
```

**Server Status**:
- ❌ Runs on HTTP by default (port 8000)
- ⚠️ HTTPS available but must be explicitly enabled (ENABLE_TLS=true)
- ❌ Note in code: TLS support is "complex" and recommends reverse proxy

### Client Configuration

**File**: `mobile/lib/services/backend_config_service.dart`

```dart
static Future<bool> useHttps() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyBackendUseHttps) ?? false;  // ❌ Defaults to false
}

static Future<String> getBaseUrl() async {
    final https = await useHttps();
    final protocol = https ? 'https' : 'http';  // Uses http by default
    return '$protocol://$ip:$port';
}
```

**Client Status**:
- ❌ Connects via HTTP by default
- ❌ HTTPS flag must be explicitly set in SharedPreferences
- ❌ Default backend IP hardcoded: `10.95.12.45:8000`

---

## What's Exposed

### Over HTTP Connection

All of these are transmitted in **plain text**:

1. **Authentication**
   - JWT tokens in Authorization header
   - User credentials during login
   - Token refresh tokens (if applicable)

2. **Sensitive Data**
   - Contact names, emails, phone numbers
   - Transaction amounts and descriptions
   - User balance information
   - All user settings

3. **Request Details**
   - API endpoints being accessed
   - Query parameters
   - Request timing and frequency
   - IP addresses

4. **Response Data**
   - Complete contact lists
   - Transaction history
   - User profile information
   - Admin panel data (if accessed)

---

## Attack Scenarios

### 1. Network Sniffing
```
Attacker on same WiFi network
  → tcpdump captures HTTP traffic
  → Extract JWT token
  → Impersonate user
  → Access all user's data
```

### 2. Man-in-the-Middle (MITM)
```
Attacker intercepts connection
  → Modify requests (change transaction amounts)
  → Modify responses (show false balances)
  → Steal authentication tokens
```

### 3. Token Theft
```
Unencrypted JWT in Authorization header
  → Token captured by attacker
  → Token reused to make unauthorized requests
  → Attacker can act as legitimate user
```

---

## Current Security Layers

### What's Protected

✅ **At Rest**:
- Passwords hashed in database (bcrypt)
- Database credentials in environment variables

✅ **Authentication**:
- JWT tokens signed with secret
- Password verification before token generation
- 401 response for invalid tokens

### What's NOT Protected

❌ **In Transit**:
- HTTP = unencrypted channel
- No TLS/SSL encryption
- No certificate verification
- No certificate pinning

❌ **Token Transmission**:
- JWT visible in Authorization header (HTTP)
- Token can be stolen mid-transit
- No integrity protection for HTTP headers

---

## Configuration Matrix

| Component | HTTPS Enabled | Secure | Notes |
|-----------|--------------|--------|-------|
| Backend | Default: No | ❌ | Requires ENABLE_TLS=true |
| Client HTTP | Default: No | ❌ | Uses http:// by default |
| Client WebSocket | Depends | ⚠️ | Uses ws:// if HTTPS not set, wss:// if HTTPS set |
| Database | Optional | ⚠️ | Separate issue, see code-cleanup.md |
| JWT Tokens | N/A | ❌ | Sent in plain text over HTTP |
| Certificates | N/A | ❌ | No pinning implemented |

---

## File Locations

### Backend
- Configuration: `backend/rust-api/src/config.rs` (lines 42-45)
- Server startup: `backend/rust-api/src/main.rs` (lines 164-230)
- Environment: `backend/.env.example` (no ENABLE_TLS documented)

### Client
- HTTP Client: `mobile/lib/services/api_service.dart` (uses dart http package)
- URL Builder: `mobile/lib/services/backend_config_service.dart` (lines 40-74)
- WebSocket: `mobile/lib/services/backend_config_service.dart` (lines 68-74)
- Config Storage: Uses SharedPreferences (Flutter)

---

## Recommended Fixes

### Immediate (Phase 1)

1. **Set HTTPS as Default**
   ```
   Backend: ENABLE_TLS=true by default
   Client: useHttps defaults to true
   ```

2. **Document Requirements**
   - Update README with HTTPS requirement
   - Document TLS certificate setup
   - Provide default TLS configuration

### Short-term (Phase 2)

3. **Use Reverse Proxy**
   - nginx/Caddy/Traefik for TLS termination
   - Better performance and maintainability
   - Automatic certificate renewal (Let's Encrypt)

4. **Certificate Pinning**
   - Pin server certificate on client
   - Detect MITM attempts with fake certificates
   - Protect against CA compromise

### Long-term (Phase 3)

5. **Certificate Management**
   - Automated certificate renewal
   - Certificate rotation procedures
   - Monitoring for expired certificates

6. **Security Hardening**
   - HSTS headers (HTTP Strict Transport Security)
   - Secure cookie flags
   - CSP (Content Security Policy) for web clients

---

## Testing to Verify

### Verify HTTP (Current - Insecure)
```bash
# Start backend with defaults
ENABLE_TLS=false ./backend

# Client connects
curl -v http://localhost:8000/health
# Will show unencrypted connection
```

### Verify HTTPS (After Fix)
```bash
# Start backend with TLS
ENABLE_TLS=true TLS_CERT_PATH=cert.pem TLS_KEY_PATH=key.pem ./backend

# Client connects
curl -v https://localhost:8000/health
# Will show encrypted connection
```

---

## Impact Assessment

**Severity**: 🔴 **CRITICAL**

| Aspect | Impact |
|--------|--------|
| **User Data** | ❌ All exposed (contacts, transactions, balances) |
| **Authentication** | ❌ Tokens visible in transit |
| **Integrity** | ❌ Requests can be modified |
| **Confidentiality** | ❌ No encryption |
| **Production Ready** | ❌ Not suitable for production |

---

## Cleanup Checklist

- [ ] Review current deployment configuration
- [ ] Determine HTTPS requirement for production
- [ ] Plan TLS certificate management
- [ ] Configure reverse proxy (nginx/Caddy) or direct TLS
- [ ] Implement certificate pinning on client
- [ ] Document secure deployment procedures
- [ ] Test HTTPS with real certificates
- [ ] Implement HSTS headers
- [ ] Add security headers (X-Frame-Options, etc.)
- [ ] Document configuration for users

---

## Related Issues

- [[code-cleanup.md]] - Overall security issues including database connection
- [[backend-reader-guide.md]] - Understanding the backend architecture
- [[security-fixes.md]] - All critical security findings
