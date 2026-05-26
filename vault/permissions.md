# Permissions System

## Overview

The permissions system distinguishes between **admin users** (admin panel access) and **regular users** (application users). Both types are authenticated via JWT, but they log in through different endpoints and are stored in separate database tables.

## User Role Definition & Storage

### Regular Users (users_projection table)
- Stored in: `users_projection` table
- Created via: `/api/auth/login` endpoint
- Identifier: UUID `id`
- Credentials: email + password
- Table structure (from 001_initial_schema.sql):
  ```sql
  CREATE TABLE users_projection (
      id UUID PRIMARY KEY,
      email VARCHAR(255) UNIQUE NOT NULL,
      password_hash VARCHAR(255) NOT NULL,
      created_at TIMESTAMP NOT NULL,
      last_event_id BIGINT NOT NULL
  );
  ```
- No role/status field — simple table with no distinction flags
- Login tries to find user by email

### Admin Users (admin_users table)
- Stored in: `admin_users` table (separate from users)
    pub user_id: Uuid,
    pub email: String,
}
```

## Route-Level Permission Distinction

### Public Routes (main.rs:92-99)
No authentication required:
- `/health`
- `/api/auth/login`
- `/api/auth/admin/login`
- `/admin` (login form HTML)
- `/config.js`
- `/favicon.ico`
- `/api/dev/clear-database`

### Protected User API Routes (main.rs:102-120)
All routes below get `.layer(auth_middleware)`:
- `/api/contacts` (GET, POST, PUT, DELETE)
- `/api/transactions` (GET, POST, PUT, DELETE)
- `/api/settings` (GET, PUT)
- `/api/sync/hash` (GET)
- `/api/sync/events` (GET, POST)
- `/api/auth/change-password` (PUT)

### Protected Admin Routes (main.rs:123-141)
All routes below get `.layer(auth_middleware)`:
- `/api/admin/events` (GET, POST)
- `/api/admin/events/latest` (GET)
- `/api/admin/events/backfill-transactions` (POST)
- `/api/admin/contacts` (GET)
- `/api/admin/transactions` (GET)
- `/api/admin/projections/status` (GET)
- `/api/admin/projections/rebuild` (POST)
- `/api/admin/users` (GET, POST, DELETE)
- `/api/admin/users/:id/password` (PUT)
- `/api/admin/users/:id/login-logs` (GET)
- `/api/admin/users/:id/backup` (GET)

## Handler-Level Permission Checks

**IMPORTANT FINDING**: There are **NO handler-level role verification checks**.

Examples from handlers/users.rs:

**delete_user handler (line 161):**
```rust
pub async fn delete_user(
    State(state): State<AppState>,
    Path(user_id): Path<String>,
) -> Result<StatusCode, ...> {
    // No AuthUser extraction
    // No role check
    // Just queries database
}
```

**admin_change_password handler (line 284):**
```rust
pub async fn admin_change_password(
    State(state): State<AppState>,
    Path(user_id): Path<String>,
    Json(payload): Json<AdminChangePasswordRequest>,
) -> Result<StatusCode, ...> {
    // No AuthUser extraction
    // No role check
    // Just updates password
}
```

**Comments claim "admin only"** but there's no actual enforcement:
```rust
// Get all users (admin only)
pub async fn get_users(State(state): State<AppState>) -> ... {
    // No role verification inside
}
```

**Protection relies entirely on routing layer** — the admin_routes group has the auth_middleware layer applied, but the middleware itself does not verify role/admin status.

## Access Control Flow: Scenario Comparison

### Scenario 1: Regular User Hits `/api/contacts`

```
POST /api/contacts (with Bearer token from /api/auth/login)
  ↓
Rate limit middleware ✓ (checks rate limit)
  ↓
Security headers middleware ✓ (adds headers)
  ↓
Auth middleware ✓ (validates JWT, checks users_projection OR admin_users)
  ↓
Route matched: protected_api_routes
  ↓
Handler executes (e.g., create_contact)
  ↓
Success ✓ (no role check inside handler)
```

**Outcome**: Allowed. User can create contacts.

### Scenario 2: Regular User Hits `/api/admin/users`

```
GET /api/admin/users (with Bearer token from /api/auth/login)
  ↓
Rate limit middleware ✓ (checks rate limit)
  ↓
Security headers middleware ✓ (adds headers)
  ↓
Auth middleware ✓ (validates JWT, checks users_projection OR admin_users)
  ↓
Route matched: admin_routes
  ↓
get_users handler executes (NO ROLE CHECK)
  ↓
Handler queries users_projection table
  ↓
Returns all users ✓
```

**Outcome**: Allowed! Regular users can access admin endpoints if they authenticate.

**⚠️ Security Issue**: There's no distinction in handlers between admin and regular users. Both receive the same `AuthUser` with only user_id and email. The middleware does NOT communicate role/table-of-origin.

### Scenario 3: Admin User Hits `/api/admin/users`

```
GET /api/admin/users (with Bearer token from /api/auth/admin/login)
  ↓
Rate limit middleware ✓
  ↓
Security headers middleware ✓
  ↓
Auth middleware ✓ (validates JWT, checks admin_users with is_active=true)
  ↓
Route matched: admin_routes
  ↓
get_users handler executes
  ↓
Returns all users ✓
```

**Outcome**: Allowed. Works as intended.

### Scenario 4: Inactive Admin Hits `/api/admin/users`

```
GET /api/admin/users (with Bearer token from /api/auth/admin/login)
  ↓
Auth middleware ✗ (user_id found in admin_users, but is_active=false)
  ↓
Returns 401 UNAUTHORIZED
```

**Outcome**: Blocked at middleware level.

## Summary: users_projection vs admin_users

| Feature | users_projection | admin_users |
|---------|------------------|-------------|
| **Purpose** | Regular app users | Admin panel users |
| **Login Endpoint** | `/api/auth/login` | `/api/auth/admin/login` |
| **ID Type** | UUID | UUID |
| **Credential Fields** | email, password_hash | username, password_hash, email |
| **Status Field** | None | is_active (BOOLEAN) |
| **Token Claims** | {user_id, email, exp} | {user_id (admin_id), email (username), exp} |
| **Tracking** | last_event_id (for sync) | last_login_at (for audit) |
| **Referenced By** | contacts_projection, transactions_projection | None (no foreign keys) |
| **Access Control** | Via protected_api_routes | Via admin_routes + middleware check |

## Permission Model Assessment

### Strengths
- Simple separation of concerns (two login flows, two tables)
- Admin activation status (is_active) provides account control
- All authenticated requests validated against both tables
- Rate limiting applies uniformly

### Weaknesses (Security Considerations)
1. **No Handler-Level Role Checking**: Handlers can't distinguish regular vs admin users
2. **No Role Field in JWT**: Token doesn't encode which table user came from
3. **No In-Request Role Info**: AuthUser struct has no role/admin flag
4. **Route-Only Enforcement**: Admin endpoints protected only by routing, not logic
5. **Potential Bypass**: If handler-level checks were needed in future, they cannot currently be implemented with available AuthUser data

### Recommended Enhancement
Add a `role` or `is_admin` field to `AuthUser`:
```rust
pub struct AuthUser {
    pub user_id: Uuid,
    pub email: String,
    pub is_admin: bool,  // ← Add this
}
```

Then handlers can check:
```rust
if !auth_user.is_admin {
    return Err((StatusCode::FORBIDDEN, Json(...)));
}
```
