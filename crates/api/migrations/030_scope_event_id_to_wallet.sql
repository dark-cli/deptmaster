-- Migration 030: scope event_id uniqueness to (wallet_id, event_id), retire idempotency_key
--
-- Background:
-- Previously the server generated event_ids and used idempotency_key as the per-request
-- dedup token. That created two problems:
--   1. Offline clients can't generate UNDO events referencing pre-sync events.
--   2. Lots of plumbing (separate field, separate response shape, separate FFI handling)
--      for a property the client already has via its own UUID generation.
--
-- New design:
--   - Clients generate event_ids locally (UUID v4). UUID v4 collision odds at our scale
--     (~10^9 events lifetime) are ~10^-18 globally; scoping to per-wallet makes them
--     even more astronomical.
--   - Uniqueness is on (wallet_id, event_id), NOT global event_id. A wallet is the
--     natural boundary for event identity.
--   - idempotency_key column stays for minimal code churn but is no longer load-bearing.
--     Future cleanup may drop it.

-- 1. Drop the FK that depends on the old global UNIQUE on events.event_id.
ALTER TABLE user_readable_events
    DROP CONSTRAINT IF EXISTS user_readable_events_event_id_fkey;

-- 2. Drop the old uniqueness constraints (global event_id, global idempotency_key).
ALTER TABLE events DROP CONSTRAINT IF EXISTS events_event_id_key;
ALTER TABLE events DROP CONSTRAINT IF EXISTS events_idempotency_key_unique;
ALTER TABLE events DROP CONSTRAINT IF EXISTS events_idempotency_key_key;

-- 3. Relax NOT NULL on idempotency_key — INSERTs no longer have to populate it.
--    Column kept for code-compat; remove in a follow-up migration if desired.
ALTER TABLE events ALTER COLUMN idempotency_key DROP NOT NULL;

-- 4. New dedup key: per-wallet event_id.
ALTER TABLE events
    ADD CONSTRAINT events_wallet_event_id_key UNIQUE (wallet_id, event_id);

-- 5. Re-create the FK using the composite reference.
--    user_readable_events already has wallet_id, so this just promotes its existing
--    columns into the FK signature.
ALTER TABLE user_readable_events
    ADD CONSTRAINT user_readable_events_event_id_fkey
    FOREIGN KEY (wallet_id, event_id)
    REFERENCES events(wallet_id, event_id)
    ON DELETE CASCADE;
