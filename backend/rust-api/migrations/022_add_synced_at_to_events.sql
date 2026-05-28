-- Add synced_at timestamp to events table
-- This tracks when the event was received/synced by the server
-- Used for UNDO event validation: 5-second window is measured from synced_at, not created_at
-- This supports offline-first: both event and UNDO are created offline, but measured from server sync time

ALTER TABLE events ADD COLUMN synced_at TIMESTAMP NOT NULL DEFAULT now();

-- Create index for efficient UNDO validation queries
CREATE INDEX idx_events_synced_at ON events(synced_at);
CREATE INDEX idx_events_wallet_synced ON events(wallet_id, synced_at DESC);
