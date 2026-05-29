# Permission System Architecture

## Overview

The permission system is a type-safe, batch-only API for checking permissions across wallet-scoped resources. It provides a single source of truth for all permission logic with optimized SQL queries.

## Core Components

### 1. **Action** (`action.rs`)
Type-safe permission enum defining all 13 possible actions:
- **Contact**: Create, Read, Update, Delete
- **Transaction**: Create, Read, Update, Close
- **Wallet**: Read, Update, AddMember, RemoveMember
- **Events**: Read

Methods:
- `as_str()` - String representation
- `implies(other)` - Dependency checking (e.g., Update implies Read)

### 2. **Resource** (`resource.rs`)
Type-safe resource identification:
- **Specific**: Contact(Uuid), Transaction(Uuid), Wallet(Uuid), ContactGroup(Uuid)
- **Wildcard**: AllContacts, AllTransactions (implicit access to all in wallet)

Methods:
- `id()` - Get resource ID if specific resource
- `Display` trait for string representation

### 3. **PermissionContext** (`context.rs`)
Encapsulates the permission evaluation context:
- `wallet_id` - Wallet being accessed
- `user_id` - User making the request
- `user_role` - WalletRole (Owner, Admin, Member)

Methods:
- `owner()`, `admin()`, `member()` - Constructor helpers
- `bypasses_permissions()` - True for Owner/Admin

### 4. **WalletRole** Enum
Three-tier role system:
- **Owner**: Bypasses all permission checks (implicit access)
- **Admin**: Bypasses all permission checks (can manage permissions)
- **Member**: Subject to group-based permission matrix

### 5. **PermissionModel** (`model.rs`)
Public batch-only API for permission checking:

```rust
let model = PermissionModel::new(pool);
let ctx = PermissionContext::member(wallet_id, user_id);

let allowed = model.check_permissions(&ctx, vec![
    (Action::ContactCreate, Resource::AllContacts),
    (Action::TransactionRead, Resource::Transaction(id)),
]).await?;

if allowed[0] { /* can create */ }
if allowed[1] { /* can read */ }
```

Features:
- Single query for multiple permissions
- Returns bool array matching input order
- Validates dependencies before checking

### 6. **Resolver** (`resolver.rs`)
Internal single-JOIN query executor:
- `resolve_actions()` - Get allowed actions for specific resource
- `get_readable_contacts()` - List contacts user can read
- `get_readable_transaction_contacts()` - List contacts with readable transactions

Query optimization:
- Uses UNION to split implicit all_users path from explicit membership
- Reduces result set size 10-100x before DISTINCT

### 7. **SQL Queries** (`queries.rs`)
Centralized permission SQL constants:
- `RESOLVE_ACTIONS_QUERY` - Main permission check
- `GET_READABLE_CONTACTS_QUERY` - Contact filtering (UNION optimized)
- `GET_READABLE_TRANSACTION_CONTACTS_QUERY` - Transaction contact filtering
- `GET_READABLE_CONTACTS_VIA_ALL_QUERY` - All contacts variant
- `GET_READABLE_TRANSACTION_CONTACTS_VIA_ALL_QUERY` - All contacts variant for transactions

## Permission Model Concepts

### Wallet Hierarchy
```
Wallet
├── User
│   └── User Groups (all_users is implicit for all members)
└── Contact Groups
    └── Group Permission Matrix
        └── Permission Actions
```

### Implicit Group Membership
All wallet members are automatically in the `all_users` group without explicit entries in `user_group_members`. This is critical for:
- Reducing database rows
- Simplifying permission setup
- Fast permission resolution

### Group Permission Matrix
Cross-tabulation: user_group_id × contact_group_id × permission_action_id

Each entry grants a specific action to members of a user group for contacts in a contact group.

### Contact Groups
- **all_contacts**: Implicit group containing all wallet contacts
- **Custom groups**: User-defined groups for fine-grained permissions

## Query Optimization Strategy

### UNION Path Splitting
Original single JOIN would:
1. Process 1000+ rows of user_group_members entries
2. Join through permission matrix
3. Filter to user's groups
4. Remove duplicates with DISTINCT

Optimized approach splits into two paths:
1. **Implicit path** (all_users): Fast scan of group_permission_matrix
2. **Explicit path** (user_group_members): Filtered membership check

Result: 10-100x smaller result set before DISTINCT, with better query planner efficiency.

## Integration Points

### Handlers
- **wallets.rs** - Wallet operations with permission context
- **sync.rs** - Event sync with ReadContext for READ permission filtering
- **settings.rs** - User-scoped (no permission checks needed)
- **users.rs** - User-scoped (no permission checks needed)

### ReadContext (sync.rs)
Specialized permission context for READ-only operations:
- Filters events by user's readable contacts
- Automatically handles implicit group membership
- Used only for data filtering, not access control

## Testing

### Unit Tests
- `test_action_implies` - Dependency validation
- `test_permission_dependency_validation` - Batch validation
- `test_permission_context_creation` - Context construction

### Integration Tests
- `wallet_permissions_stage2a_test.rs` - Multi-user permission scenarios
- `app_instances_sync_test.rs` - READ permission filtering in sync
- `user_settings_test.rs` - User-scoped operations

## Key Design Principles

1. **Type Safety**: Compile-time guarantees for actions and resources
2. **Single Source of Truth**: All permission logic in PermissionModel
3. **Batch Operations**: Multiple permissions checked in single query
4. **Explicit Dependencies**: Action implications validated before checking
5. **Role Bypass**: Owner/Admin bypass all checks (fast path)
6. **Implicit Groups**: Reduce schema complexity and query size
7. **Query Optimization**: UNION splitting for large result sets

## Performance Characteristics

- **Owner/Admin bypass**: O(1) - returns true immediately
- **Member permission check**: O(1) JOIN with caching
- **Readable contacts filter**: O(n) where n = user's accessible contacts
- **Overall**: Single optimized query for multiple permissions

## Future Extensions

- Role-based defaults (grant permissions to new members)
- Time-based permissions (temporary access)
- Delegation system (users granting permissions to others)
- Audit logging (permission check history)
