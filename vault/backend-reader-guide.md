# Backend Reader Guide

Complete guide to understanding the Rust backend codebase. Focus on understanding code flow, architecture, and design patterns.

## Prerequisites

- Rust basics (ownership, traits, async/await)
- HTTP/REST concepts
- PostgreSQL fundamentals

## Phase 1: Foundation (Understanding the Big Picture)

### 1.1 Project Overview
**File**: `/README.md`
**Time**: 5 minutes
**Goal**: What problem does this solve?

**Key Points to Note**:
- Offline-first debt tracking app
- Event-sourced backend
- Real-time sync via WebSocket
- Multi-platform (iOS, Android, Web, Linux)

### 1.2 Architecture Overview
**File**: `vault/architecture.md`
**Time**: 15 minutes
**Goal**: How do all pieces fit together?

**Key Sections to Read**:
- Tech Stack (Backend)
- Core Data Flow
- Backend Services
- Storage Architecture
- Key Design Decisions

**Diagrams to Understand**:
- User Action → Event Creation → Server Storage → Broadcast → Client Sync

---

## Phase 2: Entry Point & Routing

### 2.1 Main Application Setup
**File**: `backend/rust-api/src/main.rs`
**Time**: 30 minutes
**Goal**: How does the app start and route requests?

**What to Look For**:
- Lines 37-70: Application initialization
  - Environment loading
  - Database pool creation
  - Background scheduler setup
  - Rate limiter initialization
  - Broadcast channel creation
- Lines 92-153: Route definitions
  - Public routes (no auth required)
  - Protected user API routes
  - Admin routes
  - Middleware layers

**Key Understanding**:
```
Request
  ↓
Rate Limit Middleware
  ↓
Security Headers Middleware
  ↓
Trace/Logging Middleware
  ↓
Auth Middleware (for protected routes)
  ↓
Route Handler
  ↓
Response
```

**Questions to Answer**:
- How many route groups are there?
- Which routes require authentication?
- What happens if rate limit exceeded?

### 2.2 Configuration
**File**: `backend/rust-api/src/config.rs`
**Time**: 15 minutes
**Goal**: How is the app configured?

**What to Look For**:
- Lines 19-57: Configuration loading from environment
- Lines 59-119: Configuration validation
- Database URL handling (sslmode)
- JWT secret and expiration
- CORS settings
- TLS configuration

**Key Understanding**:
- All config comes from environment variables
- Default values exist but should be overridden in production
- Validation warns about insecure configurations

---

## Phase 3: Authentication & Authorization

### 3.1 Authentication System
**File**: `vault/auth.md`
**Time**: 15 minutes
**Goal**: How does JWT authentication work?

**Already documented**, just read and understand:
- How tokens are generated
- How tokens are validated
- Which routes are protected
- AuthUser struct

### 3.2 Middleware: Auth
**File**: `backend/rust-api/src/middleware/auth.rs`
**Time**: 20 minutes
**Goal**: How is every request authenticated?

**What to Look For**:
- Lines 12-17: JWT Claims structure
- Lines 19-24: AuthUser struct (user info passed to handlers)
- Lines 26-84: auth_middleware function
  - Path exceptions (health, login endpoints)
  - Token extraction from Authorization header
  - JWT decoding and validation
  - User verification (check in users_projection or admin_users)
  - AuthUser injection into request

**Key Understanding**:
- Middleware checks every request (except public routes)
- User must exist in database (either table)
- Admin users must have is_active = true
- User info attached to request via extensions

**Questions to Answer**:
- What paths bypass authentication?
- What happens if token is invalid?
- How does middleware know if user is admin? (Spoiler: it doesn't - see permissions.md)

### 3.3 Permissions System
**File**: `vault/permissions.md`
**Time**: 30 minutes
**Goal**: How are admin vs regular users distinguished?

**Key Sections**:
- User Role Definition & Storage
- How System Distinguishes Admin vs Regular User
- Handler-Level Permission Checks
- Database Differences (users_projection vs admin_users)

**Critical Finding**:
- Admin endpoints have NO handler-level role checks
- Only protected by routing layer
- Regular users can access admin endpoints if they have valid JWT

---

## Phase 4: Database & Storage

### 4.1 Database Schema
**Files**: 
- `backend/rust-api/migrations/001_initial_schema.sql` (main tables)
- `backend/rust-api/migrations/010_add_admin_users.sql` (admin table)
**Time**: 30 minutes
**Goal**: Understand data structure

**Tables to Understand**:

1. **events** (immutable event log)
   - event_id (UUID)
   - user_id (who made the change)
   - aggregate_type (contact, transaction)
   - aggregate_id (which contact/transaction)
   - event_type (CREATED, UPDATED, DELETED)
   - event_data (JSON payload)
   - created_at (timestamp)

2. **users_projection** (regular users)
   - id (UUID)
   - email
   - password_hash
   - created_at
   - last_event_id (for sync)

3. **admin_users** (admin panel users)
   - id (UUID)
   - username
   - password_hash
   - is_active (can be deactivated)
   - last_login_at

4. **contacts_projection** (read-optimized view)
   - user_id (belongs to which user)
   - name, phone, email
   - is_deleted (soft delete)

5. **transactions_projection** (read-optimized view)
   - user_id, contact_id
   - type, direction, amount
   - is_settled, is_deleted

**Key Understanding**:
- Events are immutable (append-only)
- Projections are actively maintained (not rebuilt)
- Soft deletes (is_deleted flag)
- user_id in every data row (data isolation)

### 4.2 Database Connection
**File**: `backend/rust-api/src/database/mod.rs`
**Time**: 10 minutes
**Goal**: How does code connect to database?

**What to Look For**:
- Lines 6-24: create_pool function
  - SQLx PgPool creation
  - TLS configuration check
  - Warning for insecure connections

**Key Understanding**:
- Uses connection pooling (SQLx)
- TLS support available but not enforced by default

---

## Phase 5: Request Handlers

### 5.1 Simple Handler: Get Contacts
**File**: `backend/rust-api/src/handlers/contacts.rs`
**Time**: 20 minutes
**Goal**: How does a handler work?

**Function to Read**: `get_contacts()` (first function)

**What to Look For**:
- `State(state)` → Access to AppState (DB pool, config)
- `Path(user_id)` → Extract path parameter
- `axum::extract::Extension(auth_user)` → Extract authenticated user
- SQL query construction
- Error handling pattern
- Response serialization

**Pattern to Understand**:
```rust
pub async fn handler_name(
    State(state): State<AppState>,           // App state injection
    Path(id): Path<String>,                  // URL path params
    axum::extract::Extension(auth_user): ..., // Authenticated user
    Json(payload): Json<RequestStruct>,      // Request body
) -> Result<Json<ResponseStruct>, Error> {
    // 1. Validate input
    // 2. Query database
    // 3. Handle errors
    // 4. Return response
}
```

### 5.2 Create Handler: Create Contact
**File**: `backend/rust-api/src/handlers/contacts.rs`
**Function**: `create_contact()`
**Time**: 20 minutes
**Goal**: How is data created and stored?

**What to Look For**:
- UUID generation
- SQL INSERT
- Event creation (event_data JSON)
- Error handling (duplicate, validation)
- HTTP status codes (201 Created)

**Key Understanding**:
- Data inserted into projection (contacts_projection)
- Event created (for audit trail)
- Both happen in transaction (same query)

### 5.3 Authentication Handlers
**File**: `backend/rust-api/src/handlers/auth.rs`
**Function**: `login()`
**Time**: 15 minutes
**Goal**: How does user login work?

**What to Look For**:
- Query user by email from users_projection
- Password verification (bcrypt)
- JWT token generation
- Login logging (ip, user_agent)
- Error messages (don't reveal if user exists)

### 5.4 Admin Handlers
**File**: `backend/rust-api/src/handlers/users.rs`
**Functions**: `get_users()`, `create_user()`, `delete_user()`
**Time**: 15 minutes
**Goal**: How do admin operations work?

**What to Look For**:
- No authentication extraction (relies on routing)
- Direct database queries without role checks
- Admin user creation
- User deletion

**Critical Note**: These handlers have comments saying "admin only" but NO actual role verification code.

---

## Phase 6: Middleware & Security

### 6.1 Rate Limiting Middleware
**File**: `backend/rust-api/src/middleware/rate_limit.rs`
**Time**: 15 minutes
**Goal**: How are requests rate limited?

**What to Look For**:
- Rate limit key (by IP or user)
- Check limit logic
- Error response (429 Too Many Requests)

### 6.2 Security Headers Middleware
**File**: `backend/rust-api/src/middleware/security_headers.rs`
**Time**: 10 minutes
**Goal**: What security headers are added?

**What to Look For**:
- Headers added to every response
- CORS handling
- Content-Type enforcement

---

## Phase 7: Advanced Topics

### 7.1 Event Sourcing Pattern
**Where to Learn**:
- Read handlers that INSERT events
- Look at event_data JSON structure
- Understand immutability principle

**Key Files**:
- Any handler with INSERT + event creation
- Migration 001 (events table structure)

### 7.2 Projections
**Understand**:
- Projections are updated in real-time (not rebuilt)
- Snapshots exist for optimization (not required)
- Data denormalization for fast reads

**Example**:
```rust
// When contact created:
// 1. INSERT into events (immutable)
// 2. INSERT into contacts_projection (read cache)
// 3. BROADCAST to WebSocket (notify clients)
```

### 7.3 WebSocket & Real-Time Updates
**File**: `backend/rust-api/src/websocket/mod.rs`
**Time**: 15 minutes
**Goal**: How do clients get real-time notifications?

**Key Understanding**:
- Tokio broadcast channel (multiple subscribers)
- One message = server sends message to all connected clients
- Clients trigger sync (not receiving full data via WebSocket)

---

## Reading Checklist

### Must Read (Foundation)
- [ ] README.md
- [ ] vault/architecture.md
- [ ] main.rs (routes + startup)
- [ ] config.rs
- [ ] vault/auth.md
- [ ] middleware/auth.rs
- [ ] vault/permissions.md
- [ ] migrations/001_initial_schema.sql
- [ ] database/mod.rs

### Should Read (Core Logic)
- [ ] handlers/auth.rs (login flow)
- [ ] handlers/contacts.rs (CRUD example)
- [ ] handlers/users.rs (admin operations)
- [ ] middleware/rate_limit.rs
- [ ] middleware/security_headers.rs

### Nice to Read (Advanced)
- [ ] handlers/admin.rs (admin panel)
- [ ] websocket/mod.rs (real-time)
- [ ] background/scheduler.rs (background jobs)
- [ ] migrations/* (all schema changes)

---

## Tips for Reading Code

1. **Start with function signature** — Input/output tells you everything
   ```rust
   pub async fn get_contacts(
       State(state): State<AppState>,
       Path(user_id): Path<String>,
       axum::extract::Extension(auth_user): ...,
   ) -> Result<Json<Vec<ContactResponse>>, Error>
   ```
   This tells you: takes state/params/user, returns contacts or error

2. **Follow the `Result<T, E>` type** — Shows error handling
   - Ok branch = success path
   - Err branch = failure path

3. **Look for `sqlx::query` patterns** — How database is accessed
   ```rust
   sqlx::query("SELECT...")
       .bind(param)
       .fetch_one(&*state.db_pool)
       .await
   ```

4. **Understand Axum extractors**:
   - `State(state)` = app state
   - `Path(id)` = URL path parameter
   - `Json(payload)` = request body
   - `Extension(user)` = middleware-injected data

5. **Don't memorize SQL** — Just understand what queries do
   - SELECT = read
   - INSERT = create
   - UPDATE = modify
   - DELETE = remove

6. **Trace error handling** — Usually follows pattern:
   ```rust
   .map_err(|e| {
       tracing::error!(...);
       (StatusCode::INTERNAL_SERVER_ERROR, Json(...))
   })
   ```

---

## Quick Reference: Code Organization

```
backend/rust-api/src/
├── main.rs                 ← App startup, routes
├── config.rs              ← Configuration loading & validation
├── app_state.rs           ← Shared application state
├── middleware/
│   ├── auth.rs           ← JWT validation
│   ├── rate_limit.rs     ← Rate limiting
│   └── security_headers.rs ← Security headers
├── handlers/
│   ├── auth.rs           ← Login endpoints
│   ├── admin_auth.rs     ← Admin login
│   ├── contacts.rs       ← Contact CRUD
│   ├── transactions.rs   ← Transaction CRUD
│   ├── users.rs          ← User management
│   └── admin.rs          ← Admin panel endpoints
├── database/
│   └── mod.rs            ← DB connection pooling
├── websocket/
│   └── mod.rs            ← WebSocket handler
├── background/
│   └── scheduler.rs      ← Background jobs
└── services/
    ├── seed_data.rs      ← Initial data seeding
    └── ...

migrations/
├── 001_initial_schema.sql     ← Tables
├── 010_add_admin_users.sql    ← Admin table
└── ...
```

---

## What to Ask Me

After reading each section, ask:

- "I don't understand how [X] works"
- "Why is [Y] designed this way?"
- "What happens when [Z] occurs?"
- "Can you trace the flow of [feature]?"
- "Where is [concept] used in the code?"

I'll use CodeGraph to show you exact code, trace execution paths, and explain design decisions.

---

## Study Schedule Suggestion

**Day 1**: Phase 1-2 (Big picture + routing)
**Day 2**: Phase 3-4 (Auth + database)
**Day 3**: Phase 5-6 (Handlers + middleware)
**Day 4**: Phase 7 + review (Advanced topics)
**Day 5**: Q&A and deep dives on confusing areas

Total time: ~5-7 hours of focused reading
