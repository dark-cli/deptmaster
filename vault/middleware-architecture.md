---
tags:
  - middleware
  - architecture
---

# Middleware Architecture

Complete overview of middleware responsibilities, current implementation, and architecture.

---

## Middleware Chain (Execution Order)

```
Request arrives
    ↓
1. Rate Limit Middleware          ← First gate (IP-based throttling)
    ↓
2. Security Headers Middleware    ← Add safety headers (CORS, etc.)
    ↓
3. Trace/Logging Middleware       ← Log requests
    ↓
4. Auth Middleware                ← JWT validation (for protected routes)
    ↓
5. Wallet Context Middleware      ← Extract wallet & validate membership (for wallet routes)
    ↓
6. Handler
    ↓
7. Response
```

---

## Current Middleware (4 implementations)

### 1. Auth Middleware (`src/middleware/auth.rs`)

**Responsibility**: Validate JWT tokens and determine user identity/role

**What it does**:
- Decodes JWT token from `Authorization: Bearer <token>` header
- Validates token signature and expiration (HS256 algorithm)
- Checks user exists in either:
  - `users_projection` (regular users)
  - `admin_users` with `is_active = true` (admin panel users)
- Determines if user is admin or regular user
- Enforces admin-only paths: `/api/admin/*` requires `is_admin = true`
- Enforces user-only paths: `/api/contacts`, `/api/transactions`, `/api/sync/` require `is_admin = false`

**Injects into request**: 
```rust
pub struct AuthUser {
    pub user_id: Uuid,
    pub username: String,
    pub is_admin: bool,
}
```

**Applied to**: All protected routes (not public routes like `/health`, `/api/auth/login`)

**Issues**:
- ⚠️ Path checking (`if path.starts_with("/api/admin/")`) should be at routing level, not middleware
- ⚠️ Admin token blocking logic (denying `/api/contacts` to admins) is fragile

---

### 2. Wallet Context Middleware (`src/middleware/wallet_context.rs`)

**Responsibility**: Extract wallet ID and validate user has access to it

**What it does**:
- Extracts wallet_id from (in precedence order):
  1. Query parameter: `?wallet_id=<uuid>`
  2. HTTP header: `X-Wallet-Id: <uuid>`
  3. URL path: `/api/wallets/<uuid>/...`
- Validates wallet exists in database
- Validates user is member of wallet (has entry in `wallet_users` with role owner/admin/member)
- Extracts user's role in that specific wallet
- Returns 403 Forbidden if user not in wallet

**Injects into request**:
```rust
pub struct WalletContext {
    pub wallet_id: Uuid,
    pub user_role: String,  // "owner" | "admin" | "member"
}
```

**Applied to**: Wallet-scoped routes (`/api/wallets/:wallet_id/...`)

**Issues**:
- ⚠️ Supports 3 extraction methods with unclear precedence (should use path only)
- ⚠️ No permission check here (permissions checked in handlers instead)

---

### 3. Rate Limit Middleware (`src/middleware/rate_limit.rs`)

**Responsibility**: Throttle requests per client

**What it does**:
- Tracks requests by IP address
- Enforces limits per time window:
  - Unauthenticated: 100 requests per 60 seconds (1.67/sec)
  - Authenticated: 500 requests per 60 seconds (8.33/sec)
- Returns 429 Too Many Requests when limit exceeded
- Includes retry-after header

**Configuration** (from `config.rs`):
```
RATE_LIMIT_REQUESTS=100        # unauthenticated limit
RATE_LIMIT_AUTHENTICATED=500   # authenticated limit
RATE_LIMIT_WINDOW=60           # time window in seconds
```

**Issues**:
- ⚠️ Per-IP only (affects multiple users behind same VPN/corporate network)
- ⚠️ Should be per-user + per-IP for authenticated requests

---

### 4. Security Headers Middleware (`src/middleware/security_headers.rs`)

**Responsibility**: Add security-related HTTP headers to all responses

**What it does**:
- Adds CORS headers (Access-Control-Allow-*)
- Adds security headers:
  - `X-Content-Type-Options: nosniff` (prevent MIME sniffing)
  - `X-Frame-Options: SAMEORIGIN` (prevent clickjacking)
  - `X-XSS-Protection` (legacy XSS protection)
  - `Content-Type: application/json` (enforce JSON)

**Applied to**: All responses

---

## Missing Middleware

### Permission Enforcement Middleware (Not yet implemented)

**Would do**: Check user has permission for the resource before handler runs

**Current state**: Permission checks are scattered in handlers:
- `handlers/contacts.rs` checks `can_perform("contact:create")`
- `handlers/transactions.rs` checks `can_perform("transaction:create")`
- Each handler reimplements the permission check

**Better approach**: Centralized middleware
```rust
// Hypothetical permission middleware
pub async fn permission_middleware(
    Extension(auth_user): Extension<AuthUser>,
    Extension(wallet_context): Extension<WalletContext>,
    req: Request,
    next: Next,
) -> Response {
    // Determine required permission from route/method
    let required_permission = get_required_permission(req.uri());
    
    // Check permission using service
    let can_perform = permission_service.can_perform(
        auth_user.user_id,
        wallet_context.wallet_id,
        required_permission,
    ).await?;
    
    if !can_perform {
        return Response::FORBIDDEN;
    }
    
    next.run(req).await
}
```

**Benefit**: Single permission check point, consistent enforcement, testable

---

### Audit Logging Middleware (Not yet implemented)

**Would do**: Log all mutations (INSERT, UPDATE, DELETE) with context

**Current state**: No centralized audit trail
- CREATE events are stored in `events` table
- But who, what, when, where context is incomplete
- No tracking of permission checks or denials

**Better approach**: Audit middleware logs:
- User ID who performed action
- Resource (contact, transaction, wallet)
- Operation (create, update, delete)
- Timestamp
- Wallet ID
- Success/failure

**Benefit**: Security compliance, debugging, audit trail

---

### Request ID Correlation Middleware (Not yet implemented)

**Would do**: Generate or extract request IDs for distributed tracing

**Current state**: No request correlation
- Logs don't link to specific requests
- WebSocket messages aren't correlated
- Hard to trace a user action through logs

**Better approach**: 
- Generate UUID per request
- Include in response headers: `X-Request-ID: <uuid>`
- Include in all logs: `request_id=<uuid>`
- Include in WebSocket messages

**Benefit**: Easier debugging, distributed tracing support

---

### Caching Headers Middleware (Not yet implemented)

**Would do**: Add appropriate Cache-Control headers

**Current state**: No caching headers
- Clients don't know what's safe to cache
- Mobile app fetches same data repeatedly

**Better approach**:
- GET endpoints: `Cache-Control: max-age=300` (5 minutes)
- POST/PUT/DELETE: `Cache-Control: no-cache, no-store`
- Static resources: `Cache-Control: max-age=31536000` (1 year)

**Benefit**: Reduce bandwidth, faster mobile app

---

## Middleware Issues & TODOs

### Current Issues
1. **Auth middleware checks paths** (should be routing responsibility)
2. **Wallet context allows 3 extraction methods** (should use path only)
3. **Admin/user enforcement in middleware** (should be separate route groups)
4. **Rate limiting per-IP only** (should be per-user for authenticated)
5. **Permission checks in handlers** (should be middleware)
6. **No audit trail** (no logging of mutations)
7. **No request correlation** (hard to debug distributed issues)

### Action Items
- [ ] Move auth path checks to routing (separate admin_routes, user_routes)
- [ ] Standardize wallet_id extraction to path only
- [ ] Implement permission enforcement middleware
- [ ] Implement audit logging middleware
- [ ] Change rate limiting from per-IP to per-user + per-IP
- [ ] Add request ID correlation middleware
- [ ] Add caching headers middleware

---

## How to Add New Middleware

**Pattern**:
```rust
// 1. Define the middleware function
pub async fn my_middleware(
    State(state): State<AppState>,
    mut req: Request,
    next: Next,
) -> Result<Response, StatusCode> {
    // 2. Do your check/transformation
    let my_data = process_request(&req)?;
    
    // 3. Inject into request
    req.extensions_mut().insert(my_data);
    
    // 4. Call next middleware
    Ok(next.run(req).await)
}

// 5. Apply to routes in main.rs
.layer(axum::middleware::from_fn_with_state(
    app_state.clone(),
    my_middleware,
))
```

**Order matters**: Apply middleware in the order they should execute (outer = earlier)

---

## Related Notes
- [[architecture.md]] - Overall system architecture
- [[permission-system-deep-dive.md]] - Permission enforcement details
- [[todos.md]] - See "Middleware & Routing Cleanup" section
