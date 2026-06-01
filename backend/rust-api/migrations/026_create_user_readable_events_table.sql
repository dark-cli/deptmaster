-- Denormalized table to cache which events each user can read
-- Populated on event insert and rebuilt on permission changes
-- Enables O(1) hash computation instead of O(n*k) permission matrix joins

CREATE TABLE user_readable_events (
    id BIGSERIAL PRIMARY KEY,
    wallet_id UUID NOT NULL REFERENCES wallets(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users_projection(id) ON DELETE CASCADE,
    event_id UUID NOT NULL REFERENCES events(event_id) ON DELETE CASCADE,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE(wallet_id, user_id, event_id)
);

CREATE INDEX idx_user_readable_events_user
    ON user_readable_events(wallet_id, user_id, created_at DESC);

CREATE INDEX idx_user_readable_events_event
    ON user_readable_events(event_id);
