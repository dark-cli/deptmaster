# Event Audit Trail - Complete Traceability

## Overview

Every action in the system creates an **immutable event** that provides a complete audit trail. Events are stored in both PostgreSQL (for queries) and EventStore (for event sourcing).

## Event Information Structure

Each event contains the following information to answer the key questions:

### 1. **Who did the action?**
- `user_id` - UUID of the user who performed the action
- Stored in both the events table and event_data JSON

### 2. **When was the action done?**
- `created_at` - Timestamp when the event was created (in events table)
- `timestamp` - ISO 8601 timestamp in event_data JSON (RFC3339 format)
- Both timestamps ensure precise timing information

### 3. **What is the action type?**
- `event_type` - The type of action performed:
  - `ContactCreated` - New contact was created
  - `ContactUpdated` - Contact was modified
  - `ContactDeleted` - Contact was soft-deleted
  - `TransactionCreated` - New transaction was created
  - `TransactionUpdated` - Transaction was modified
  - `TransactionDeleted` - Transaction was soft-deleted

### 4. **What is the data?**
- `event_data` - Complete JSON object containing:
  - **For Create**: All the data that was created
  - **For Update**: New values + `previous_values` object showing what changed
  - **For Delete**: `deleted_contact` or `deleted_transaction` object with the data that was deleted

### 5. **Why was the action done? (Comment/Reason)**
- `comment` - User's explanation for the action:
  - **Required for Create operations** - User must explain why they're creating the contact/transaction
  - **Optional for Update operations** - Recommended but not required
  - **Optional for Delete operations** - Recommended but not required (defaults to "No comment provided" if missing)

## Complete Event Structure

### Example: ContactCreated Event

```json
{
  "user_id": "550e8400-e29b-41d4-a716-446655440000",
  "name": "John Doe",
  "username": "johndoe",
  "phone": "+1234567890",
  "email": "john@example.com",
  "notes": "Friend from work",
  "comment": "Met at conference, need to track expenses",
  "timestamp": "2026-01-20T01:15:14.3151881Z"
}
```

### Example: ContactUpdated Event

```json
{
  "name": "John Doe Updated",
  "username": "johndoe",
  "phone": "+1234567890",
  "email": "john.new@example.com",
  "notes": "Updated email address",
  "comment": "User changed their email",
  "timestamp": "2026-01-20T02:00:00.0000000Z",
  "previous_values": {
    "name": "John Doe",
    "username": "johndoe",
    "phone": "+1234567890",
    "email": "john@example.com",
    "notes": "Friend from work"
  }
}
```

### Example: ContactDeleted Event

```json
{
  "comment": "Contact moved to different system",
  "timestamp": "2026-01-20T03:00:00.0000000Z",
  "deleted_contact": {
    "name": "John Doe Updated",
    "username": "johndoe",
    "phone": "+1234567890",
    "email": "john.new@example.com",
    "notes": "Updated email address"
  }
}
```

## Database Schema

Events are stored in the `events` table with the following structure:

```sql
CREATE TABLE events (
    id BIGSERIAL PRIMARY KEY,
    event_id UUID NOT NULL UNIQUE,
    user_id UUID NOT NULL,              -- Who
    aggregate_type VARCHAR(50),         -- 'contact' or 'transaction'
    aggregate_id UUID,                  -- ID of the contact/transaction
    event_type VARCHAR(100),            -- What type (ContactCreated, etc.)
    event_version INTEGER DEFAULT 1,
    event_data JSONB NOT NULL,          -- Complete data + comment + timestamp
    metadata JSONB,
    created_at TIMESTAMP NOT NULL       -- When
);
```

## EventStore Structure

Events are also written to EventStore streams:
- Stream name: `contact-{uuid}` or `transaction-{uuid}`
- Each event is immutable and append-only
- Stream version tracks the sequence of events

## API Requirements

### Creating Contacts/Transactions
**Comment is REQUIRED**

```json
POST /api/contacts
{
  "name": "John Doe",
  "comment": "Met at conference"  // REQUIRED
}
```

### Updating Contacts/Transactions
**Comment is OPTIONAL** (but recommended)

```json
PUT /api/contacts/{id}
{
  "name": "John Updated",
  "comment": "User requested name change"  // Optional
}
```

### Deleting Contacts/Transactions
**Comment is OPTIONAL** (but recommended)

```json
DELETE /api/contacts/{id}
{
  "comment": "No longer needed"  // Optional, defaults to "No comment provided"
}
```

## Benefits

1. **Complete Traceability**: Every change is recorded with who, when, what, and why
2. **Immutable History**: Events cannot be modified or deleted
3. **Audit Compliance**: Full audit trail for compliance requirements
4. **Debugging**: Can replay events to understand how data reached current state
5. **User Accountability**: Comments require users to explain their actions

## Querying Events

### Get all events for a user
```sql
SELECT * FROM events 
WHERE user_id = '...' 
ORDER BY created_at DESC;
```

### Get events for a specific contact
```sql
SELECT * FROM events 
WHERE aggregate_type = 'contact' 
  AND aggregate_id = '...' 
ORDER BY created_at ASC;
```

### Get events with comments
```sql
SELECT event_type, event_data->>'comment' as comment, created_at
FROM events
WHERE event_data->>'comment' IS NOT NULL
ORDER BY created_at DESC;
```

## Event Sourcing Benefits

With this structure, you can:
1. **Replay events** to rebuild current state
2. **Time travel** to see what data looked like at any point
3. **Audit changes** to see who changed what and why
4. **Debug issues** by tracing the sequence of events
5. **Generate reports** on user activity

## Immutability

- Events are **append-only** - never modified or deleted
- EventStore ensures events cannot be changed
- PostgreSQL events table also maintains immutability
- Soft deletes mark items as deleted but preserve history
