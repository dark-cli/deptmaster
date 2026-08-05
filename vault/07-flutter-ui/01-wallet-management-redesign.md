# Wallet Management UI Redesign

**Status:** Planning → Implementation  
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
