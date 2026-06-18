# IBM Carbon Redesign: Information Architecture

**Branch**: `flutter/carbon-redesign`  
**Status**: Planning phase  
**Dates**: 2026-06-19 onwards

## Overview

This document defines the **user-facing information** that must be preserved during the UI redesign to IBM Carbon design system. The layout, typography, spacing, colors, and widget styles are NOT preserved—only the data structure and logical flow that users interact with.

## Principle

> "Only preserve the information architecture (what data users see). Everything else—layout, fonts, widget sizes, color palette, component styles—follows IBM Carbon code completely."

## Information Architecture by Screen

### 1. Authentication Flow

#### Login Screen
- **Fields**: 
  - Username input field
  - Password input field
  - Remember me (optional)
- **Actions**:
  - Login submission
  - Navigate to sign-up
  - Backend configuration option (dev/debug)
- **Feedback**:
  - Loading state during submission
  - Error messages if login fails

#### Sign-Up Screen
- **Fields**:
  - Username
  - Password
  - Password confirmation
- **Actions**:
  - Register new account
  - Navigate back to login

### 2. Wallet Management

#### Wallet Selection / List Screen
- **Data displayed per wallet**:
  - Wallet name
  - Wallet description
  - Wallet balance summary (optional)
- **Actions**:
  - Select a wallet (set as current)
  - Create new wallet
  - Manage wallet (roles, permissions, users)
- **Info**: Current wallet is persistent (user preference)

#### Wallet Creation Screen
- **Fields**:
  - Wallet name
  - Wallet description
- **Actions**:
  - Create wallet
  - Cancel

#### Manage Wallet Screen
- **Sections**:
  - User list with roles (owner, admin, member, viewer)
  - Invite code generation
  - User groups management
  - Contact groups management
- **Actions**:
  - Add user by username
  - Change user role
  - Remove user
  - Create/edit/delete user groups
  - Create/edit/delete contact groups
  - Revoke invite code
  - Generate new invite code

### 3. Dashboard / Home Screen

#### Summary Card
- **Data**:
  - Total balance (numerical, IQD currency)
  - Total contact count
  - Total transaction count
- **Visual**: Large, prominent display (user sees this first)

#### Outstanding Balances Chart
- **Two-column layout** (responsive: stacks on small screens):
  - **"Gave" column** (you owe people):
    - Top 5 contacts by debt amount
    - Per contact: name, username, balance (IQD)
    - Sorted by highest amount owed
  - **"Received" column** (people owe you):
    - Top 5 contacts by credit amount
    - Per contact: name, username, balance (IQD)
    - Sorted by highest amount owed to you
- **Interaction**: Tap contact → see all transactions with that contact
- **Long-press**: Quick debt-close action (add reverse transaction)

#### Debt Over Time Chart (Optional)
- Shows historical balance trend
- Can be toggled on/off in settings

#### Payment Reminders Section
- **Shown if due dates enabled in settings**
- **Data per transaction**:
  - Contact name
  - Contact username
  - Amount (IQD)
  - Due date
  - Status badge: "Overdue" (red) or "N days" (yellow)
  - Sorted: overdue first, then by soonest due date
- **Display**: Up to 10 upcoming/overdue (within 30 days)
- **Interaction**: Tap → see all transactions with that contact

#### Sync Status
- Indicator icon showing connection status (real-time WebSocket sync)
- Pull-to-refresh functionality

### 4. Contacts Screen

#### Contacts List
- **Per contact**:
  - Name (large)
  - Username (if available, smaller text)
  - Balance indicator with color (green = credit, red = debt)
  - Balance amount (IQD)
  - Last modified date (optional)
  - Transaction count (optional)
- **Features**:
  - Search/filter by name or username
  - Sort options:
    - Alphabetical A-Z (default)
    - Alphabetical Z-A
    - Balance: high to low
    - Balance: low to high
    - Most recent
    - Oldest
  - Multi-select mode (for bulk delete)
  - Swipe actions (edit, delete, or custom)
- **Interaction**:
  - Tap contact → see all transactions with that contact
  - Tap "+" or action → add new transaction
  - Long-press → edit contact
  - Swipe → quick actions

#### Add Contact Screen
- **Fields**:
  - Name (required)
  - Username (optional)
  - Phone (optional)
  - Email (optional)
  - Notes (optional)
  - Contact groups (optional, multi-select)
- **Actions**:
  - Create contact
  - Cancel

#### Edit Contact Screen
- **Fields**: Same as Add Contact
- **Actions**:
  - Update contact
  - Cancel
  - Delete contact (with confirmation)

#### Contact Groups Management
- **List of groups** with member count
- **Per group**:
  - Group name
  - Number of contacts in group
- **Actions**:
  - Create new group
  - Edit group name
  - Delete group
  - Add/remove contacts from group

### 5. Transactions Screen

#### Transactions List
- **Per transaction**:
  - Contact name
  - Transaction type (expense, debt, etc.)
  - Direction indicator (paid, received, lent, borrowed)
  - Amount (IQD, with +/- sign)
  - Date (transaction date)
  - Due date (if present, optional display)
  - Currency
  - Status (normal, undone, etc.)
  - Description (if provided)
- **Features**:
  - Search/filter
  - Sort by amount, date, type
  - Filter by contact
  - Filter by transaction direction
  - Multi-select for bulk delete
- **Interaction**:
  - Tap → view/edit transaction details
  - Swipe → quick delete or edit

#### Add Transaction Screen
- **Fields**:
  - Contact selection (required)
  - Amount (required, IQD)
  - Type (expense, debt, etc.)
  - Direction (paid/received/lent/borrowed)
  - Currency (default IQD)
  - Transaction date (required)
  - Due date (optional)
  - Description (optional)
- **Actions**:
  - Create transaction
  - Cancel

#### Edit Transaction Screen
- **Fields**: Same as Add Transaction
- **Actions**:
  - Update transaction
  - Cancel
  - Delete transaction

#### Contact Transactions Screen
- **Data specific to one contact**:
  - Contact header (name, balance with this contact)
  - List of all transactions with this contact
  - Running balance (cumulative impact of each transaction)
  - Same transaction fields as main list
- **Actions**:
  - Add new transaction with this contact
  - Edit/delete existing transactions

### 6. Permissions & Access Control Screen

#### Permission Matrix Viewer
- **Display**: Table or card-based view of:
  - Rows: Actions (contact:read, contact:create, transaction:read, transaction:update, etc.)
  - Columns: User groups or individual users
  - Cells: Permission state (allowed, denied, inherit)
- **User groups** section:
  - List of user groups in wallet
  - Create/edit/delete groups
  - Add/remove users from groups
- **Permission matrix editing**:
  - Modify permission cells
  - Batch update permissions
  - Reset to defaults

### 7. Settings Screen

#### User Profile
- Username (read-only, derived from JWT)
- Logout button

#### Wallet Settings (if accessible)
- Color flip option (swap debt/credit colors)
- Due date reminder toggle
- Dashboard chart visibility toggle
- Default transaction direction setting
- Undo/redo history viewer

#### App-Level Settings
- Theme (light/dark)
- Language/localization
- Debug logging (dev builds)

### 8. Events Log / Audit Screen

#### Event History
- **Per event**:
  - Event type (ContactCreated, TransactionUpdated, etc.)
  - Entity (which contact, transaction, wallet)
  - User who triggered it
  - Timestamp
  - Details (what changed)
- **Features**:
  - Filter by event type
  - Filter by entity
  - Search
  - Sort by date
- **Info**: Shows all events in wallet (read-only, audit trail)

## Visual Elements to Preserve

### Glitching Effect
- **Current implementation**: Animated visual distortion/corruption effect on certain text and UI elements
- **Preserve in Carbon**: Implement as an optional visual layer or custom animation overlay that respects Carbon's constraints
- **Placement**: TBD during implementation (possibly on summary balance, status indicators, or as a subtle background effect)
- **Requirement**: Must not break accessibility or readability; should enhance, not hinder

## Currency & Localization

- **Primary currency**: IQD (Iraqi Dinar)
- **Display format**: Numeric with locale-specific formatting (commas for thousands)
- **RTL support**: App supports right-to-left layouts (Arabic, etc.)
- **Preserve**: All currency/amount formatting logic and RTL behavior

## Accessibility Requirements

- All interactive elements must be keyboard accessible (Carbon provides this)
- Color should not be the only way to convey information (use text labels, icons, patterns)
- Balance indicators: combine color with symbols/icons and text
- Form validation: clear error messages

## Responsive Behavior

- **Mobile-first**: Design for small screens (phones)
- **Responsive**: Adapt gracefully to tablets (landscape/portrait)
- **Key layouts**:
  - Two-column layouts should stack on screens < 600dp wide
  - Lists should remain scrollable, not compress
  - Cards should maintain readable text size at all breakpoints

## No Preserved Decisions

The following are **explicitly discarded**—do not preserve them in the new design:

- ❌ Current color palette (use Carbon's)
- ❌ Current typography/font sizes (use Carbon's)
- ❌ Current spacing/padding/margins (use Carbon's 4pt/8pt grid)
- ❌ Current component styling (use Carbon components)
- ❌ Current animation speeds/styles (unless glitching effect requires preservation)
- ❌ Current card or layout container designs
- ❌ Current icon styles (use Carbon icon library)
- ❌ Current form input styles (use Carbon form components)
- ❌ Current button styles (use Carbon buttons)

## Next Steps

1. **Study IBM Carbon Design System**: https://carbon.ibm.com
   - Typography tokens
   - Color palette and semantic tokens
   - Component library (buttons, inputs, cards, modals, etc.)
   - Layout grid and spacing system
   - Accessibility guidelines

2. **Map information architecture to Carbon components**:
   - Which Carbon component for each screen section?
   - How does data display in Carbon's card/table/list components?

3. **Prototype key screens** in order of priority:
   - Login/auth (simplest)
   - Dashboard (most visually complex)
   - Contacts list
   - Transaction list
   - Permissions matrix

4. **Integrate glitching effect** once core layout is stable

5. **Accessibility & testing**: Audit with Carbon's accessibility guidelines
