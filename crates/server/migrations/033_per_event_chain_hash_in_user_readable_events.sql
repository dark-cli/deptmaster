-- Migration 033: per-event chain-hash in user_readable_events
--
-- New sync protocol design:
--   - Each row in user_readable_events gets its own `hash` column.
--   - hash = MD5(latest_hash_for_this_user || event_id::text), computed in
--     the same INSERT statement that adds the row. The "latest" is the hash
--     of the highest-id row for this (wallet, user) at insert time.
--   - Client pull sends its last known hash. Server does a direct
--     `SELECT id WHERE hash = ?` lookup. Found → return events with
--     greater id. Not found → full pull + flush flag.
--   - Client never computes hashes. Never validates. Just stores what the
--     server returns. Eliminates the entire class of "false divergence"
--     bugs from concurrent folds and client/server fold-order mismatches.
--
-- Why the cross-row chain integrity doesn't need to hold:
--   Two concurrent INSERTs can both read the same "latest" hash and write
--   parallel-branched rows (hash_A and hash_B both off H_prev). That's
--   fine — each row's hash is a unique identifier that resolves to its
--   own id. Lookups by either hash return the correct delta. The chain
--   is "logically broken" at that fork but lookup semantics are intact.
--   No code anywhere assumes the chain is a strict line.

ALTER TABLE user_readable_events ADD COLUMN hash TEXT;

-- Backfill: for every (wallet, user), walk rows in id order and fill the
-- chain. After this, hash is fully populated for existing rows.
DO $$
DECLARE
    user_row  RECORD;
    row_iter  RECORD;
    prev_hash TEXT;
BEGIN
    FOR user_row IN
        SELECT DISTINCT wallet_id, user_id FROM user_readable_events
    LOOP
        prev_hash := '';
        FOR row_iter IN
            SELECT id, event_id
            FROM user_readable_events
            WHERE wallet_id = user_row.wallet_id
              AND user_id   = user_row.user_id
            ORDER BY id ASC
        LOOP
            prev_hash := md5(prev_hash || row_iter.event_id::text);
            UPDATE user_readable_events
            SET    hash = prev_hash
            WHERE  id   = row_iter.id;
        END LOOP;
    END LOOP;
END $$;

ALTER TABLE user_readable_events ALTER COLUMN hash SET NOT NULL;

-- Lookup index for the pull endpoint's `WHERE hash = ?` query.
CREATE INDEX idx_user_readable_events_hash
    ON user_readable_events(wallet_id, user_id, hash);

-- The old user_event_hashes table is no longer needed — the per-row hash
-- on user_readable_events replaces it. Keep the table for now in case the
-- server build picks up before the client; drop in a follow-up migration
-- once both sides have shipped the new protocol.
