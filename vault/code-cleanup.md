# Code Cleanup & Technical Debt

Analysis of dead code, unused dependencies, and security issues. **See [[todos.md]] for actionable cleanup items.**

This document explains the problems; todos.md tracks the work needed.

## Unused Dependencies

### 1. Lettre (Email Library)
**Status**: ❌ Dead code
**File**: `backend/rust-api/Cargo.toml`
**Version**: 0.11

**What exists**:
- ✅ Dependency declared in Cargo.toml
- ✅ SMTP environment variables in .env.example (SMTP_HOST, SMTP_PORT, SMTP_USER, SMTP_PASSWORD)
- ✅ Documented in architecture.md as part of tech stack

**What's missing**:
- ❌ Zero imports in codebase
- ❌ No email service module
- ❌ No email handlers
- ❌ Not functional

**Impact**:
- Adds 2MB to compile time
- Creates confusion about email capabilities
- Cargo.toml doesn't match actual code

**Cleanup Task**:
- Remove from Cargo.toml
- Remove SMTP variables from .env.example (or keep as commented example for future)
- Update architecture.md to remove "Email: Lettre" from tech stack
- Remove from project documentation

**Root Cause**: 
Dependency added in preparation for feature that was never implemented. Version control didn't catch this mismatch.

---

## Security Issues

### 1. Client-to-Backend Connection NOT Encrypted (CRITICAL)
**Status**: ❌ Insecure by default
**Files**: 
- Backend: `backend/rust-api/src/config.rs` (ENABLE_TLS defaults to false)
- Backend: `backend/rust-api/src/main.rs` (TLS is optional)
- Client: `mobile/lib/services/backend_config_service.dart` (useHttps defaults to false)

**What exists**:
- ✅ Backend supports TLS if enabled (via ENABLE_TLS env var)
- ✅ Client has HTTPS support (useHttps flag in shared preferences)
- ✅ WebSocket can use WSS (secure) if HTTPS enabled

**What's broken**:
- ❌ **Default is HTTP (unencrypted)** — `useHttps()` returns false by default
- ❌ **Backend TLS disabled by default** — ENABLE_TLS defaults to "false"
- ❌ **No certificate pinning** — No validation of server certificates
- ❌ **No secure defaults** — Client sends JWT tokens over HTTP
- ❌ **Mobile app hardcoded IP** — Default IP is `10.95.12.45:8000` (hardcoded in code)

**What This Means**:

```
Client                          Network                      Backend
  │                               │                            │
  ├─ JWT Token ────────────HTTP────────────────────>  Listens on :8000
  │  (plain text)            (unencrypted)            (HTTP only by default)
  │                               │                            │
  │  All requests visible:        │                            │
  │  - Authorization headers      │
  │  - Contact data               │
  │  - Transaction data           │
  │  - User credentials           │
```

**Impact**:
- ⚠️ Network sniffing reveals all data
- ⚠️ Man-in-the-middle attacks possible
- ⚠️ JWT tokens exposed (can be stolen and reused)
- ⚠️ All user data (contacts, transactions, balances) exposed

**Affected Data**:
- User authentication tokens (JWT)
- Contact information
- Transaction details
- User email addresses
- All API responses

---

### 2. No Certificate Pinning
**Status**: ❌ Not implemented
**Client**: `mobile/lib/services/api_service.dart`

**What's missing**:
- ❌ No public key pinning
- ❌ No certificate validation
- ❌ No custom HttpClient with security context
- ❌ Vulnerable to CA compromise

**Risk**:
- If Certificate Authority is compromised, attacker can MITM any HTTPS connection
- No way to detect fraudulent certificates
- Standard HTTPS validation only (easy for attacker with CA cert)

**See Also**: [[client-backend-security.md]] - Full analysis of client-to-backend security

---

## Incomplete Implementations

### 1. Redis (Caching)
**Status**: ⚠️ Declared but not used
**Files**: 
- `backend/rust-api/Cargo.toml` - redis dependency
- `backend/.env.example` - REDIS_URL
- `backend/docker-compose.yml` - redis service defined
- `backend/rust-api/src/config.rs` - redis_url stored but never used

**What exists**:
- ✅ Redis container in docker-compose
- ✅ REDIS_URL environment variable
- ✅ AppState config stores redis_url
- ✅ Documented in architecture.md

**What's missing**:
- ❌ No actual usage in handlers
- ❌ No caching logic
- ❌ No redis client initialization

**Impact**:
- Redis container runs but does nothing
- Wastes resources in Docker setup
- Creates confusion about actual capabilities

**Cleanup Task**:
- Decide: remove Redis completely OR implement caching
- If removing: delete from docker-compose.yml, Cargo.toml, config.rs
- If keeping: implement actual caching (document why it's needed)

---

## Other Potential Issues

### Review Needed

**Files to audit for dead code**:
- `backend/rust-api/src/services/` — Check all services are actually used
- `backend/rust-api/migrations/` — Verify all migrations are necessary
- `Cargo.toml` dependencies — Each should have at least one use site

**Dead Code Patterns to Look For**:
- Imports without usage
- Modules that don't export anything used
- Helper functions never called
- Migration files that aren't applied

---

## Prevention Strategy

**Better Version Control Practices**:

1. **Code Review Checklist**:
   - Are new dependencies actually used?
   - Does Cargo.toml match code?
   - Are environment variables referenced in code?
   - Do module exports match imports?

2. **Documentation Should Match Code**:
   - If documenting tech stack, verify it's implemented
   - If listing features, mark unimplemented ones clearly
   - Use FIXME/TODO comments for incomplete features

3. **Dependency Management**:
   - `cargo build --release` to catch unused deps
   - Audit dependencies regularly
   - Document why each dependency exists

4. **Environment Variables**:
   - Every .env variable should be used
   - Mark optional variables clearly
   - Document the purpose of each variable

---

## Cleanup Priority

**High Priority** (Remove/Fix):
- [ ] Lettre (unused, confusing)
- [ ] Redis (unused, wastes resources)

**Medium Priority** (Audit):
- [ ] Review all Cargo.toml dependencies
- [ ] Check all exported modules are used
- [ ] Verify all migrations are in use

**Low Priority** (Documentation):
- [ ] Add "Unimplemented Features" section to README
- [ ] Mark incomplete work clearly in code
- [ ] Document why certain code exists

---

## Notes

This cleanup effort represents fixing side effects of poor version control:
- Adding dependencies without implementation
- Creating configuration without usage
- Documenting features that don't exist

The root issue is **lack of enforcement** during code review:
- Did reviewer check Cargo.toml changes?
- Did reviewer verify .env variables are used?
- Did reviewer ensure documentation matches code?

Future PRs should include verification that:
- ✅ All added dependencies are used
- ✅ All new config variables are referenced in code
- ✅ Architecture.md matches actual implementation

---

## Actionable Items

All cleanup tasks are listed in [[todos.md]] under:
- Code Cleanup & Technical Debt
- Unused Dependencies
- Security Issues

Track progress there.
