-- Event Store (Write-only append log)
CREATE TABLE events (
    id BIGSERIAL PRIMARY KEY,
    event_id UUID NOT NULL UNIQUE DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    aggregate_type VARCHAR(50) NOT NULL,
    aggregate_id UUID NOT NULL,
    event_type VARCHAR(100) NOT NULL,
    event_version INTEGER NOT NULL DEFAULT 1,
    event_data JSONB NOT NULL,
    metadata JSONB,
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_events_user_aggregate ON events(user_id, aggregate_type, aggregate_id);
CREATE INDEX idx_events_user_created ON events(user_id, created_at DESC);
CREATE INDEX idx_events_aggregate ON events(aggregate_type, aggregate_id);
CREATE INDEX idx_events_type ON events(event_type);
CREATE INDEX idx_events_data_gin ON events USING GIN (event_data);

-- Users projection
CREATE TABLE users_projection (
    id UUID PRIMARY KEY,
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    created_at TIMESTAMP NOT NULL,
    last_event_id BIGINT NOT NULL
);

-- Contacts projection
CREATE TABLE contacts_projection (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users_projection(id),
    name VARCHAR(255) NOT NULL,
    phone VARCHAR(50),
    email VARCHAR(255),
    notes TEXT,
    linked_contact_uri TEXT,
    is_deleted BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP NOT NULL,
    updated_at TIMESTAMP NOT NULL,
    last_event_id BIGINT NOT NULL
);

CREATE INDEX idx_contacts_user ON contacts_projection(user_id) WHERE is_deleted = FALSE;

-- Transactions projection
CREATE TABLE transactions_projection (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users_projection(id),
    contact_id UUID NOT NULL REFERENCES contacts_projection(id),
    type VARCHAR(20) NOT NULL CHECK (type IN ('money', 'item')),
    direction VARCHAR(20) NOT NULL CHECK (direction IN ('owed', 'lent')),
    amount BIGINT NOT NULL,
    currency VARCHAR(3) DEFAULT 'USD',
    description TEXT,
    transaction_date DATE NOT NULL,
    is_settled BOOLEAN DEFAULT FALSE,
    settled_at TIMESTAMP,
    is_deleted BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP NOT NULL,
    updated_at TIMESTAMP NOT NULL,
    last_event_id BIGINT NOT NULL
);

CREATE INDEX idx_transactions_user_date ON transactions_projection(user_id, transaction_date DESC) WHERE is_deleted = FALSE;
CREATE INDEX idx_transactions_contact ON transactions_projection(contact_id) WHERE is_deleted = FALSE;

-- Transaction Images projection
CREATE TABLE transaction_images_projection (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    transaction_id UUID NOT NULL REFERENCES transactions_projection(id),
    image_url TEXT NOT NULL,
    is_deleted BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP NOT NULL,
    last_event_id BIGINT NOT NULL
);

-- Reminders projection
CREATE TABLE reminders_projection (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users_projection(id),
    transaction_id UUID REFERENCES transactions_projection(id),
    reminder_type VARCHAR(50) NOT NULL,
    scheduled_at TIMESTAMP NOT NULL,
    sent_at TIMESTAMP,
    status VARCHAR(20) DEFAULT 'pending',
    is_deleted BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP NOT NULL,
    last_event_id BIGINT NOT NULL
);

CREATE INDEX idx_reminders_user_scheduled ON reminders_projection(user_id, scheduled_at) WHERE is_deleted = FALSE AND status = 'pending';

-- Snapshots
CREATE TABLE snapshots (
    id BIGSERIAL PRIMARY KEY,
    aggregate_type VARCHAR(50) NOT NULL,
    aggregate_id UUID NOT NULL,
    snapshot_data JSONB NOT NULL,
    snapshot_version INTEGER NOT NULL,
    last_event_id BIGINT NOT NULL REFERENCES events(id),
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE(aggregate_type, aggregate_id)
);

CREATE INDEX idx_snapshots_aggregate ON snapshots(aggregate_type, aggregate_id);
