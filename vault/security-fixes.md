# Security Fixes Checklist

## Overview

Critical security vulnerabilities requiring urgent remediation. All tasks have been added to the task list.

## Permissions System (Tasks #1-5)

**Issue**: Regular users can access admin endpoints due to missing handler-level role checks.

**Root Cause**:
- AuthUser struct only contains user_id and email (no is_admin field)
- JWT tokens don't encode which table user came from
- Handlers marked "admin only" have no actual permission verification

**Affected Endpoints**:
- `/api/admin/users` (GET, POST, DELETE)
- `/api/admin/users/:id/password` (PUT)
- `/api/admin/users/:id/login-logs` (GET)
- `/api/admin/users/:id/backup` (GET)
- All other `/api/admin/*` routes

**Task #1: Add is_admin field to AuthUser struct**
- File: `middleware/auth.rs`
- Add: `pub is_admin: bool` to AuthUser struct
- Update: auth_middleware to query which table user exists in

**Task #2: Add handler-level role verification** (blocks on #1)
- Files: `handlers/users.rs`, `handlers/admin.rs`
- Add: AuthUser extraction and is_admin check to each admin handler
- Pattern:
  ```rust
  if !auth_user.is_admin {
      return Err((StatusCode::FORBIDDEN, Json({"error": "Admin access required"})));
  }
  ```

**Task #3: Encode role in JWT token claims**
- Files: `middleware/auth.rs`, `handlers/auth.rs`, `handlers/admin_auth.rs`
- Add: `is_admin` field to Claims struct
- Update: Both generate_jwt_token() and generate_admin_jwt_token() functions

**Task #4: Document middleware role verification**
- Add comments explaining the is_active check for admins
- Update API documentation about admin endpoints
- Document permission model in README

**Task #5: Add permission tests** (blocks on #1, #2)
- Create: `tests/permissions_test.rs`
- Test regular user gets 403 on `/api/admin/users`
- Test admin gets 200 on `/api/admin/users`
- Test inactive admin cannot authenticate

---

## Database Connection Security (Tasks #6-7)

**Issue**: Database connections are unencrypted by default. All queries and credentials transmitted in plain text.

**Current Configuration**:
```
❌ Default: postgresql://debt_tracker:dev_password@localhost:5432/debt_tracker
✓  Secure: postgresql://user:pass@host:5432/db?sslmode=require
```

**Root Cause**:
- Default DATABASE_URL lacks `sslmode` parameter
- Docker-compose.yml doesn't enforce TLS (line 40)
- Security validation only warns in production mode
- Weak default credentials (`dev_password`) documented

**Affected Files**:
- `backend/docker-compose.yml` (line 40)
- `backend/.env.example`
- `backend/rust-api/src/config.rs` (lines 91-95)
- `backend/rust-api/src/database/mod.rs` (lines 6-24)

**Task #6: Enforce TLS encryption for database** (CRITICAL)
- Update docker-compose.yml line 40:
  ```yaml
  DATABASE_URL: postgresql://debt_tracker:${DB_PASSWORD}@postgres:5432/debt_tracker?sslmode=require
  ```
- Update config.rs validation to ERROR (not warn) in production
- Update .env.example with production database config
- Change default DB_PASSWORD from `dev_password`
- Create or update deployment documentation

**Task #7: Add TLS certificate pinning** (blocks on #6)
- Implement certificate pinning to prevent MITM attacks
- Options:
  1. Use rustls with certificate pinning
  2. Configure PostgreSQL sslcert/sslkey/sslrootcert
  3. Implement custom certificate validation
- Lower priority than #6 but essential for production

---

## Task Dependencies

```
Permissions:
#1 (Add is_admin) → #2 (Handler verification) → #5 (Tests)
                 → #3 (JWT encoding)
                 → #4 (Documentation)

Database:
#6 (Enforce TLS) → #7 (Certificate pinning)
```

---

## Remediation Priority

**Phase 1: Permissions** (2-3 hours)
- Risk level: HIGH
- Impact: Privilege escalation possible
- Do first: #1 → #2 → #3 → #4 → #5

**Phase 2: Database** (1-2 hours)
- Risk level: CRITICAL
- Impact: Credentials and all data exposed
- Do immediately: #6 → #7

---

## Verification Checklist

**After Permissions Fix**:
- [ ] Regular user gets 403 on `/api/admin/users`
- [ ] Admin user gets 200 on `/api/admin/users`
- [ ] AuthUser extraction required in all admin handlers
- [ ] Permission tests pass

**After Database Fix**:
- [ ] docker-compose.yml contains `?sslmode=require`
- [ ] Production DATABASE_URL enforces TLS
- [ ] Default credentials changed from `dev_password`
- [ ] Config validation requires TLS in production

---

## Related Documentation
- [[auth.md]] - JWT authentication and middleware
- [[permissions.md]] - Detailed permissions system analysis
- [[architecture.md]] - System architecture overview
