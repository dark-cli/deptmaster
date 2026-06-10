-- Add idempotency keys to events table
ALTER TABLE events 
ADD COLUMN idempotency_key VARCHAR(255) UNIQUE;

CREATE INDEX idx_events_idempotency ON events(idempotency_key) WHERE idempotency_key IS NOT NULL;

-- Add version tracking to projections
ALTER TABLE contacts_projection 
ADD COLUMN version INTEGER NOT NULL DEFAULT 1;

ALTER TABLE transactions_projection 
ADD COLUMN version INTEGER NOT NULL DEFAULT 1;

-- Add version indexes for conflict detection
CREATE INDEX idx_contacts_version ON contacts_projection(id, version);
CREATE INDEX idx_transactions_version ON transactions_projection(id, version);

-- Add sync tracking table for clients
CREATE TABLE client_sync_state (
    id BIGSERIAL PRIMARY KEY,
    client_id VARCHAR(255) NOT NULL,
    user_id UUID NOT NULL REFERENCES users_projection(id),
    last_synced_event_id BIGINT NOT NULL REFERENCES events(id),
    last_synced_at TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE(client_id, user_id)
);

CREATE INDEX idx_sync_state_user ON client_sync_state(user_id);
CREATE INDEX idx_sync_state_event ON client_sync_state(last_synced_event_id);

-- Add comment explaining idempotency
COMMENT ON COLUMN events.idempotency_key IS 'Client-provided key to prevent duplicate operations. If same key is used, return existing result.';
COMMENT ON COLUMN contacts_projection.version IS 'Increments on each update. Used for optimistic locking and conflict detection.';
COMMENT ON COLUMN transactions_projection.version IS 'Increments on each update. Used for optimistic locking and conflict detection.';
