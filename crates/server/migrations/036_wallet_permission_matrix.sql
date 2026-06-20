-- Wallet-level permission matrix and soft delete support
-- Introduces granular wallet permissions (info_update, member_add/remove, delete)
-- Replaces role-based access with unified permission matrix model

-- 1. Add soft-delete columns to wallets table
ALTER TABLE wallets ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP;
ALTER TABLE wallets ADD COLUMN IF NOT EXISTS deleted_by UUID REFERENCES users_projection(id);
ALTER TABLE wallets ADD COLUMN IF NOT EXISTS deletion_reason TEXT;

-- 2. Create wallet_permission_matrix table
-- Stores permissions at wallet level: (user_group, action) → allowed/denied
-- No contact_group scope (unlike group_permission_matrix which is resource-scoped)
CREATE TABLE IF NOT EXISTS wallet_permission_matrix (
    user_group_id UUID NOT NULL REFERENCES user_groups(id) ON DELETE CASCADE,
    action VARCHAR(64) NOT NULL,
    is_deny BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_group_id, action)
);

CREATE INDEX IF NOT EXISTS idx_wallet_permission_matrix_user_group
    ON wallet_permission_matrix(user_group_id);
CREATE INDEX IF NOT EXISTS idx_wallet_permission_matrix_action
    ON wallet_permission_matrix(action);

-- 3. Update permission_actions table
-- Remove old wallet actions (wallet:read, wallet:update, wallet:delete, wallet:manage_members)
-- Add new granular wallet actions
DELETE FROM permission_actions WHERE name IN (
    'wallet:read',
    'wallet:update',
    'wallet:delete',
    'wallet:manage_members'
);

INSERT INTO permission_actions (name, resource) VALUES
    ('wallet:info_read', 'wallet'),
    ('wallet:info_update', 'wallet'),
    ('wallet:member_add', 'wallet'),
    ('wallet:member_remove', 'wallet'),
    ('wallet:member_list', 'wallet'),
    ('wallet:owner_transfer', 'wallet'),
    ('wallet:delete', 'wallet')
ON CONFLICT (name) DO NOTHING;

-- 4. Backfill wallet_permission_matrix with safe defaults
-- All members (via all_users group) get:
-- - wallet:info_read (can see wallet name/description)
-- - wallet:member_list (can see who's in the wallet)
INSERT INTO wallet_permission_matrix (user_group_id, action, is_deny, created_at, updated_at)
SELECT ug.id, action, false, NOW(), NOW()
FROM user_groups ug
CROSS JOIN (
    VALUES
        ('wallet:info_read'),
        ('wallet:member_list')
) AS actions(action)
WHERE ug.name = 'all_users' AND ug.is_system = true
ON CONFLICT (user_group_id, action) DO NOTHING;

-- 5. Add index for active wallets queries (common pattern)
CREATE INDEX IF NOT EXISTS idx_wallets_deleted_at ON wallets(deleted_at)
    WHERE deleted_at IS NULL;

-- 6. Add comments for documentation
COMMENT ON TABLE wallet_permission_matrix IS
    'Wallet-level permissions: (user_group, action) pairs with allow/deny.
     Grants a user group the ability to perform wallet-level actions.
     No contact_group scope (wallet-level is global within wallet).
     Same resolution algorithm as group_permission_matrix: deny wins.';

COMMENT ON COLUMN wallets.deleted_at IS
    'Timestamp when wallet was soft-deleted. NULL = active wallet.
     Enables audit trail and recovery/archive functionality.';

COMMENT ON COLUMN wallets.deleted_by IS
    'User ID who performed the soft delete. Links to who executed deletion.';

COMMENT ON COLUMN wallets.deletion_reason IS
    'Optional reason for deletion (e.g., "user requested", "compliance", "spam").';
