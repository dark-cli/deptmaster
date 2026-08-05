# Wallet Management UI Redesign

**Status:** ✅ COMPLETE  
**Date:** 2026-08-05  
**Scope:** Flutter mobile app - wallet management screen only

## Problem

The current wallet management screen uses a TabBar with 6 tabs:
- Members
- User Groups
- Contact Groups
- Rules (Permission Matrix)
- Wallet Permissions
- Member Permissions

**Issues:**
- ❌ 6 tabs overflow on mobile screens
- ❌ Tab labels compress, hard to read
- ❌ Related sections scattered (Groups separate from Permissions)
- ❌ Unclear information hierarchy

## Solution: Android Settings-Style Layout

Replace TabBar with hierarchical list navigation (Android Settings pattern):

```
AppBar: "Manage: Wallet Name"
────────────────────────────────────
│ 👥 PEOPLE & ACCESS                │
│   ├─ Members                   [>] │
│   └─ Invite by Code            [>] │
├────────────────────────────────────┤
│ 📦 GROUPS (consolidated)           │
│   ├─ User Groups               [>] │
│   ├─ Contact Groups            [>] │
│   └─ Group Members & Contacts  [>] │
├────────────────────────────────────┤
│ 🔒 PERMISSIONS                     │
│   ├─ Permission Rules           [>] │
│   ├─ Member Permissions         [>] │
│   └─ Contact Permissions        [>] │
├────────────────────────────────────┤
│ ⚙️  WALLET SETTINGS                │
│   ├─ Wallet Permissions         [>] │
│   ├─ Rename Wallet              [>] │
│   ├─ Leave Wallet               [>] │
│   └─ Delete Wallet              [>] │
────────────────────────────────────
```

## Benefits

✅ Only 4 main sections (cleaner, organized by function)  
✅ All group management consolidated in one place  
✅ Wallet-level config clearly separated in Settings  
✅ Operational permissions logically grouped  
✅ Easier to scan and navigate on mobile  
✅ Room for future features without redesign  

## Implementation Plan

### Phase 1: Layout Structure
- [ ] Create new `manage_wallet_screen.dart` with ListView (replace TabBar)
- [ ] Create section card/tile widget
- [ ] Implement navigation to sub-screens

### Phase 2: Extract to Sub-Screens
- [ ] Create `wallet_management/people_section.dart`
- [ ] Create `wallet_management/groups_section.dart`
- [ ] Create `wallet_management/permissions_section.dart`
- [ ] Create `wallet_management/settings_section.dart`

### Phase 3: Consolidate Groups
- [ ] Merge User Groups + Contact Groups into single Groups sub-screen
- [ ] Show unified group member/contact management

### Phase 4: Polish & Test
- [ ] Navigation state management
- [ ] Refresh handling
- [ ] Error states
- [ ] Responsive layout

## File Structure (New)

```
mobile/lib/screens/
├─ manage_wallet_screen.dart (main list view)
└─ wallet_management/
   ├─ people_section.dart
   ├─ groups_section.dart
   ├─ permissions_section.dart
   ├─ wallet_settings_section.dart
   └─ section_card_tile.dart
```

## Backward Compatibility

- Dart UI only - no Rust client changes needed
- All API calls remain the same
- Logic unchanged - only presentation redesigned

## Implementation Complete (2026-08-05)

### ✅ Files Created/Modified

**New Screens Implemented:**
- `wallet_management/wallet_permissions_screen.dart` — Wallet-level delegable permissions (+ toggle UI)
- `wallet_management/member_permissions_screen.dart` — Member-group-scoped delegable permissions (+ toggle UI)
- `wallet_management/contact_permissions_screen.dart` — Contact-group-scoped delegable permissions (+ toggle UI)
- `wallet_management/permission_rules_screen.dart` — Permission matrix display (read-only)

**Updated Screens:**
- `wallet_management/contact_groups_screen.dart` — Added "Add contact" dialog with contact selection
- `wallet_management/user_groups_screen.dart` — Added "Add member" dialog with user selection

**Main Layout:**
- `manage_wallet_screen.dart` — 4-section Android Settings-style layout (replaced TabBar)

**Widgets:**
- `widgets/management_section_card.dart` — Reusable section header + tile list widget
- `widgets/invite_code_dialog.dart` — Extracted 4-digit invite code dialog

**API Extensions:**
- `api.dart` — Added getContactGroupPermissions() and setContactGroupPermissions() methods

### ✅ Features Implemented

**Wallet Permissions Screen:**
- Load wallet-level delegable permissions from API
- Display permissions with source_group_id and action
- Toggle allow/deny state (inline button)
- Error handling for permission denied

**Member Permissions Screen:**
- Load member-group-scoped delegable permissions
- Display source→target group relationships
- Toggle allow/deny state per action
- Error handling for permission denied

**Contact Permissions Screen:**
- Load contact-group-scoped delegable permissions
- Display source_group_id → contact_group_id relationships
- Toggle allow/deny state per action
- Error handling for permission denied

**Permission Rules Screen:**
- Load permission matrix (role-based access matrix)
- Display in card-based list format
- Shows role, action, and allowed/denied status
- Read-only (display only)

**"Add Contact" Dialog:**
- Select from available contacts not already in group
- RadioListTile for clean selection UX
- Auto-close on selection
- Toast confirmation on success/error
- Handles "all in group" case gracefully

**"Add Member" Dialog:**
- Select from available users not already in group
- RadioListTile for clean selection UX
- Auto-close on selection
- Toast confirmation on success/error
- Handles "all in group" case gracefully

### Removed
- `manage_wallet_screen.dart.bak` — Old TabBar version (backup no longer needed)
