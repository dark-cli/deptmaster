-- Migration 031: drop events.idempotency_key entirely.
--
-- Background:
-- Migration 030 already removed the UNIQUE/NOT NULL constraints on this column
-- because event_id (UUID, scoped per-wallet) became the dedup key. That left the
-- column sitting in the schema doing nothing — vestigial state that confuses
-- readers about what's actually load-bearing.
--
-- This migration deletes the column. event_id (client-generated UUID v4, UNIQUE
-- per wallet) is now both the event identity AND the dedup key. The (wallet_id,
-- event_id) constraint added in migration 030 prevents network-retry duplicates:
-- a retry sends the same event_id and ON CONFLICT DO NOTHING handles it.
--
-- UI-glitch (double-tap) duplicate protection was a hypothetical future use for
-- idempotency_key, but the client doesn't actually keep a stable per-action key
-- — every call generates a fresh UUID. If we ever need that, we'd reintroduce
-- the column with a clear, documented purpose.

ALTER TABLE events DROP COLUMN IF EXISTS idempotency_key;
