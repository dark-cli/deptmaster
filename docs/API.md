# API Reference

## Base URL
- Development: `http://localhost:8000`
- Production: (TBD)

## Authentication

Currently unauthenticated. Future: JWT tokens.

## Endpoints

### Health Check
```
GET /health
```
Returns: `"OK"`

### WebSocket
```
WS /ws
```
Real-time updates connection. Sends JSON messages:
```json
{
  "type": "contact_created" | "contact_updated" | "transaction_created" | "transaction_updated",
  "data": { ... }
}
```

### Contacts

#### Create Contact
```
POST /api/contacts
Content-Type: application/json
Idempotency-Key: {uuid} (optional)
```

Request:
```json
{
  "name": "John Doe",
  "phone": "+1234567890",
  "email": "john@example.com",
  "notes": "Optional notes"
}
```

Response (201 Created):
```json
{
  "id": "uuid",
  "name": "John Doe",
  "balance": 0
}
```

#### Update Contact
```
PUT /api/contacts/{id}
Content-Type: application/json
```

Request:
```json
{
  "name": "Jane Doe",
  "phone": "+1234567890",
  "email": "jane@example.com",
  "notes": "Updated notes"
}
```

#### Delete Contact
```
DELETE /api/contacts/{id}
```

#### Get Contacts (Admin)
```
GET /api/admin/contacts
```

Response (200 OK):
```json
[
  {
    "id": "uuid",
    "user_id": "uuid",
    "name": "John Doe",
    "phone": "+1234567890",
    "email": "john@example.com",
    "notes": "Notes",
    "is_deleted": false,
    "created_at": "2026-01-18T00:00:00Z",
    "updated_at": "2026-01-18T00:00:00Z"
  }
]
```

### Transactions

#### Create Transaction
```
POST /api/transactions
Content-Type: application/json
Idempotency-Key: {uuid} (optional)
```

Request:
```json
{
  "contact_id": "uuid",
  "amount": 5000,
  "currency": "USD",
  "direction": "owed",
  "description": "Lent money",
  "transaction_date": "2026-01-18T00:00:00Z",
  "due_date": "2026-02-18T00:00:00Z" (optional)
}
```

Response (201 Created):
```json
{
  "id": "uuid",
  "contact_id": "uuid",
  "amount": 5000,
  "currency": "USD",
  "direction": "owed",
  "description": "Lent money",
  "transaction_date": "2026-01-18T00:00:00Z"
}
```

#### Update Transaction
```
PUT /api/transactions/{id}
Content-Type: application/json
```

#### Delete Transaction
```
DELETE /api/transactions/{id}
```

#### Get Transactions (Admin)
```
GET /api/admin/transactions
```

Response (200 OK):
```json
[
  {
    "id": "uuid",
    "contact_id": "uuid",
    "amount": 5000,
    "currency": "USD",
    "direction": "owed",
    "description": "Lent money",
    "transaction_date": "2026-01-18T00:00:00Z",
    "is_deleted": false,
    "created_at": "2026-01-18T00:00:00Z",
    "updated_at": "2026-01-18T00:00:00Z"
  }
]
```

### Events

#### Get Events (Admin)
```
GET /api/admin/events?event_type={type}&aggregate_type={type}&limit={n}&offset={n}
```

Query Parameters:
- `event_type`: Filter by event type (e.g., `CREATED`, `UPDATED`, `DELETED`)
- `aggregate_type`: Filter by aggregate type (e.g., `contact`, `transaction`)
- `limit`: Number of events to return (default: 100)
- `offset`: Pagination offset (default: 0)

Response (200 OK):
```json
[
  {
    "id": "uuid",
    "aggregate_id": "uuid",
    "aggregate_type": "contact",
    "event_type": "CONTACT_CREATED",
    "event_data": {...},
    "timestamp": "2026-01-18T00:00:00Z"
  }
]
```

#### Delete Event (Admin)
```
DELETE /api/admin/events/{event_id}
```

Only allowed if event is less than 5 seconds old (for undo functionality).

### Projections

#### Get Projection Status
```
GET /api/admin/projections/status
```

Response (200 OK):
```json
{
  "last_event_id": 12345,
  "is_up_to_date": true
}
```

#### Rebuild Projections
```
POST /api/admin/projections/rebuild
```

Rebuilds all projections from events. Returns:
```json
{
  "status": "success",
  "events_processed": 12345
}
```

## Error Responses

### 400 Bad Request
```json
{
  "error": "Invalid request data"
}
```

### 404 Not Found
```json
{
  "error": "Resource not found"
}
```

### 409 Conflict
```json
{
  "error": "Version conflict - resource was modified"
}
```

### 500 Internal Server Error
```json
{
  "error": "Internal server error"
}
```

## Rate Limiting

Not currently implemented. Planned for production.

## Related Documentation

- [Architecture](./ARCHITECTURE.md) - System architecture
- [Development Guide](./DEVELOPMENT.md) - Development setup
