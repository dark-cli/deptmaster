# Debitum Project - Current State Summary

**Last Updated**: May 26, 2026  
**Branch**: docs/codebase-audit (merged from feature/advanced-permissions-system)  
**Status**: Major architectural upgrade complete, ready for client-side work

## Architecture Overview

### Multi-Wallet System ✅
- Wallets are now top-level containers (like Discord servers or Telegram groups)
- Each wallet has its own:
  - Contacts
  - Transactions  
  - Users/members with roles (owner, admin, member)
  - User groups and contact groups
  - Permission matrix
- User can be member of multiple wallets

### Permission System ✅
**Pattern**: Discord/Telegram style group-based permissions

**Components**:
- **Permission Actions**: 13+ actions (contact:read, transaction:update, wallet:manage_members, etc.)
- **User Groups**: Collections of users within a wallet (e.g., all_users, Admins, Editors)
- **Contact Groups**: Collections of contacts within a wallet (e.g., all_contacts, VIP, Family)
- **Permission Matrix**: Defines which user groups can perform which actions on which contact groups

**Resolution**:
1. Get user's groups (including all_users if member)
2. Get contact's groups (including all_contacts if exists)
3. For each (user_group, contact_group) pair, collect allowed actions
4. Merge (union); if requested action in set → allow; else 403

### Data Isolation ✅
- **Fixed**: Multi-wallet system solves global data access issue
- All data now scoped to wallet_id
- User A in Wallet 1 cannot see User B in Wallet 2's data
- Permission matrix provides fine-grained access within wallet

## Technology Stack

### Backend (Rust)
- **Framework**: Axum (web)
- **Database**: PostgreSQL (event sourcing + projections)
- **Real-time**: WebSocket with broadcast
- **Async**: Tokio
- **Testing**: Comprehensive test suite (wallet isolation, permissions, integration)

### Frontend (Rust/Leptos)
- **Framework**: Leptos (reactive web framework)
- **Language**: Rust
- **Status**: Complete implementation (new in this merge)

### Mobile (Flutter)
- **Architecture**: New client-core library (Flutter Rust Bridge)
- **Client Core**: Rust-based with FFI to Flutter
- **Libraries**:
  - Sync module (offline-first)
  - Permissions module (with full tests)
  - CRUD operations
  - Storage abstraction
  - Conflict resolution
- **Status**: Framework complete, UI screens updated

## Database Schema Highlights

### Multi-Wallet Tables
- `wallets` - Wallet containers
- `wallet_users` - Membership with roles
- All data tables (contacts, transactions, events) have `wallet_id` foreign key

### Permission Tables
- `permission_actions` - 13 action definitions
- `user_groups` - Per-wallet user groups
- `user_group_members` - Static group membership
- `contact_groups` - Per-wallet contact groups
- `contact_group_members` - Static membership
- `group_permission_matrix` - (user_group × contact_group) → allowed actions
- `user_wallet_settings` - Default group selection for creators

## Testing Coverage

### New Test Suites
- ✅ Wallet isolation tests
- ✅ Permission enforcement tests  
- ✅ Wallet context middleware tests
- ✅ App instances sync tests
- ✅ Client-core comprehensive tests (permissions, conflict, sync, stress)

### Coverage Areas
- Wallet data isolation
- Permission matrix resolution
- Group membership evaluation
- Multi-wallet synchronization
- Offline-first sync behavior
- Conflict handling

## Completed vs Remaining

### ✅ COMPLETED THIS WEEK
1. Code audit (main branch analysis)
2. Security vulnerabilities identified (data isolation, permissions)
3. Feature branch discovery (advanced-permissions-system)
4. Full merge of advanced permissions system
5. Vault documentation updated
6. MERGED_FEATURES.md created
7. Architecture documented

### 🚀 NEXT PHASE
1. **Mobile Client-Core Integration**
   - Migrate screens to use client-core
   - Remove old service files
   - Implement permission-aware UI

2. **Permission UIs**
   - Admin: Group management
   - Admin: Permission matrix viewer
   - User: Default group selection in settings
   - User: Show available actions based on permissions

3. **Dynamic Groups**
   - Implement computed groups (overdue, we_owe, they_owe)
   - Evaluation at permission resolution time

4. **Missing Features**
   - Idempotency keys on mobile
   - Conflict resolution UI
   - Allow/deny permission matrix

## File Structure

```
backend/rust-api/
  ├── src/
  │   ├── handlers/wallets.rs          (NEW)
  │   ├── middleware/wallet_context.rs (NEW)
  │   ├── services/permission_service.rs (NEW)
  │   └── ...
  ├── migrations/
  │   ├── 011_create_wallets.sql
  │   ├── 012_add_wallet_id_to_tables.sql
  │   ├── 014_advanced_permissions.sql
  │   └── ...
  └── tests/
      ├── wallet_isolation_test.rs
      ├── permission_enforcement_test.rs
      └── ...

crates/debitum_client_core/          (NEW)
  └── Complete Rust client library with FFI

frontend/                             (NEW)
  └── Complete Leptos web frontend

mobile/
  ├── lib/
  │   ├── lib/src/                    (NEW - client-core bindings)
  │   ├── screens/                    (Updated for wallets)
  │   └── providers/wallet_data_providers.dart (NEW)
  └── test/hive_test_data/wallets*    (NEW)

vault/
  ├── todos.md                         (Updated)
  ├── MERGED_FEATURES.md              (NEW)
  ├── CURRENT_STATE.md                (THIS FILE - NEW)
  ├── permissions.md                  (Existing)
  └── ...
```

## Key Metrics

| Aspect | Before | After |
|--------|--------|-------|
| **User Roles** | 2 (admin, user) | N groups per wallet |
| **Data Isolation** | Global access (bug) | Per-wallet isolation |
| **Permissions** | Route-only | Handler + matrix based |
| **Test Coverage** | Basic | Comprehensive |
| **Architecture** | Single-user multi-access | Multi-wallet multi-tenant |
| **Mobile** | Old services | Client-core library |
| **Frontend** | Minimal | Full Leptos app |

## Known Limitations

1. Dynamic groups not yet evaluated (static membership only)
2. Allow/deny matrix not implemented (allow-only currently)
3. Transaction groups are placeholders
4. Mobile client-core not yet fully integrated with UI
5. Idempotency keys not sent from mobile client

## Deployment Considerations

### Migration from Old System
- Create default wallet per user
- Migrate existing contacts/transactions to default wallet
- Seed default groups and permission matrix
- Backward compatible (all_users gets all permissions by default)

### Configuration
- Rate limiting: 100/60s unauthenticated, 500/60s authenticated
- JWT expiration: 3600s (1 hour)
- WebSocket broadcast buffer: 100 messages
- Database: PostgreSQL with 21+ tables

### Security
- ⚠️ TLS disabled by default (should be enabled for production)
- ⚠️ Database connection unencrypted by default (should require sslmode)
- ✅ JWT tokens used for authentication
- ✅ Permission matrix enforced at handler level
- ✅ Wallet scoping provides data isolation

