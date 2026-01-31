# Multi-User Multi-Wallet System Plan

## Overview

Transform the current single-tenant system into a multi-user, multi-wallet system where:
- **Wallets** are isolated containers with their own event logs, transactions, and contacts
- Users can subscribe to multiple wallets
- Admins can create wallets and manage user subscriptions
- Users can switch between wallets via a side UI

## Architecture Changes

### 1. Database Schema

#### New Tables

**wallets**
```sql
CREATE TABLE wallets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(255) NOT NULL,
    description TEXT,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
    created_by UUID REFERENCES users(id),
    is_active BOOLEAN NOT NULL DEFAULT true
);

CREATE INDEX idx_wallets_created_by ON wallets(created_by);
CREATE INDEX idx_wallets_active ON wallets(is_active);
```

**wallet_users** (Many-to-many relationship)
```sql
CREATE TABLE wallet_users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    wallet_id UUID NOT NULL REFERENCES wallets(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role VARCHAR(50) NOT NULL DEFAULT 'member', -- 'owner', 'admin', 'member'
    subscribed_at TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE(wallet_id, user_id)
);

CREATE INDEX idx_wallet_users_wallet_id ON wallet_users(wallet_id);
CREATE INDEX idx_wallet_users_user_id ON wallet_users(user_id);
```

#### Modified Tables

**events**
- Add `wallet_id UUID REFERENCES wallets(id) ON DELETE CASCADE`
- Make wallet_id required (NOT NULL)
- Update indexes to include wallet_id

**contacts_projection**
- Add `wallet_id UUID REFERENCES wallets(id) ON DELETE CASCADE`
- Make wallet_id required (NOT NULL)
- Update indexes to include wallet_id

**transactions_projection**
- Add `wallet_id UUID REFERENCES wallets(id) ON DELETE CASCADE`
- Make wallet_id required (NOT NULL)
- Update indexes to include wallet_id

**projection_snapshots**
- Add `wallet_id UUID REFERENCES wallets(id) ON DELETE CASCADE`
- Update composite indexes to include wallet_id

### 2. Event Sourcing Changes

#### Event Structure
All events must include `wallet_id` in the event data:
```json
{
  "wallet_id": "uuid",
  "aggregate_type": "contact",
  "aggregate_id": "uuid",
  "event_type": "CREATED",
  "event_data": {...}
}
```

#### Projection Rebuild
- Rebuild projections per wallet
- Each wallet maintains its own state independently

### 3. API Changes

#### New Endpoints

**Wallet Management (Admin)**
- `POST /api/admin/wallets` - Create new wallet
- `GET /api/admin/wallets` - List all wallets
- `GET /api/admin/wallets/:id` - Get wallet details
- `PUT /api/admin/wallets/:id` - Update wallet
- `DELETE /api/admin/wallets/:id` - Delete wallet (soft delete)

**Wallet User Management (Admin)**
- `POST /api/admin/wallets/:id/users` - Add user to wallet
- `GET /api/admin/wallets/:id/users` - List wallet users
- `PUT /api/admin/wallets/:id/users/:userId` - Update user role
- `DELETE /api/admin/wallets/:id/users/:userId` - Remove user from wallet

**User Wallet Access**
- `GET /api/wallets` - List wallets user is subscribed to
- `GET /api/wallets/:id` - Get wallet details (if subscribed)
- `POST /api/wallets/:id/subscribe` - Subscribe to wallet (if allowed)
- `DELETE /api/wallets/:id/subscribe` - Unsubscribe from wallet

**Wallet-Scoped Operations**
All existing endpoints need wallet context:
- `GET /api/contacts?wallet_id=:id` - Get contacts in wallet
- `POST /api/contacts` - Create contact in current wallet
- `GET /api/transactions?wallet_id=:id` - Get transactions in wallet
- `POST /api/transactions` - Create transaction in current wallet
- `GET /api/sync/hash?wallet_id=:id` - Get sync hash for wallet
- `GET /api/sync/events?wallet_id=:id` - Get events for wallet

#### Middleware Changes

**Wallet Context Middleware**
- Extract `wallet_id` from request (header, query param, or session)
- Verify user has access to the wallet
- Inject wallet context into request state

**Authorization Updates**
- Check wallet subscription before allowing operations
- Enforce role-based permissions (owner, admin, member)

### 4. Frontend Changes

#### Mobile App

**Wallet Switcher UI**
- Add wallet selector in drawer/sidebar
- Show current wallet name and icon
- List all subscribed wallets
- Allow switching between wallets
- Show wallet-specific badge/indicator

**State Management**
- Add `currentWalletId` to app state
- Store wallet list in local state
- Update all API calls to include `wallet_id`
- Separate local database per wallet (or namespace by wallet_id)

**UI Components**
- Wallet selector component
- Wallet list screen
- Wallet info display
- Wallet switching animation/feedback

**Local Database Changes**
- Namespace Hive boxes by wallet_id: `contacts_${wallet_id}`, `transactions_${wallet_id}`
- Or add wallet_id field to all local records
- Update sync service to sync per wallet

#### Admin Page

**Wallet Management**
- Create wallet form
- Wallet list with search/filter
- Wallet details view
- Edit wallet settings

**User Management per Wallet**
- Add users to wallet
- Remove users from wallet
- Change user roles
- View wallet members

**Dashboard Updates**
- Show wallet selector
- Filter statistics by wallet
- Wallet-specific analytics

### 5. Migration Strategy

#### Phase 1: Database Migration
1. Create new tables (wallets, wallet_users)
2. Create default wallet for existing data
3. Migrate all existing events/contacts/transactions to default wallet
4. Add wallet_id columns to existing tables
5. Backfill wallet_id for all existing records

#### Phase 2: Backend Implementation
1. Add wallet endpoints
2. Update existing endpoints to require wallet_id
3. Add wallet context middleware
4. Update authorization checks
5. Update event sourcing to include wallet_id

#### Phase 3: Frontend Implementation
1. Add wallet switcher UI
2. Update API calls to include wallet_id
3. Update local database structure
4. Update sync service
5. Add wallet management to admin page

#### Phase 4: Testing & Rollout
1. Test multi-wallet scenarios
2. Test user permissions
3. Test wallet switching
4. Performance testing
5. Gradual rollout

### 6. Security Considerations

**Access Control**
- Users can only access wallets they're subscribed to
- Verify wallet access on every API call
- Prevent cross-wallet data leakage
- Audit wallet access logs

**Role-Based Permissions**
- **Owner**: Full control, can delete wallet, manage users
- **Admin**: Can manage users, modify data
- **Member**: Can view and create data, cannot manage users

**Data Isolation**
- Ensure queries are always scoped to wallet_id
- Validate wallet_id in all database operations
- Prevent SQL injection through wallet_id

### 7. Performance Considerations

**Database Indexes**
- Index all wallet_id columns
- Composite indexes for common queries (wallet_id + other fields)
- Monitor query performance

**Caching**
- Cache wallet subscriptions per user
- Cache wallet metadata
- Invalidate on subscription changes

**Sync Optimization**
- Sync per wallet independently
- Parallel sync for multiple wallets
- Optimize event queries with wallet_id

### 8. User Experience

**Wallet Switching**
- Smooth transition animation
- Clear indication of current wallet
- Remember last selected wallet per session
- Quick switch via keyboard shortcut (desktop)

**Visual Indicators**
- Wallet name in app bar
- Wallet color/icon for differentiation
- Badge showing wallet count
- Empty state when no wallets

**Onboarding**
- Create first wallet automatically
- Guide users to create/join wallets
- Show wallet benefits/use cases

### 9. Implementation Checklist

#### Backend
- [ ] Create database migration for wallets table
- [ ] Create database migration for wallet_users table
- [ ] Add wallet_id to events table
- [ ] Add wallet_id to all projection tables
- [ ] Create wallet management endpoints
- [ ] Create wallet user management endpoints
- [ ] Update all existing endpoints to require wallet_id
- [ ] Add wallet context middleware
- [ ] Update authorization middleware
- [ ] Update event sourcing to include wallet_id
- [ ] Update projection rebuild to be wallet-scoped
- [ ] Add wallet_id to sync endpoints
- [ ] Update WebSocket to include wallet_id
- [ ] Add wallet access validation
- [ ] Write tests for wallet functionality

#### Frontend (Mobile)
- [ ] Design wallet switcher UI
- [ ] Create wallet selector component
- [ ] Add wallet state management
- [ ] Update all API calls to include wallet_id
- [ ] Update local database to namespace by wallet_id
- [ ] Update sync service for multi-wallet
- [ ] Add wallet list screen
- [ ] Add wallet switching logic
- [ ] Update UI to show current wallet
- [ ] Handle wallet switching in navigation
- [ ] Test wallet switching flow

#### Frontend (Admin)
- [ ] Create wallet management UI
- [ ] Create wallet list view
- [ ] Create wallet creation form
- [ ] Create wallet user management UI
- [ ] Add wallet selector to admin dashboard
- [ ] Update admin endpoints to support wallets
- [ ] Add wallet filtering to admin views

#### Migration
- [ ] Create migration script for existing data
- [ ] Create default wallet for existing users
- [ ] Migrate all existing data to default wallet
- [ ] Verify data integrity after migration
- [ ] Create rollback plan

### 10. Future Enhancements

**Wallet Features**
- Wallet sharing via invite links
- Wallet templates
- Wallet archiving
- Wallet export/import
- Wallet merging

**Advanced Permissions**
- Granular permissions per wallet
- Custom roles
- Permission inheritance
- Time-based access

**Analytics**
- Per-wallet analytics
- Cross-wallet reporting
- Wallet usage statistics
- User activity per wallet

## Notes

- Consider using "workspace" or "space" terminology instead of "wallet" if it better fits the use case
- Ensure backward compatibility during migration
- Plan for data export/backup before major changes
- Consider rate limiting per wallet
- Plan for wallet deletion and data retention policies
