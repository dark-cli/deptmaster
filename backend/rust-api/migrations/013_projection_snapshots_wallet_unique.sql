-- projection_snapshots must be wallet-scoped: each wallet has its own snapshot stack (indices 0,1,...).
-- Replace global UNIQUE(snapshot_index) with UNIQUE(wallet_id, snapshot_index).
-- Dev: data is dummy; you can always wipe and re-import from zip via manager.sh.

TRUNCATE TABLE projection_snapshots;

ALTER TABLE projection_snapshots
DROP CONSTRAINT IF EXISTS projection_snapshots_snapshot_index_key;

ALTER TABLE projection_snapshots
ADD CONSTRAINT projection_snapshots_wallet_snapshot_index_key UNIQUE (wallet_id, snapshot_index);

ALTER TABLE projection_snapshots
ALTER COLUMN wallet_id SET NOT NULL;

CREATE INDEX IF NOT EXISTS idx_projection_snapshots_wallet_index
ON projection_snapshots(wallet_id, snapshot_index DESC);

COMMENT ON CONSTRAINT projection_snapshots_wallet_snapshot_index_key ON projection_snapshots IS 'Per-wallet snapshot stack: each wallet has its own sequence of snapshot indices.';
