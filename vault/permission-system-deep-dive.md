---
tags:
  - permissions
  - security
---

# Permission System Deep Dive

**Status**: ✅ Fully implemented and tested  
**Architecture**: Discord/Telegram style group-based permissions  
**Database**: PostgreSQL with permission matrix tables

## Table of Contents
1. [System Overview](#system-overview)
2. [Request Flow](#request-flow)
3. [Permission Resolution Algorithm](#permission-resolution-algorithm)
4. [Key Components](#key-components)
5. [Code Examples](#code-examples)
6. [Data Model](#data-model)

---

## System Overview

The permission system enforces fine-grained access control through a **matrix-based approach**:

```
User Groups × Contact Groups → Allowed Actions
```

### Core Concepts

| Concept | Definition | Example |
|---------|-----------|---------|
| **Wallet** | Top-level container (like Discord server) | "My Finances" wallet |
| **User Group** | Collection of users within a wallet | all_users, Admins, Editors |
| **Contact Group** | Collection of contacts within a wallet | all_contacts, VIP, Family |
| **Permission Action** | Specific operation | contact:read, transaction:update |
| **Permission Matrix** | (user_group, contact_group) → actions | "Editors can read all_contacts" |

### Permission Actions

**Contact Operations**:
- `contact:create` - Create new contacts
- `contact:read` - View contact details
- `contact:update` - Edit contact info (also aliased as `contact:edit`)
- `contact:delete` - Remove contacts
- `contact:edit` - UI alias for contact:update

**Transaction Operations**:
- `transaction:create` - Create new transactions
- `transaction:read` - View transaction details
- `transaction:update` - Edit transactions
- `transaction:delete` - Remove transactions
- `transaction:close` - Mark as settled

**Wallet Operations**:
- `wallet:read` - View wallet
- `wallet:update` - Edit wallet settings
- `wallet:delete` - Remove wallet
- `wallet:manage_members` - Add/remove wallet members

**Other**:
- `events:read` - Access event log

---

## Request Flow

### Step 1: HTTP Request Arrives

```
GET /api/wallets/abc-123/contacts
Authorization: Bearer <JWT_token>
```

### Step 2: Authentication Middleware

**File**: `src/middleware/auth.rs`

```rust
pub async fn auth_middleware(...) -> Result<Response, StatusCode> {
    // 1. Extract JWT from Authorization header
    let token = extract_bearer_token(auth_header)?;
    
    // 2. Decode and validate JWT signature
    let claims = decode::<Claims>(token, decoding_key, validation)?;
    
    // 3. Verify user exists in users_projection or admin_users
    let user_exists = query_scalar(
        "SELECT EXISTS(SELECT 1 FROM users_projection WHERE id = $1) 
         OR EXISTS(SELECT 1 FROM admin_users WHERE id = $1 AND is_active = true)"
    ).fetch_one(pool).await?;
    
    // 4. Attach AuthUser to request extensions
    let auth_user = AuthUser {
        user_id: claims.user_id,
        email: claims.email,
    };
    req.extensions_mut().insert(auth_user);
    
    Ok(next.run(req).await)
}
```

**Output**: `AuthUser` extension containing user_id and email

### Step 3: Wallet Context Middleware

**File**: `src/middleware/wallet_context.rs`

```rust
pub async fn wallet_context_middleware(...) -> Result<Response, StatusCode> {
    // 1. Get authenticated user from extensions
    let auth_user = req.extensions()
        .get::<AuthUser>()
        .cloned()
        .ok_or(StatusCode::UNAUTHORIZED)?;
    
    // 2. Extract wallet_id from query param, header, or URL path
    let wallet_id = extract_wallet_id(&req)?;
    
    // 3. Verify wallet exists and is active
    let wallet_exists = query_scalar(
        "SELECT EXISTS(SELECT 1 FROM wallets WHERE id = $1 AND is_active = true)"
    ).fetch_one(pool).await?;
    
    if !wallet_exists {
        return Err(StatusCode::NOT_FOUND);
    }
    
    // 4. Verify user is member of wallet (owns/admin/member role)
    let wallet_user = query(
        "SELECT role FROM wallet_users 
         WHERE wallet_id = $1 AND user_id = $2"
    ).fetch_optional(pool).await?;
    
    let user_role = match wallet_user {
        Some(row) => row.get::<String>("role"), // "owner", "admin", or "member"
        None => {
            return Err((StatusCode::FORBIDDEN, json!({
                "code": "DEBITUM_INSUFFICIENT_WALLET_PERMISSION",
                "message": "You do not have access to this wallet"
            })));
        }
    };
    
    // 5. Attach WalletContext to request extensions
    let wallet_context = WalletContext {
        wallet_id,
        user_role, // "owner", "admin", or "member"
    };
    req.extensions_mut().insert(wallet_context);
    
    Ok(next.run(req).await)
}
```

**Output**: `WalletContext` extension containing wallet_id and user_role

### Step 4: Handler Permission Check

**File**: `src/handlers/contacts.rs::create_contact`

```rust
pub async fn create_contact(
    State(state): State<AppState>,
    Extension(wallet_context): Extension<WalletContext>,
    Extension(auth_user): Extension<AuthUser>,
    Json(payload): Json<CreateContactRequest>,
) -> Result<...> {
    let wallet_id = wallet_context.wallet_id;
    let user_id = auth_user.user_id;
    let user_role = &wallet_context.user_role;
    
    // 1. For non-owner/admin members: check permission matrix
    if user_role != "owner" && user_role != "admin" {
        for contact_group_id in &payload.group_ids {
            // 2. Call permission service
            let can_create = permission_service::can_perform_action_on_contact_group(
                &pool,
                wallet_id,
                user_id,
                user_role,
                contact_group_id,
                "contact:create", // Action to check
            )
            .await?;
            
            // 3. If denied, return 403
            if !can_create {
                return Err((
                    StatusCode::FORBIDDEN,
                    json!({"error": "Insufficient permissions"})
                ));
            }
        }
    }
    
    // 4. If allowed, proceed with creating contact
    let contact = create_contact_in_db(...)?;
    
    Ok((StatusCode::CREATED, json!(contact)))
}
```

**Key Points**:
- Owner/admin roles **bypass all permission checks** (auto-allowed)
- Members go through **permission matrix resolution**
- If action not allowed → **403 Forbidden**

---

## Permission Resolution Algorithm

### Step 1: Resolve User Groups

**Function**: `resolve_user_groups()`

```rust
async fn resolve_user_groups(
    pool: &PgPool,
    wallet_id: Uuid,
    user_id: Uuid,
) -> Result<Vec<Uuid>, sqlx::Error> {
    // Every member is implicitly in all_users group
    let mut user_group_ids = vec![
        query_scalar("SELECT id FROM user_groups 
                      WHERE wallet_id = $1 AND name = 'all_users'")
            .fetch_one(pool)
            .await?
    ];
    
    // Plus any explicitly assigned groups
    let explicit_groups = query_scalar::<_, Vec<Uuid>>(
        "SELECT user_group_id FROM user_group_members 
         WHERE user_id = $1"
    )
    .bind(user_id)
    .fetch_all(pool)
    .await?;
    
    user_group_ids.extend(explicit_groups);
    Ok(user_group_ids)
}
```

**Result**: `[all_users, Editors, VIP_Managers]`

### Step 2: Resolve Resource Groups

**Function**: `resolve_contact_groups_for_resource()`

```rust
async fn resolve_contact_groups_for_resource(
    pool: &PgPool,
    wallet_id: Uuid,
    resource_type: ResourceType,
    resource_id: Option<Uuid>,
) -> Result<Vec<Uuid>, sqlx::Error> {
    // Every contact is implicitly in all_contacts group
    let mut group_ids = vec![
        query_scalar("SELECT id FROM contact_groups 
                      WHERE wallet_id = $1 AND name = 'all_contacts'")
            .fetch_one(pool)
            .await?
    ];
    
    // Plus explicit groups for this contact
    if let Some(contact_id) = resource_id {
        let explicit_groups = query_scalar::<_, Vec<Uuid>>(
            "SELECT contact_group_id FROM contact_group_members 
             WHERE contact_id = $1"
        )
        .bind(contact_id)
        .fetch_all(pool)
        .await?;
        
        group_ids.extend(explicit_groups);
    }
    
    Ok(group_ids)
}
```

**Result**: `[all_contacts, VIP, Family]`

### Step 3: Query Permission Matrix

**Function**: `resolve_allowed_actions()`

```rust
pub async fn resolve_allowed_actions(
    pool: &PgPool,
    wallet_id: Uuid,
    user_id: Uuid,
    resource_type: ResourceType,
    resource_id: Option<Uuid>,
) -> Result<HashSet<String>, sqlx::Error> {
    // Get user's groups
    let user_group_ids = resolve_user_groups(pool, wallet_id, user_id).await?;
    
    // Get resource's groups
    let contact_group_ids = resolve_contact_groups_for_resource(
        pool, wallet_id, resource_type, resource_id
    ).await?;
    
    if user_group_ids.is_empty() || contact_group_ids.is_empty() {
        return Ok(HashSet::new());
    }
    
    // Query: for each (user_group, contact_group) pair in matrix,
    // collect all allowed actions
    let action_names: Vec<String> = query_scalar(
        r#"
        SELECT DISTINCT pa.name
        FROM group_permission_matrix m
        JOIN permission_actions pa ON pa.id = m.permission_action_id
        WHERE m.user_group_id = ANY($1)
          AND m.contact_group_id = ANY($2)
        "#
    )
    .bind(&user_group_ids)        // [all_users, Editors, ...]
    .bind(&contact_group_ids)     // [all_contacts, VIP, ...]
    .fetch_all(pool)
    .await?;
    
    // Return as HashSet for O(1) lookup
    Ok(action_names.into_iter().collect())
}
```

**SQL Matrix Query**:
```
┌─────────────────────────────────────────────────┐
│ User Groups: [all_users, Editors, VIP_Managers] │
│ Contact Groups: [all_contacts, VIP, Family]     │
└─────────────────────────────────────────────────┘
        │
        ├─→ (all_users, all_contacts) → {contact:read, events:read}
        ├─→ (all_users, VIP)          → {contact:read}
        ├─→ (all_users, Family)       → {contact:read}
        ├─→ (Editors, all_contacts)   → {contact:create, contact:update}
        ├─→ (Editors, VIP)            → {contact:update}
        ├─→ (VIP_Managers, VIP)       → {contact:delete, contact:update}
        │
        └─→ MERGED SET:
            {contact:read, contact:create, contact:update, contact:delete, events:read}
```

### Step 4: Permission Check

```rust
pub async fn can_perform(
    pool: &PgPool,
    wallet_id: Uuid,
    user_id: Uuid,
    user_role: &str,
    action_name: &str,
    resource_type: ResourceType,
    resource_id: Option<Uuid>,
) -> Result<bool, sqlx::Error> {
    // Fast path: owner/admin has all permissions
    if user_role == "owner" || user_role == "admin" {
        return Ok(true);
    }
    
    // Slow path: resolve matrix
    let allowed_actions = resolve_allowed_actions(
        pool, wallet_id, user_id, resource_type, resource_id
    ).await?;
    
    // Check if action is in allowed set
    if allowed_actions.contains(action_name) {
        return Ok(true);
    }
    
    // Handle alias: contact:update ↔ contact:edit
    if action_name == "contact:update" && allowed_actions.contains("contact:edit") {
        return Ok(true);
    }
    
    Ok(false) // DENIED
}
```

**Decision Tree**:
```
is_owner_or_admin? → YES → ALLOW
                ↓
                NO
                ↓
allowed_actions = resolve_from_matrix()
                ↓
action in allowed_actions? → YES → ALLOW
                         ↓
                         NO → DENY (403)
```

---

## Key Components

### 1. Permission Service

**Location**: `src/services/permission_service.rs`

**Key Functions**:

| Function | Purpose | Caller |
|----------|---------|--------|
| `can_perform()` | Check if user can perform action on resource | Handlers |
| `can_perform_action_on_contact_group()` | Check permission for contact group | Handlers (create) |
| `resolve_allowed_actions()` | Get all allowed actions for user/resource | `can_perform()` |
| `resolve_user_groups()` | Get user's groups in wallet | `resolve_allowed_actions()` |
| `resolve_contact_groups_for_resource()` | Get resource's groups | `resolve_allowed_actions()` |
| `insufficient_permission_response()` | Generate 403 JSON response | Handlers |

### 2. Wallet Context Middleware

**Location**: `src/middleware/wallet_context.rs`

**Extracts**:
- `wallet_id` from query param, header (`X-Wallet-Id`), or URL path
- `user_role` from `wallet_users` table (owner/admin/member)

**Validates**:
- Wallet exists and is active
- User is member of wallet
- Returns error if not

### 3. Permission Tables

**Location**: `migrations/014_advanced_permissions.sql`

```
┌─────────────────────────────────────────────────────┐
│ permission_actions (global reference)               │
│ id | name              | resource                   │
│ 1  | contact:create    | contact                   │
│ 2  | contact:read      | contact                   │
│ 3  | contact:update    | contact                   │
│ ... more actions ...                               │
└─────────────────────────────────────────────────────┘
         ↓
         references in matrix
         ↓
┌─────────────────────────────────────────────────────┐
│ user_groups (per wallet)                            │
│ id | wallet_id | name          | is_system         │
│ u1 | w1        | all_users     | true              │
│ u2 | w1        | Editors       | false             │
│ u3 | w1        | VIP_Managers  | false             │
└─────────────────────────────────────────────────────┘
         ↓
         membership
         ↓
┌─────────────────────────────────────────────────────┐
│ user_group_members                                  │
│ user_id | user_group_id                             │
│ alice   | u2 (Editors)                              │
│ bob     | u3 (VIP_Managers)                         │
└─────────────────────────────────────────────────────┘
         
         (similar for contact_groups/contact_group_members)
         
         ↓
         
┌────────────────────────────────────────────────────┐
│ group_permission_matrix (THE CORE)                 │
│ user_group_id | contact_group_id | permission_action_id │
│ u1 (all_users)| c1 (all_contacts)| 2 (contact:read)     │
│ u2 (Editors)  | c1 (all_contacts)| 1 (contact:create)   │
│ u2 (Editors)  | c1 (all_contacts)| 3 (contact:update)   │
│ u3 (VIP_Mgrs) | c2 (VIP)         | 4 (contact:delete)   │
└────────────────────────────────────────────────────┘
```

---

## Code Examples

### Example 1: Creating a Contact with Permission Check

```rust
// From: src/handlers/contacts.rs::create_contact

pub async fn create_contact(
    State(state): State<AppState>,
    Extension(wallet_context): Extension<WalletContext>,
    Extension(auth_user): Extension<AuthUser>,
    Json(payload): Json<CreateContactRequest>,
) -> Result<...> {
    let wallet_id = wallet_context.wallet_id;
    let user_id = auth_user.user_id;
    let user_role = &wallet_context.user_role;
    
    // 1. Determine which groups the contact will be in
    let group_ids = if let Some(ids) = &payload.group_ids {
        ids.iter().filter_map(|s| Uuid::parse_str(s).ok()).collect()
    } else {
        // Use user's default groups from settings
        sqlx::query_scalar::<_, Vec<Uuid>>(
            "SELECT COALESCE(default_contact_group_ids, '{}') 
             FROM user_wallet_settings 
             WHERE wallet_id = $1 AND user_id = $2"
        )
        .bind(wallet_id)
        .bind(user_id)
        .fetch_optional(&*state.db_pool)
        .await
        .ok()
        .flatten()
        .unwrap_or_default()
    };
    
    // 2. For non-admin members: check permission for each group
    if user_role != "owner" && user_role != "admin" {
        for contact_group_id in &group_ids {
            let can_create = permission_service::can_perform_action_on_contact_group(
                &*state.db_pool,
                wallet_id,
                user_id,
                user_role,
                contact_group_id,
                "contact:create",
            )
            .await
            .map_err(|e| {
                tracing::error!("Permission check error: {:?}", e);
                permission_service::insufficient_permission_response()
            })?;
            
            if !can_create {
                return Err(permission_service::insufficient_permission_response());
            }
        }
    }
    
    // 3. If permission check passed, create contact
    let contact_id = Uuid::new_v4();
    
    sqlx::query(
        "INSERT INTO contacts_projection (id, wallet_id, user_id, name, ...) 
         VALUES ($1, $2, $3, $4, ...)"
    )
    .bind(contact_id)
    .bind(wallet_id)
    .bind(user_id)
    .bind(&payload.name)
    .execute(&*state.db_pool)
    .await?;
    
    // 4. Add contact to specified groups
    for group_id in &group_ids {
        sqlx::query(
            "INSERT INTO contact_group_members (contact_id, contact_group_id) 
             VALUES ($1, $2)"
        )
        .bind(contact_id)
        .bind(group_id)
        .execute(&*state.db_pool)
        .await?;
    }
    
    Ok((StatusCode::CREATED, json!(contact)))
}
```

### Example 2: Full Permission Check Flow

```rust
// User tries to update a VIP contact they're not allowed to edit
// User: alice (group: Editors)
// Contact: customer (groups: VIP)
// Required action: contact:update

// 1. wallet_context_middleware extracts:
//    wallet_id = "wallet-123"
//    user_role = "member"

// 2. create_contact / update_contact handler calls:
let can_update = permission_service::can_perform(
    &pool,
    wallet_id,           // "wallet-123"
    alice_id,            // alice's user_id
    "member",            // user_role from wallet_context
    "contact:update",    // action to check
    ResourceType::Contact,
    Some(customer_id),   // the specific contact
)
.await?;

// 3. can_perform() resolves:
if user_role == "member" {
    // Not owner/admin, so check matrix
    let allowed = resolve_allowed_actions(
        &pool,
        "wallet-123",
        alice_id,
        ResourceType::Contact,
        Some(customer_id)
    )
    .await?;
    
    // Inside resolve_allowed_actions:
    // - Get user groups: [all_users, Editors]
    // - Get contact groups: [all_contacts, VIP]
    // - Query matrix for (all_users|Editors) x (all_contacts|VIP) pairs
    //
    // Matrix results:
    // (Editors, all_contacts) → {contact:create, contact:update}
    // (Editors, VIP) → {}  ← NO PERMISSION!
    // (all_users, VIP) → {contact:read}
    //
    // Merged: {contact:create, contact:update, contact:read}
    
    allowed.contains("contact:update")  // true!
}

// 4. Result: ALLOWED (because Editors can update all_contacts)
```

---

## Data Model

### Key Tables

#### `wallets`
```sql
CREATE TABLE wallets (
    id UUID PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    is_active BOOLEAN DEFAULT TRUE
);
```

#### `wallet_users`
```sql
CREATE TABLE wallet_users (
    wallet_id UUID NOT NULL REFERENCES wallets(id),
    user_id UUID NOT NULL REFERENCES users_projection(id),
    role VARCHAR(32) CHECK (role IN ('owner', 'admin', 'member')),
    PRIMARY KEY (wallet_id, user_id)
);
```

#### `permission_actions` (Seeded)
```sql
CREATE TABLE permission_actions (
    id SMALLSERIAL PRIMARY KEY,
    name VARCHAR(64) UNIQUE NOT NULL,
    resource VARCHAR(32) NOT NULL
);
-- Inserted with: contact:create, contact:read, etc.
```

#### `user_groups`
```sql
CREATE TABLE user_groups (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    wallet_id UUID NOT NULL REFERENCES wallets(id),
    name VARCHAR(255) NOT NULL,
    is_system BOOLEAN DEFAULT FALSE,
    UNIQUE(wallet_id, name)
);
```

#### `contact_groups`
```sql
CREATE TABLE contact_groups (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    wallet_id UUID NOT NULL REFERENCES wallets(id),
    name VARCHAR(255) NOT NULL,
    type VARCHAR(32) DEFAULT 'static',
    definition JSONB,
    is_system BOOLEAN DEFAULT FALSE,
    UNIQUE(wallet_id, name)
);
```

#### `group_permission_matrix` (THE CORE)
```sql
CREATE TABLE group_permission_matrix (
    user_group_id UUID NOT NULL REFERENCES user_groups(id),
    contact_group_id UUID NOT NULL REFERENCES contact_groups(id),
    permission_action_id SMALLINT NOT NULL REFERENCES permission_actions(id),
    PRIMARY KEY (user_group_id, contact_group_id, permission_action_id)
);
```

---

## Error Handling

### Permission Denied Response

**File**: `src/services/permission_service.rs`

```rust
pub fn insufficient_permission_response() -> (StatusCode, Json<serde_json::Value>) {
    (
        StatusCode::FORBIDDEN,
        Json(serde_json::json!({
            "code": "DEBITUM_INSUFFICIENT_WALLET_PERMISSION",
            "message": "You do not have permission to perform this action"
        }))
    )
}
```

**Mobile Handling**:
- Catches `DEBITUM_INSUFFICIENT_WALLET_PERMISSION` error code
- Shows toast: "You don't have permission to do this"
- Does NOT drop local events (respects permission boundary)

---

## Testing

### Test Coverage

**Location**: `backend/rust-api/tests/permission_enforcement_test.rs`

Tests cover:
- ✅ Owner has all permissions
- ✅ Admin has all permissions
- ✅ Member with permission allowed
- ✅ Member without permission denied
- ✅ Multiple user groups (union of permissions)
- ✅ Multiple contact groups (union of permissions)
- ✅ Default group selection on create
- ✅ Wallet isolation (users can't access other wallets)

---

## Performance Considerations

### Query Optimization

1. **Indexed lookups**: user_groups, contact_groups indexed by wallet_id
2. **Batched array queries**: Permission matrix uses SQL `ANY()` for groups
3. **Caching candidates**: Could cache user groups (relatively static)
4. **Fast path**: Owner/admin bypasses all queries (no matrix lookup)

### Typical Query Time

- Auth middleware: ~5ms (JWT decode)
- Wallet context middleware: ~10ms (wallet validation + role lookup)
- Permission check (member): ~15-20ms (matrix query)
- **Total per request**: ~30-35ms (members), ~15ms (owners/admins)

---

## Future Enhancements

1. **Dynamic Groups**: Computed groups (overdue, we_owe, they_owe)
2. **Allow/Deny Matrix**: Currently allow-only; add explicit denies
3. **Role Inheritance**: User groups can inherit from other groups
4. **Permission Caching**: Cache user groups in Redis for frequent users
5. **Audit Logging**: Log all permission checks for compliance
6. **Group UI**: Admin interface for managing groups and matrix

