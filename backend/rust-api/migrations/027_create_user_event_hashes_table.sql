-- Store incremental event hashes per user for efficient sync hash calculation
-- Hash is calculated as MD5(previous_hash + new_event_id) when events are added to readable_events

CREATE TABLE IF NOT EXISTS user_event_hashes (
    wallet_id UUID NOT NULL REFERENCES wallets(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users_projection(id) ON DELETE CASCADE,
    last_event_id UUID,
    hash TEXT NOT NULL DEFAULT '',
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
    PRIMARY KEY (wallet_id, user_id)
);

CREATE INDEX idx_user_event_hashes_user
    ON user_event_hashes(wallet_id, user_id);
