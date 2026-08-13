-- Fix protect_system_user_groups / protect_system_contact_groups triggers.
--
-- Migration 035 introduced BEFORE UPDATE triggers to reject modifications
-- to system groups. Both functions correctly RAISE EXCEPTION when
-- OLD.is_system = true, but on the success path they `RETURN OLD`.
--
-- In a PostgreSQL BEFORE UPDATE row trigger, the returned row is the
-- one PostgreSQL actually writes. Returning OLD means "write the row
-- back with its original values" — the UPDATE becomes a silent no-op
-- (rows_affected still reports 1, but nothing changes on disk).
--
-- Effect: renaming a non-system user_group or contact_group did nothing.
-- Fix: RETURN NEW on the success path so the caller's changes stick.

CREATE OR REPLACE FUNCTION protect_system_user_groups()
RETURNS TRIGGER AS $$
BEGIN
    -- Allow deletion if wallet is being deleted (cascade delete scenario)
    IF TG_OP = 'DELETE' THEN
        PERFORM 1 FROM wallets WHERE id = OLD.wallet_id;
        IF NOT FOUND THEN
            -- Wallet is gone, this is a cascade delete - allow it
            RETURN OLD;
        END IF;
    END IF;

    IF OLD.is_system = true THEN
        RAISE EXCEPTION 'Cannot modify system groups (% in wallet %)',
            OLD.name, OLD.wallet_id;
    END IF;

    -- Non-system group: allow the modification through with the caller's
    -- new values. On DELETE the returned row is ignored except for control
    -- flow, so returning OLD/NEW both work — use NEW on UPDATE for clarity.
    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    ELSE
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION protect_system_contact_groups()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        PERFORM 1 FROM wallets WHERE id = OLD.wallet_id;
        IF NOT FOUND THEN
            RETURN OLD;
        END IF;
    END IF;

    IF OLD.is_system = true THEN
        RAISE EXCEPTION 'Cannot modify system contact groups (% in wallet %)',
            OLD.name, OLD.wallet_id;
    END IF;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    ELSE
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;
