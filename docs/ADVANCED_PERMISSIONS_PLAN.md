# Advanced Permissions System Plan (Group–Group, Discord/Telegram Style)

## 1. Current state

- **Wallet scope**: `wallet_users` has `(wallet_id, user_id, role)` with roles `owner` | `admin` | `member`. Only wallet membership is enforced; any member can do everything inside the wallet.
- **Gap**: No action-level or per-contact/per-group permissions.

---

## 2. Alignment with Discord / Telegram

We follow a **Discord/Telegram-like** pattern:

| Concept | Discord | Telegram | Debitum |
|--------|---------|----------|---------|
| **Container** | Guild (server) | Chat | Wallet |
| **Who** | Roles (e.g. @everyone) | Roles (Owner, Admin, Custom) | **User groups** (all_users, Editors, Closers) |
| **Where / scope** | Channels | Chat | **Contact groups** / **Transaction groups** |
| **Permission rule** | Role × channel overwrites | Admin rights bits | **Matrix**: (user_group × contact_group) → allowed actions |
| **Defaults** | @everyone base | Default rights | **all_users**, **all_contacts**, **all_transactions** |

- One resolution path: user → user groups; resource → resource groups; matrix lookup; merge (e.g. union). Same logic for static and dynamic groups.
- Optional: allow/deny (Discord-style) later; start with allow-only.

---

## 3. Action inventory

| Resource | Actions |
|----------|---------|
| **Contact** | `contact:create`, `contact:read`, `contact:update`, `contact:delete` |
| **Transaction** | `transaction:create`, `transaction:read`, `transaction:update`, `transaction:delete`, `transaction:close` |
| **Events** | `events:read` |
| **Wallet** | `wallet:read`, `wallet:update`, `wallet:delete`, `wallet:manage_members` |

---

## 4. Group–group permission model

### 4.1 Two kinds of groups

- **User groups** (who): e.g. all_users, Admins, Editors, Closers, Viewers. Users are assigned to one or more user groups (manually for static; all_users implicit for every wallet member).
- **Contact groups** (scope for contacts): e.g. all_contacts, VIP, Family, Overdue, We_owe, They_owe. Contacts belong to one or more contact groups.
- **Transaction groups** (optional): e.g. all_transactions, Over_limit, Under_limit.

Permissions: **what each user group can do to a given contact group** (and optionally transaction group). Many-to-many.

### 4.2 Static vs dynamic groups

- **Static groups**: Created by admin. **Users** and **contacts** (and optionally transactions) are **added manually**. Tables: `user_group_members`, `contact_group_members`.
- **Dynamic groups**: Membership **computed** from rules, e.g.:
  - Contact: `overdue`, `we_owe`, `they_owe`, `contacts_we_own`, `contacts_they_own`
  - Transaction: `transactions_over_limit`, `transactions_under_limit`
  No membership table; evaluate at resolution time or materialize in a job.

**Default/system groups** (per wallet): **all_users**, **all_contacts**, **all_transactions**. Every member is in all_users; every contact in all_contacts; every transaction in all_transactions.

### 4.3 Permission matrix and resolution

- **Matrix**: For each (user_group, contact_group) [and (user_group, transaction_group)] store allowed **actions** (e.g. `group_permission_matrix(user_group_id, scope_group_id, action_id)`).
- **Resolution**:
  1. Get user's user groups (including all_users if member).
  2. Get resource's groups (contact's contact groups or transaction's transaction groups).
  3. For every (user_group, resource_group) pair, collect allowed actions from the matrix.
  4. Merge (e.g. **union**); optional: explicit denies later.
  5. Requested action in merged set → allow; else 403.

Owner/admin: special user group "Admins" with all actions on all_contacts/all_transactions, or keep short-circuit in code (if wallet role is owner/admin → all actions).

---

## 5. Default group selection (creators) and user settings

- **When creating a contact or transaction**: Users with `contact:create` or `transaction:create` must **choose which groups** the new contact/transaction is added to (or we default). Backend: accept `group_ids` in create payload; validate user can add to those groups.
- **Default group selection**: So creators don't pick every time:
  - **Settings**: "Default groups for new contacts" and "Default groups for new transactions" per (user, wallet), e.g. in `user_wallet_settings`.
  - **Create flow**: If client doesn't send `group_ids`, use user's default for that wallet; else require or fall back to all_contacts / all_transactions.

---

## 6. Schema (outline)

- **permission_actions**: id, name, resource type. Seeded.
- **user_groups**: id, wallet_id, name, is_system. System groups (all_users) seeded per wallet.
- **user_group_members**: user_id, user_group_id. Static; all_users can be implicit.
- **contact_groups**: id, wallet_id, name, type (static | dynamic), definition (JSON for dynamic rules).
- **contact_group_members**: contact_id, contact_group_id. Static only.
- **transaction_groups** / **transaction_group_members**: optional, same idea.
- **group_permission_matrix**: user_group_id, scope_group_id (contact or transaction group), permission_action_id. Unique (user_group_id, scope_group_id, permission_action_id).
- **user_wallet_settings**: wallet_id, user_id, default_contact_group_ids (array), default_transaction_group_ids (array).

---

## 7. Where to enforce (backend)

- **Contacts**: Resolve permission for (user, contact) via contact's groups; require contact:create/read/update/delete. Create: accept group_ids; apply default from settings if missing.
- **Transactions**: Same for (user, transaction); require transaction:* actions. Create: group_ids + default.
- **Sync/events**: Require events:read (e.g. via all_users × all_contacts).
- **Wallets**: Keep require_wallet_role_at_least for manage_members, update, delete.

Single **permission service**: `resolve_allowed_actions(...)` and `can_perform(...)` implementing the resolution; 403 with existing permission code when false.

---

## 8. API (outline)

- **Groups**: CRUD for user groups, contact groups, transaction groups (admin); list/add/remove members for static groups.
- **Matrix**: GET/PUT matrix (user_group × contact_group / transaction_group) – allowed actions. Admin only.
- **Current user**: `GET /api/wallets/:id/me/permissions` (optional resource_type, resource_id) – for UI. Per-resource for edit/delete visibility.
- **Default group selection**: `GET/PUT /api/wallets/:id/me/settings` – default_contact_group_ids, default_transaction_group_ids.
- **Create contact/transaction**: Body may include `group_ids`; if omitted, server uses user's default for that wallet.

---

## 9. Client (mobile / Flutter)

- Load permissions (and per-resource when needed) for current wallet. Show/hide create, edit, delete, close per resource.
- **Settings**: "Default groups for new contacts" / "Default groups for new transactions" – multi-select; save to backend.
- **Create**: Send chosen or default group_ids; allow user to change before submit.
- 403 handling: existing DEBITUM_INSUFFICIENT_WALLET_PERMISSION + toasts.

---

## 10. Implementation order

1. **Schema**: permission_actions, user_groups, user_group_members, contact_groups, contact_group_members, group_permission_matrix (contact scope). Seed all_users, all_contacts, default matrix. Optional: user_wallet_settings.
2. **Permission service**: Resolve user groups, resource groups (static from tables; dynamic from rules), matrix lookup, merge, can_perform.
3. **Handlers**: Permission checks in contact/transaction handlers; group_ids on create + default-from-settings.
4. **APIs**: Groups CRUD, matrix GET/PUT, me/permissions, me/settings (default groups).
5. **Client**: Permissions in state, settings for default groups, create flow with group selection/defaults.
6. **Later**: Dynamic group evaluation, transaction groups, optional allow/deny.

---

## Implemented (Phase 1 backend)

- **Migration 014**: `permission_actions`, `user_groups`, `user_group_members`, `contact_groups`, `contact_group_members`, `group_permission_matrix`, `user_wallet_settings`. Seeded system groups (all_users, all_contacts) and default matrix per wallet.
- **Permission service**: `can_perform`, `resolve_allowed_actions`; owner/admin bypass; matrix resolution for members.
- **Handlers**: Contacts (create/read/update/delete), transactions (create/read/update/delete), sync (get_sync_hash, get_sync_events) check permissions; 403 with `DEBITUM_INSUFFICIENT_WALLET_PERMISSION` when denied.
- **APIs**: `GET /api/wallets/:wallet_id/me/permissions` (optional `?resource_type=&resource_id=`), `GET/PUT /api/wallets/:wallet_id/me/settings` (default_contact_group_ids, default_transaction_group_ids).

**Implemented**: Create contact accepts optional `group_ids`; if omitted, server uses `user_wallet_settings.default_contact_group_ids` for the wallet. New contact is added to those contact groups. Create transaction accepts optional `group_ids` (stored in API only; transaction_groups table not yet added).

**Not yet implemented**: Groups CRUD and matrix admin API; client: fetch permissions and drive UI, settings screen for default groups.

---

## 11. Summary

| Aspect | Choice |
|--------|--------|
| **Model** | Group–group (Discord/Telegram style): user groups × contact/transaction groups → actions. One resolution path. |
| **Groups** | Static (manual membership) + dynamic (computed). Defaults: all_users, all_contacts, all_transactions. |
| **Creators** | Choose groups for new contacts/transactions; **default group selection** stored in **user settings** per wallet. |
| **Storage** | permission_actions, user_groups, user_group_members, contact_groups, contact_group_members, group_permission_matrix, user_wallet_settings (default group IDs). |
| **Enforcement** | Single permission service; 403 with existing code when action not allowed. |
