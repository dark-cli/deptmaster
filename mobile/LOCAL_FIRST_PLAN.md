# Local-First Database Implementation Plan

## Goal
Make the app work with a local-first database approach where:
- All operations (read/write) happen on local database first (instant, snappy)
- Sync happens in background when connection is available or user swipes to refresh
- App works offline with full functionality

## Architecture

### 1. Local Database Service (LocalDatabaseService)
- Wrapper around Hive for all local operations
- Provides methods: getContacts(), getTransactions(), createContact(), updateContact(), etc.
- All operations are synchronous/async but read from/write to local Hive

### 2. Sync Service (SyncService)
- Tracks pending changes (created, updated, deleted items)
- Syncs to server in background
- Handles conflict resolution
- Syncs from server when connection available or manual refresh

### 3. Update Screens
- All screens read from LocalDatabaseService (not ApiService)
- All screens write to LocalDatabaseService (not ApiService)
- SyncService handles background sync automatically

### 4. Pending Changes Tracking
- Store pending operations in a separate Hive box
- Track: operation type (create/update/delete), entity type (contact/transaction), entity data
- Mark as synced when server confirms

## Implementation Steps

1. Create LocalDatabaseService - wrapper for Hive operations
2. Create SyncService - handles background sync and pending changes
3. Update ApiService - add methods that work with sync service
4. Update all screens to use LocalDatabaseService instead of ApiService
5. Add pull-to-refresh to trigger manual sync
6. Add background sync on connection restore
