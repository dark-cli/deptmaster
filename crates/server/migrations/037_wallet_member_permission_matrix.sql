-- Wallet member management permissions (vector-based)
-- Scoped permissions between user groups: source_group can manage target_group members
-- Complements wallet_permission_matrix (global) for granular member group management

-- 1. Create wallet_member_permission_matrix table
CREATE TABLE IF NOT EXISTS wallet_member_permission_matrix (
    source_group_id UUID NOT NULL REFERENCES user_groups(id) ON DELETE CASCADE,
    target_group_id UUID NOT NULL REFERENCES user_groups(id) ON DELETE CASCADE,
    action VARCHAR(64) NOT NULL,
    is_deny BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
    PRIMARY KEY (source_group_id, target_group_id, action)
);

-- Ensure source and target are different (can't grant permissions on same group)
ALTER TABLE wallet_member_permission_matrix
ADD CONSTRAINT check_source_target_different
CHECK (source_group_id != target_group_id);

-- 2. Create indexes for query performance
CREATE INDEX IF NOT EXISTS idx_wallet_member_perm_source
    ON wallet_member_permission_matrix(source_group_id);

CREATE INDEX IF NOT EXISTS idx_wallet_member_perm_target
    ON wallet_member_permission_matrix(target_group_id);

CREATE INDEX IF NOT EXISTS idx_wallet_member_perm_action
    ON wallet_member_permission_matrix(action);

CREATE INDEX IF NOT EXISTS idx_wallet_member_perm_source_target
    ON wallet_member_permission_matrix(source_group_id, target_group_id);

-- 3. Add comments for documentation
COMMENT ON TABLE wallet_member_permission_matrix IS
    'Vector-based member management permissions: (source_group, target_group, action).
     Grants a source group the ability to manage members in a specific target group.
     Actions: wallet:member_add, wallet:member_remove, wallet:member_list, wallet:set_permission_matrix.
     Same deny-wins algorithm as group_permission_matrix.';

COMMENT ON COLUMN wallet_member_permission_matrix.source_group_id IS
    'The group that has the permission (the group containing users who can perform the action).';

COMMENT ON COLUMN wallet_member_permission_matrix.target_group_id IS
    'The group being managed (the group on which the action is applied).';

COMMENT ON COLUMN wallet_member_permission_matrix.action IS
    'The member management action: wallet:member_add, wallet:member_remove, wallet:member_list, wallet:set_permission_matrix.';

COMMENT ON COLUMN wallet_member_permission_matrix.is_deny IS
    'If true, this permission is a denial (explicit deny). Deny wins if user is in both allow and deny groups.';

-- 4. Update permission_actions table with new vector actions
INSERT INTO permission_actions (name, resource) VALUES
    ('wallet:member_add', 'wallet_member'),
    ('wallet:member_remove', 'wallet_member'),
    ('wallet:member_list', 'wallet_member'),
    ('wallet:set_permission_matrix', 'wallet_member')
ON CONFLICT (name) DO NOTHING;
