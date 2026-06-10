-- Add projection snapshots table for efficient state rebuilding
CREATE TABLE IF NOT EXISTS projection_snapshots (
    id BIGSERIAL PRIMARY KEY,
    snapshot_index BIGINT NOT NULL, -- Sequential index (0, 1, 2, ...)
    last_event_id BIGINT NOT NULL REFERENCES events(id),
    event_count BIGINT NOT NULL, -- Number of events processed up to this snapshot
    contacts_snapshot JSONB NOT NULL, -- Array of contacts
    transactions_snapshot JSONB NOT NULL, -- Array of transactions
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE(snapshot_index)
);

CREATE INDEX IF NOT EXISTS idx_snapshots_event_id ON projection_snapshots(last_event_id);
CREATE INDEX IF NOT EXISTS idx_snapshots_index ON projection_snapshots(snapshot_index DESC);

COMMENT ON TABLE projection_snapshots IS 'Snapshots of projections for efficient state rebuilding. Created every 10 events and after UNDO events.';
COMMENT ON COLUMN projection_snapshots.snapshot_index IS 'Sequential index for ordering snapshots. Higher index = more recent snapshot.';
COMMENT ON COLUMN projection_snapshots.last_event_id IS 'ID of the last event included in this snapshot.';
COMMENT ON COLUMN projection_snapshots.event_count IS 'Number of events processed up to this snapshot.';
