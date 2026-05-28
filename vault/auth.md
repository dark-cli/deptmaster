---
tags:
  - auth
  - middleware
---

# Authentication Middleware

## Overview

The backend uses JWT-based authentication with a middleware layer that enforces authorization on protected routes. The middleware extracts and validates Bearer tokens, verifies user existence in the database, and injects authenticated user information into the request.

## Route Groups

### Public Routes (No Authentication)
Configured in `backend/rust-api/src/main.rs:92-99`. These routes bypass the auth middleware entirely:

- `/health` — Health check endpoint
- `/api/auth/login` — Regular user login
- `/api/auth/admin/login` — Admin user login
- `/admin` — Admin panel page (login form)
- `/config.js` — Admin configuration (optional)
- `/favicon.ico` — Favicon
- `/api/dev/clear-database` — Dev-only database clear (checks ENVIRONMENT internally)

**Exception handling in middleware**: The `auth_middleware` function explicitly allows these paths (middleware/auth.rs:32-35) before requiring JWT validation.

### Protected Routes — User API
Configured in `backend/rust-api/src/main.rs:102-120`. All routes require valid JWT token:

- `/api/contacts` — GET, POST, PUT, DELETE
- `/api/transactions` — GET, POST, PUT, DELETE
- `/api/settings` — GET, PUT
- `/api/sync/hash` — GET
- `/api/sync/events` — GET, POST
- `/api/auth/change-password` — PUT

Authentication applied via: `.layer(axum::middleware::from_fn_with_state(app_state.clone(), auth_middleware))`

### Protected Routes — Admin API
Configured in `backend/rust-api/src/main.rs:123-141`. All routes require valid JWT token:

- `/api/admin/events` — GET, POST
- `/api/admin/events/latest` — GET
- `/api/admin/events/backfill-transactions` — POST
- `/api/admin/contacts` — GET
- `/api/admin/transactions` — GET
- `/api/admin/projections/status` — GET
- `/api/admin/projections/rebuild` — POST
- `/api/admin/users` — GET, POST, DELETE
- `/api/admin/users/:id/password` — PUT
- `/api/admin/users/:id/login-logs` — GET
- `/api/admin/users/:id/backup` — GET

Authentication applied via: `.layer(axum::middleware::from_fn_with_state(app_state.clone(), auth_middleware))`

## JWT Validation Flow

### 1. Token Extraction (middleware/auth.rs:37-48)
- Reads `Authorization` header from request
- Expects format: `Bearer <token>`
- Returns `401 UNAUTHORIZED` if header missing or malformed

### 2. JWT Decoding (middleware/auth.rs:50-55)
- Uses HS256 algorithm with `JWT_SECRET` from config
- Decodes and validates token signature
- Returns `401 UNAUTHORIZED` if token invalid or expired

### 3. User Verification (middleware/auth.rs:59-74)
- Parses `user_id` from token claims
- Queries database for user existence in either:
  - `users_projection` table (regular users)
  - `admin_users` table with `is_active = true` (admin users)
- Returns `401 UNAUTHORIZED` if user not found or inactive

### 4. AuthUser Injection (middleware/auth.rs:76-81)
- Creates `AuthUser` struct with validated user information
- Inserts into request extensions: `req.extensions_mut().insert(auth_user)`
- Continues request processing with auth context attached

## Token Structure

JWT claims are defined as `Claims` struct (middleware/auth.rs:12-17):

```rust
pub struct Claims {
    pub user_id: String,      // UUID of authenticated user
    pub email: String,        // User email address
    pub exp: usize,           // Expiration timestamp (Unix epoch)
}
```

## AuthUser Extraction in Handlers

Protected handlers extract the authenticated user via Axum's extension extractor:

```rust
pub async fn some_protected_handler(
    axum::extract::Extension(auth_user): axum::extract::Extension<AuthUser>,
    // ... other extractors
) -> Result<...> {
    // auth_user.user_id: Uuid
    // auth_user.email: String
}
```

Example: `change_password` handler (handlers/users.rs:212) uses `AuthUser` to identify which user is changing their password.

## Configuration

- **JWT Secret**: `JWT_SECRET` environment variable
- **Token Expiration**: Set during token generation (handlers/auth.rs:45-56)
- **Algorithm**: HS256 (symmetric, shared secret)

## Middleware Chain Order

The complete middleware stack (main.rs:148-161):

1. CORS layer
2. Rate limit middleware
3. Security headers middleware
4. Trace layer (HTTP logging)
5. **Per-router auth middleware** (applied only to protected_api_routes and admin_routes)
6. Router dispatch

This ensures all requests are rate-limited, logged, and have security headers before reaching route-specific auth checks.

## AuthUser Structure

Defined in `middleware/auth.rs:19-24`:

```rust
#[derive(Clone)]
pub struct AuthUser {
    pub user_id: Uuid,                    // Parsed from JWT claims
    pub email: String,                    // Parsed from JWT claims
}
```

The `#[allow(dead_code)]` comment indicates email is reserved for future use in logging or user info display.

## Login Response

Successful login returns `AuthResponse` (handlers/auth.rs:30-34) with:

```rust
pub struct AuthResponse {
    pub token: String,       // JWT token for subsequent requests
    pub user_id: String,     // User's UUID
    pub username: String,    // User's email (treated as username in login)
}
```

## Related Notes
- [[permission-system-deep-dive.md]] - Group-based permissions and access control
