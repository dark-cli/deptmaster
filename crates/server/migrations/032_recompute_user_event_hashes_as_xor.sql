-- Switch user_event_hashes.hash from the order-sensitive MD5-chain to an
-- order-independent XOR-of-MD5(event_id). XOR is commutative, so concurrent
-- folds (multiple push handlers writing to the same row) can no longer
-- produce a hash that disagrees with the client's pull-order fold — which
-- was the root cause of the "hash diverged → wipe → diverged again" loop
-- in production.
--
-- The fold for one event becomes:    md5(event_id::text) as 16-byte bytea
-- The full hash for a (wallet, user): bytewise XOR of every such 16-byte
-- value across the user's user_readable_events set.
--
-- Postgres has no built-in bytea XOR operator (the `#` operator is for
-- integers and bit strings, not bytea), so we ship a small helper
-- function. calculate_and_store and this migration both use it.

CREATE OR REPLACE FUNCTION bytea_xor(a bytea, b bytea) RETURNS bytea AS $$
DECLARE
    result bytea := ''::bytea;
    len    int   := LEAST(octet_length(a), octet_length(b));
    i      int;
BEGIN
    FOR i IN 0..(len - 1) LOOP
        result := result || set_byte(
            decode('00', 'hex'),
            0,
            get_byte(a, i) # get_byte(b, i)
        );
    END LOOP;
    RETURN result;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Recompute every existing row from user_readable_events so the
-- server-side state matches the new algorithm immediately. After
-- this runs, clients on the new code agree with the server on the
-- first incremental pull. Old-code clients see a divergence, trigger
-- the existing wipe+refetch path, and store the server's new (XOR)
-- hash — converging automatically.
DO $$
DECLARE
    user_row RECORD;
    acc      bytea;
    md_row   RECORD;
BEGIN
    FOR user_row IN SELECT wallet_id, user_id FROM user_event_hashes LOOP
        acc := decode('00000000000000000000000000000000', 'hex');
        FOR md_row IN
            SELECT decode(md5(event_id::text), 'hex') AS d
            FROM user_readable_events
            WHERE wallet_id = user_row.wallet_id
              AND user_id   = user_row.user_id
        LOOP
            acc := bytea_xor(acc, md_row.d);
        END LOOP;
        UPDATE user_event_hashes
        SET hash       = encode(acc, 'hex'),
            updated_at = NOW()
        WHERE wallet_id = user_row.wallet_id
          AND user_id   = user_row.user_id;
    END LOOP;
END $$;

-- Note: last_event_id is no longer meaningful under XOR (there's no
-- ordering). We keep the column for backward compatibility but stop
-- depending on it; subsequent calculate_and_store calls still set it
-- to the most-recently-folded event_id as informational metadata.
