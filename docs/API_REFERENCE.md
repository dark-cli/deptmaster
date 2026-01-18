# API Reference

## Base URL
- Development: `http://localhost:8000`
- Production: (TBD)

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
  "type": "contact_created" | "transaction_created",
  "data": { ... }
}
```

### Contacts

#### Create Contact
```
POST /api/contacts
Content-Type: application/json
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
```

Request:
```json
{
  "contact_id": "uuid",
  "amount": 5000,
  "currency": "USD",
  "direction": "owed",
  "description": "Lent money",
  "transaction_date": "2026-01-18T00:00:00Z"
}
```

Response (201 Created):
```json
{
  "id": "uuid",
  "contact_id": "uuid"
}
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
    "created_at": "2026-01-18T00:00:00Z",
    "updated_at": "2026-01-18T00:00:00Z"
  }
]
```

### Admin Endpoints

#### Get Events
```
GET /api/admin/events
```

Returns all events from event store.

#### Get Projection Status
```
GET /api/admin/projections/status
```

Returns status of all projections.

#### Admin Panel
```
GET /admin
```

HTML admin interface for monitoring and debugging.

## Error Responses

### 400 Bad Request
```json
{
  "error": "Validation error message"
}
```

### 500 Internal Server Error
```json
{
  "error": "Internal server error message"
}
```

## WebSocket Events

### Contact Created
```json
{
  "type": "contact_created",
  "data": {
    "id": "uuid",
    "name": "John Doe",
    "balance": 0
  }
}
```

### Transaction Created
```json
{
  "type": "transaction_created",
  "data": {
    "id": "uuid",
    "contact_id": "uuid"
  }
}
```

## Status Codes

- `200 OK` - Success
- `201 Created` - Resource created
- `400 Bad Request` - Invalid request
- `404 Not Found` - Resource not found
- `500 Internal Server Error` - Server error
- `501 Not Implemented` - Feature not yet implemented
