-- Layer 1/2/2.5 Permission System - New Actions and Vector Tables
-- Implements four-layer permission architecture:
-- Layer 1: Wallet-wide permissions (wallet:*)
-- Layer 2: Member-group-to-member-group permissions (member_group:*)
-- Layer 2.5: Contact-group management permissions (contact_group:*)
-- Layer 3: Contact/transaction operational permissions (existing C: T: matrix)

-- 1. Add new Layer 1 permission actions to permission_actions table
INSERT INTO permission_actions (name, resource) VALUES
    -- Layer 1: Wallet-wide permissions
    ('wallet:members_read', 'wallet'),
    ('wallet:members_add', 'wallet'),
    ('wallet:members_remove', 'wallet'),
    ('wallet:groups_create', 'wallet'),
    ('wallet:groups_update', 'wallet'),
    ('wallet:groups_delete', 'wallet'),
    ('wallet:contact_groups_create', 'wallet'),
    ('wallet:contact_groups_update', 'wallet'),
    ('wallet:contact_groups_delete', 'wallet'),
    ('wallet:metadata_read', 'wallet'),
    ('wallet:permissions_edit', 'wallet'),
    -- Layer 2: Member-group-to-member-group permissions
    ('member_group:members_read', 'member_group'),
    ('member_group:members_add', 'member_group'),
    ('member_group:members_remove', 'member_group'),
    ('member_group:permissions_edit', 'member_group'),
    -- Layer 2.5: Contact-group management permissions
    ('contact_group:contacts_read', 'contact_group'),
    ('contact_group:contacts_add', 'contact_group'),
    ('contact_group:contacts_remove', 'contact_group')
ON CONFLICT (name) DO NOTHING;

-- 2. Create wallet_contact_group_permission_matrix table (Layer 2.5)
-- Scoped permissions between user groups and contact groups:
-- source_group can manage membership of target_contact_group
CREATE TABLE IF NOT EXISTS wallet_contact_group_permission_matrix (
    source_group_id UUID NOT NULL REFERENCES user_groups(id) ON DELETE CASCADE,
    target_contact_group_id UUID NOT NULL REFERENCES contact_groups(id) ON DELETE CASCADE,
    action VARCHAR(64) NOT NULL,
    is_deny BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
    PRIMARY KEY (source_group_id, target_contact_group_id, action)
);

-- Create indexes for query performance
CREATE INDEX IF NOT EXISTS idx_wallet_contact_group_perm_source
    ON wallet_contact_group_permission_matrix(source_group_id);

CREATE INDEX IF NOT EXISTS idx_wallet_contact_group_perm_target
    ON wallet_contact_group_permission_matrix(target_contact_group_id);

CREATE INDEX IF NOT EXISTS idx_wallet_contact_group_perm_action
    ON wallet_contact_group_permission_matrix(action);

CREATE INDEX IF NOT EXISTS idx_wallet_contact_group_perm_source_target
    ON wallet_contact_group_permission_matrix(source_group_id, target_contact_group_id);

-- Add comments for documentation
COMMENT ON TABLE wallet_contact_group_permission_matrix IS
    'Layer 2.5 permissions: Vector-based contact-group management.
     (source_group, target_contact_group, action) grants a source group
     the ability to manage members in a specific contact group.
     Actions: contact_group:contacts_read, contact_group:contacts_add, contact_group:contacts_remove.
     Same deny-wins algorithm as group_permission_matrix.';

COMMENT ON COLUMN wallet_contact_group_permission_matrix.source_group_id IS
    'The user group that has the permission.';

COMMENT ON COLUMN wallet_contact_group_permission_matrix.target_contact_group_id IS
    'The contact group being managed.';

COMMENT ON COLUMN wallet_contact_group_permission_matrix.action IS
    'The contact-group management action: contact_group:contacts_read, contact_group:contacts_add, contact_group:contacts_remove.';

COMMENT ON COLUMN wallet_contact_group_permission_matrix.is_deny IS
    'If true, this permission is a denial. Deny wins if user is in both allow and deny groups.';

-- 3. Notes on Layer 1 and Layer 2 (already in database)
-- Layer 1 (wallet-wide) uses wallet_permission_matrix table (migration 036)
-- Layer 2 (member-group-to-member-group) uses wallet_member_permission_matrix table (migration 037)
-- These existing tables are extended with new action types above.
