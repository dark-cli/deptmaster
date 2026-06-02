-- Change deduplication key from event_id to idempotency_key
--
-- Semantics:
-- - event_id (UUID): Server-generated, for internal event management
-- - idempotency_key (VARCHAR): Client-generated per UI action, for deduplication
--
-- idempotency_key prevents duplicate form submissions (browser glitches, retries)
-- event_id tracks event identity and is used for event references in other operations

-- First, populate any NULL idempotency_key values with a UUID-based value
-- This allows existing rows to transition to the new constraint
UPDATE events SET idempotency_key = 'legacy_' || event_id::text WHERE idempotency_key IS NULL;

-- Remove UNIQUE constraint from event_id (it will remain for lookups but no longer unique)
ALTER TABLE events DROP CONSTRAINT IF EXISTS events_event_id_key;

-- Make idempotency_key NOT NULL and add UNIQUE constraint
ALTER TABLE events ALTER COLUMN idempotency_key SET NOT NULL;
ALTER TABLE events ADD CONSTRAINT events_idempotency_key_unique UNIQUE (idempotency_key);
