-- Protect owner permissions via database constraints
-- This migration adds triggers to enforce structural integrity of the permission system:
-- 1. Owners cannot be added to non-system groups
-- 2. System groups cannot be modified (rename/delete)
-- 3. System contact groups cannot be modified

-- ============================================================================
-- PROTECT OWNER GROUP MEMBERSHIP
-- ============================================================================
-- Prevent adding wallet owners to non-system user groups
-- Owners should only be members of the __owners__ system group

CREATE OR REPLACE FUNCTION check_owner_group_membership()
RETURNS TRIGGER AS $$
DECLARE
    is_owner BOOLEAN;
    is_system_group BOOLEAN;
    owner_wallet_id UUID;
BEGIN
    -- Check if the user being added is a wallet owner
    SELECT EXISTS(
        SELECT 1 FROM wallet_owners
        WHERE user_id = NEW.user_id
        AND wallet_id = (
            SELECT user_groups.wallet_id FROM user_groups WHERE id = NEW.user_group_id LIMIT 1
        )
    ) INTO is_owner;

    -- If user is an owner, check if the group is system
    IF is_owner THEN
        SELECT is_system INTO is_system_group
        FROM user_groups WHERE id = NEW.user_group_id;

        IF is_system_group = false THEN
            RAISE EXCEPTION 'Wallet owners cannot be added to non-system groups';
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS prevent_owner_in_non_system_groups ON user_group_members;
CREATE TRIGGER prevent_owner_in_non_system_groups
BEFORE INSERT ON user_group_members
FOR EACH ROW
EXECUTE FUNCTION check_owner_group_membership();

-- ============================================================================
-- PROTECT SYSTEM USER GROUPS FROM MODIFICATION
-- ============================================================================
-- Prevent renaming or deleting system groups (all_users, __owners__)

CREATE OR REPLACE FUNCTION protect_system_user_groups()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.is_system = true THEN
        RAISE EXCEPTION 'Cannot modify system groups (% in wallet %)',
            OLD.name, OLD.wallet_id;
    END IF;
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS prevent_system_user_group_modification ON user_groups;
CREATE TRIGGER prevent_system_user_group_modification
BEFORE UPDATE OR DELETE ON user_groups
FOR EACH ROW
EXECUTE FUNCTION protect_system_user_groups();

-- ============================================================================
-- PROTECT SYSTEM CONTACT GROUPS FROM MODIFICATION
-- ============================================================================
-- Prevent renaming or deleting system contact groups (all_contacts)

CREATE OR REPLACE FUNCTION protect_system_contact_groups()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.is_system = true THEN
        RAISE EXCEPTION 'Cannot modify system contact groups (% in wallet %)',
            OLD.name, OLD.wallet_id;
    END IF;
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS prevent_system_contact_group_modification ON contact_groups;
CREATE TRIGGER prevent_system_contact_group_modification
BEFORE UPDATE OR DELETE ON contact_groups
FOR EACH ROW
EXECUTE FUNCTION protect_system_contact_groups();

-- ============================================================================
-- ENSURE UNIQUE GROUP NAMES PER WALLET
-- ============================================================================
-- The UNIQUE(wallet_id, name) constraints already exist, but we document them here
-- for clarity. These constraints prevent:
-- - Creating duplicate user group names in the same wallet
-- - Creating duplicate contact group names in the same wallet

-- Existing constraints (created in migration 014):
-- user_groups: UNIQUE(wallet_id, name)
-- contact_groups: UNIQUE(wallet_id, name)

COMMENT ON TRIGGER prevent_owner_in_non_system_groups ON user_group_members IS
'Enforces that wallet owners can only be members of system groups (specifically __owners__)';

COMMENT ON TRIGGER prevent_system_user_group_modification ON user_groups IS
'Enforces that system user groups (all_users, __owners__) cannot be renamed or deleted';

COMMENT ON TRIGGER prevent_system_contact_group_modification ON contact_groups IS
'Enforces that system contact groups (all_contacts) cannot be renamed or deleted';
