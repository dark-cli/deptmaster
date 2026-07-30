# Unified Permission System V2: Four-Layer Architecture

**Status:** ✅ NEW STANDARD — Replaces all previous permission system documentation  
**Date:** 2026-07-30  
**Effective:** Now (code implementation to follow)  
**Supersedes:**
- `wallet-permissions-implementation-summary.md` (archived)
- `wallet-permissions-redesign-v2.md` (archived)
- `08-permission-implementation-status.md` (archived)

**Purpose:** Clarify and improve the permission system with better separation of concerns and more intuitive naming.

---

## 🚀 What's New in This Version

This is a **complete redesign** of the permission system architecture:

1. **Four distinct layers** with clear separation of concerns (was unclear before)
2. **Explicit resource types** — Always distinguish `member_group:*` vs `contact_group:*` vs `wallet:*`
3. **Standardized operations** — Consistent naming: read, create, update, delete, add, remove
4. **Vector permissions clarified** — Scoped permissions are now obvious (Layer 2 & 2.5)
5. **No ambiguity** — Each permission does one thing, controlled by one layer



---

## Overview

The permission system has four distinct layers, each controlling different aspects of wallet operations:

1. **Wallet-wide Permissions** — What users in a member_group can do across the entire wallet (structural)
2. **Member-group-to-member-group Permissions** — What one member_group can do to another member_group (administrative control)
3. **Contact Group Management Permissions** — Which member_groups can modify contact_group membership (structural)
4. **Contact/Transaction Permissions** — Granular rules for contact and transaction operations (existing C: T: matrix, operational)

---

## Layer 1: Wallet-Wide Permissions

These permissions control structural access at the wallet level. Any user in a member_group with these permissions can perform them on any resource in the wallet. Layer 1 permissions cannot be overridden by lower layers.

### Wallet Administration

| Permission | Controls | Example Use Case |
|------------|----------|------------------|
| `wallet:info_read` | View wallet metadata (name, description, dates) | See wallet details |
| `wallet:info_update` | Update wallet metadata (name, description) | Rename wallet |
| `wallet:delete` | Soft delete wallet | Archive wallet (OWNERS ONLY - hardcoded) |

### Member Management

| Permission | Controls | Example Use Case |
|------------|----------|------------------|
| `wallet:members_read` | View all members in the wallet | See who has access |
| `wallet:members_add` | Invite/add new members to wallet | Onboard new users |
| `wallet:members_remove` | Remove members from wallet | Offboard users |

### Member Group Management

| Permission | Controls | Example Use Case |
|------------|----------|------------------|
| `wallet:groups_create` | Create new member_groups | Create team groups like "Sellers" |
| `wallet:groups_update` | Update member_group properties + add/remove members to/from member_groups | Reorganize teams, assign members to groups |
| `wallet:groups_delete` | Delete member_groups | Remove obsolete teams |

### Contact Group Management

| Permission | Controls | Example Use Case |
|------------|----------|------------------|
| `wallet:contact_groups_create` | Create new contact_groups | Create contact categories like "Prospects" |
| `wallet:contact_groups_update` | Update contact_group properties | Rename contact groups, set descriptions |
| `wallet:contact_groups_delete` | Delete contact_groups | Remove obsolete contact groups |

**Important:** Adding/removing individual contacts to/from specific contact_groups is **NOT** a wallet-wide permission. It's managed at Layer 2.5, allowing different member_groups to manage different contact_groups.

### Metadata & Discovery

| Permission | Controls | Example Use Case |
|------------|----------|------------------|
| `wallet:metadata_read` | View member_groups, contact_groups, and permission matrix structure | See wallet organization |

### Permissions Configuration

| Permission | Controls | Example Use Case |
|------------|----------|------------------|
| `wallet:permissions_edit` | Modify the permission matrix | Grant/revoke member_group permissions |

---

## Layer 2: Member-Group-to-Member-Group Permissions

These permissions define what one **member_group** can do to another **member_group**. This creates a vector-based (scoped) permission system.

Example: "Sellers Admin" member_group can add/remove members from "Sellers" member_group, but not from "Finance" member_group.

### Member Group Operations (administrative control over other member_groups)

| Permission | Controls | Granularity | Example Use Case |
|------------|----------|------------|------------------|
| `member_group:members_read` | View members in a target member_group | **Per target member_group** | See who's in a team |
| `member_group:members_add` | Add members to a target member_group | **Per target member_group** | Sellers admin adds new sellers to Sellers member_group |
| `member_group:members_remove` | Remove members from a target member_group | **Per target member_group** | Sellers admin removes a seller from Sellers member_group |
| `member_group:permissions_edit` | Modify permissions for a target member_group | **Per target member_group** | Change what a team can do |

---

## Layer 2.5: Contact Group Management Permissions

These permissions define which **member_groups** can modify **contact_group membership** (add/remove specific contacts to/from contact_groups). This is structural control, separate from what people can DO with contacts.

This creates a vector-based (scoped) permission system scoped to specific contact_groups.

Example: "Sellers Team" member_group can add/remove contacts to/from "Prospects" contact_group, but not "Customers" contact_group.

### Contact Group Structure Operations

| Permission | Controls | Granularity | Example Use Case |
|------------|----------|------------|------------------|
| `contact_group:contacts_read` | View which contacts are in a target contact_group | **Per target contact_group** | See contacts in "Prospects" contact_group |
| `contact_group:contacts_add` | Add contacts to a target contact_group | **Per target contact_group** | Sellers team adds contacts to "Prospects" contact_group |
| `contact_group:contacts_remove` | Remove contacts from a target contact_group | **Per target contact_group** | Sellers team removes contacts from "Prospects" contact_group |

**Key Distinction from Layer 3:**
- **Layer 2.5:** "Who can MODIFY which contacts are in a contact_group?" (structural)
- **Layer 3:** "What can a member_group DO with contacts in a contact_group?" (operational)

---

## Layer 3: Contact/Transaction Operational Permissions

These are the existing `C:` and `T:` permissions in the matrix, stored per (member_group → contact_group) pair. They define what operations a member_group can perform on contacts and transactions within a specific contact_group.

### Format

```
C: r:a c:a w:a d:-, T: r:a c:a w:a d:a x:a
```

### Available Actions

**Contacts (C):**
- `r` (read) — View contacts
- `c` (create) — Create new contacts
- `w` (write/update) — Modify contacts
- `d` (delete) — Delete contacts

**Transactions (T):**
- `r` (read) — View transactions
- `c` (create) — Create new transactions
- `w` (write/update) — Modify transactions
- `d` (delete) — Delete transactions
- `x` (close) — Mark as settled/closed

### Three States

- `:a` (allow) — Permission granted
- `:d` (deny) — Permission explicitly blocked
- `:-` (unset) — No decision; check other groups

---

## Permission Resolution Algorithm

When a user performs an action:

1. **Collect all member_groups** the user belongs to
2. **Check wallet-wide permissions** (Layer 1)
   - If granted, proceed with basic operation access
   - If denied, return 403
3. **Check member_group-to-member_group permissions** (Layer 2, if applicable)
   - If the action targets another member_group, check scoped permissions
   - Apply deny-wins rule: if any member_group denies, action is denied
4. **Check contact_group management permissions** (Layer 2.5, if applicable)
   - If the action is adding/removing contacts to a contact_group, check scoped permissions
   - Apply deny-wins rule: if any member_group denies, action is denied
5. **Check contact/transaction operational permissions** (Layer 3, if applicable)
   - If the action is reading/creating/modifying/deleting contacts or transactions, check C: T: permissions
   - Apply deny-wins rule: if any member_group denies, action is denied

---

## Default Permissions

When a wallet is created:

### System Groups Created
- `all_users` (member_group) — Automatically includes all wallet members
- `all_contacts` (contact_group) — Automatically includes all contacts
- `__owners__` (member_group) — Includes the wallet owner

### Default Wallet-Wide Permissions
- `all_users` member_group gets: `wallet:info_read`, `wallet:members_read`, `wallet:metadata_read`
- `__owners__` member_group gets: ALL wallet-wide permissions

### Default Contact/Transaction Permissions
```
all_users member_group → all_contacts contact_group:
  C: r:a c:- w:- d:-
  T: r:a c:- w:- d:- x:-
```
(All members can read all contacts/transactions by default)

---

## Permission Implication Rules

Operations that imply read access:

**Layer 1 (Wallet-wide):**
- `wallet:groups_update` → implies `wallet:groups_read`
- `wallet:groups_delete` → implies `wallet:groups_read`
- `wallet:contact_groups_update` → implies `wallet:contact_groups_read`
- `wallet:contact_groups_delete` → implies `wallet:contact_groups_read`

**Layer 2 (Member-group-to-member-group):**
- `member_group:members_add` → implies `member_group:members_read`
- `member_group:members_remove` → implies `member_group:members_read`
- `member_group:permissions_edit` → implies `member_group:permissions_read`

**Layer 2.5 (Contact-group management):**
- `contact_group:contacts_add` → implies `contact_group:contacts_read`
- `contact_group:contacts_remove` → implies `contact_group:contacts_read`

---

## Operation Consistency Rules

### Read Operations Come First
In each section, `*_read` permissions are listed first, making read operations the foundation.

### Add/Remove Operations
- Paired symmetrically (add always paired with remove)
- Used for collection membership (add/remove member to member_group, add/remove contact to contact_group)
- Apply consistent ordering: read → add → remove

### Create/Update/Delete Operations
- Used for resource management (create member_group, update member_group, delete member_group)
- Kept together in sequence: create → update → delete

---

## Clearer Examples: Permission Scenarios

### Scenario 1: Team Lead Managing Their Team

**Grant these wallet-wide permissions to "TeamLeads" member_group:**
- `wallet:members_read` — See who's in the wallet
- `wallet:metadata_read` — View member_group structure

**Grant these member_group-to-member_group permissions:**
- `member_group:members_read` — View members in target member_group
- `member_group:members_add` — Add new members to their member_group
- `member_group:members_remove` — Remove members from their member_group

**Result:** Team lead can manage their member_group's membership but cannot create new member_groups or change global permissions.

---

### Scenario 2: Finance Admin Managing Multiple Member Groups

**Grant these wallet-wide permissions to "FinanceAdmin" member_group:**
- `wallet:info_read`, `wallet:members_read`, `wallet:metadata_read`
- `wallet:groups_create`, `wallet:groups_update`, `wallet:groups_delete`
- `wallet:permissions_edit`

**Grant these member_group-to-member_group permissions:**
- `member_group:members_read` — View any member_group's members
- `member_group:members_add`, `member_group:members_remove` — Manage any member_group's members
- `member_group:permissions_edit` — Modify permissions for any member_group

**Result:** Finance admin can create member_groups, manage members, and set permissions, acting as a secondary administrator.

---

### Scenario 3: Sellers Admin with Limited Contact_group Access

**Grant these wallet-wide permissions:**
- `wallet:members_read`, `wallet:metadata_read`
- `wallet:groups_update` — Can only edit the "Sellers" member_group (scoped via Layer 2)

**Grant these member_group-to-member_group permissions (Layer 2):**
- `member_group:members_add`, `member_group:members_remove` — Only for "Sellers" member_group
- Can manage team membership but no other member_groups

**Grant these contact_group management permissions (Layer 2.5):**
- `contact_group:contacts_add`, `contact_group:contacts_remove` — Only for "Prospects" and "Customers" contact_groups
- Can add/remove contacts to/from these specific contact_groups

**Grant these contact operational permissions (Layer 3):**
```
"SellersAdmin" member_group → "Prospects" contact_group:
  C: r:a c:a w:a d:-, T: r:a c:- w:- d:- x:-

"SellersAdmin" member_group → "Customers" contact_group:
  C: r:a c:a w:a d:-, T: r:a c:- w:- d:- x:-
```
(Can read/create/edit contacts but not delete or manage transactions)

**Result:** Sellers admin can:
- Manage Sellers member_group membership
- Add/remove contacts to/from Prospects and Customers contact_groups
- View and edit contacts in those contact_groups
- But cannot create new member_groups, delete contacts, or manage transactions

---

## Storage & Implementation Notes

### Layer 2.5: Contact_group Management Vector Storage

`contact_group:contacts_*` permissions are stored in a vector table:

```sql
Table: group_contact_group_permissions
Columns:
  - member_group_id (source: which member_group has the permission)
  - contact_group_id (target: which contact_group they can manage)
  - action (e.g., "contact_group:contacts_add")
  - is_allow (true for allow, false for deny)
```

This mirrors the member_group-to-member_group vector but targets contact_groups instead of member_groups.

---

## Summary of Changes

| Layer | Old System | New System | Storage | Distinction |
|-------|-----------|-----------|---------|------------|
| **Layer 1** | Unclear (info_read covered everything) | Specific wallet-wide permissions | Wallet permission matrix | Structural operations at wallet level |
| **Layer 2** | Existing `group:members_add` etc. | `member_group:members_*` (explicit resource) | Member_group permission vector | Administrative control between member_groups |
| **Layer 2.5** | Mixed with operational permissions | `contact_group:contacts_*` (explicit resource) | Contact_group permission vector | Structural control of contact_group membership |
| **Layer 3** | `C: r:a c:a w:a d:a` format | Same (no change) | Permission matrix (member_group → contact_group) | Operational permissions on data |

---

## Open Questions

1. Should `wallet:metadata_read` be one permission or separate ones?
   - **Proposal:** One permission since viewing structure is atomic operation
   
2. Storage approach for Layer 2.5 permissions?
   - **Proposal:** Separate conceptual layer but can share DB table if convenient (distinguish by action name prefix)
   
3. Should there be intermediate roles?
   - **Proposal:** No — let implementation define via permission assignments

---

## Related Documents

- [[05-permission-format-system.md]] — Contact/Transaction permission format (C: T: notation)
- [[09-permission-defaults-and-scoped-access.md]] — Default permissions and scoped access
- [[06-owner-permission-threat-model.md]] — Security model for owner-only operations

---

## Migration from Old System

### Old Documents (Archived)
The following documents have been **archived and replaced** by this specification:
- `wallet-permissions-implementation-summary.md` → See `.trash/wallet-permissions-implementation-summary-OLD.md`
- `wallet-permissions-redesign-v2.md` → See `.trash/wallet-permissions-redesign-v2-OLD.md`
- `08-permission-implementation-status.md` → See `.trash/08-permission-implementation-status-OLD.md`

### What Changed
1. **Architecture:** Four-layer model (was three-layer, was confusing)
2. **Naming:** Explicit resource types (`member_group:*`, `contact_group:*`, `wallet:*`)
3. **Clarity:** Each permission does one thing, at one layer
4. **Scoping:** Vector permissions (Layer 2, 2.5) are now visually distinct from wallet-wide (Layer 1)

### Implementation Steps
1. ✅ Document approved and standardized (this document)
2. ⏳ Update `Action` enum in Rust code with new permission names
3. ⏳ Update handlers to use new permission names
4. ⏳ Database migration for permission names (if needed)
5. ⏳ Update client code and tests
6. ⏳ Verify backward compatibility (if needed during transition)

### For Developers
- Use this document as the **source of truth** for permission architecture
- All new permission checks should use Layer 1/2/2.5/3 structure
- Refer to examples and scenarios when implementing
- Contact the team if clarification is needed on any permission scope
