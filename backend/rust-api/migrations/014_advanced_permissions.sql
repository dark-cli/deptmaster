-- Advanced permissions: group-group model (Discord/Telegram style)
-- permission_actions (global), user_groups, contact_groups, matrix, user_wallet_settings

-- 1. Permission actions (global reference)
CREATE TABLE IF NOT EXISTS permission_actions (
    id SMALLSERIAL PRIMARY KEY,
    name VARCHAR(64) UNIQUE NOT NULL,
    resource VARCHAR(32) NOT NULL
);

INSERT INTO permission_actions (name, resource) VALUES
    ('contact:create', 'contact'),
    ('contact:read', 'contact'),
    ('contact:update', 'contact'),
    ('contact:delete', 'contact'),
    ('transaction:create', 'transaction'),
    ('transaction:read', 'transaction'),
    ('transaction:update', 'transaction'),
    ('transaction:delete', 'transaction'),
    ('transaction:close', 'transaction'),
    ('events:read', 'events'),
    ('wallet:read', 'wallet'),
    ('wallet:update', 'wallet'),
    ('wallet:delete', 'wallet'),
    ('wallet:manage_members', 'wallet')
ON CONFLICT (name) DO NOTHING;

-- 2. User groups (per wallet)
CREATE TABLE IF NOT EXISTS user_groups (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    wallet_id UUID NOT NULL REFERENCES wallets(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    is_system BOOLEAN NOT NULL DEFAULT false,
    UNIQUE(wallet_id, name)
);

CREATE INDEX IF NOT EXISTS idx_user_groups_wallet ON user_groups(wallet_id);

-- 3. User group members (static; all_users membership is implicit for wallet members)
CREATE TABLE IF NOT EXISTS user_group_members (
    user_id UUID NOT NULL REFERENCES users_projection(id) ON DELETE CASCADE,
    user_group_id UUID NOT NULL REFERENCES user_groups(id) ON DELETE CASCADE,
    PRIMARY KEY (user_id, user_group_id)
);

CREATE INDEX IF NOT EXISTS idx_user_group_members_group ON user_group_members(user_group_id);

-- 4. Contact groups (per wallet; scope for permission matrix)
CREATE TABLE IF NOT EXISTS contact_groups (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    wallet_id UUID NOT NULL REFERENCES wallets(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    type VARCHAR(32) NOT NULL DEFAULT 'static' CHECK (type IN ('static', 'dynamic')),
    definition JSONB,
    is_system BOOLEAN NOT NULL DEFAULT false,
    UNIQUE(wallet_id, name)
);

CREATE INDEX IF NOT EXISTS idx_contact_groups_wallet ON contact_groups(wallet_id);

-- 5. Contact group members (static only; all_contacts membership is implicit)
CREATE TABLE IF NOT EXISTS contact_group_members (
    contact_id UUID NOT NULL REFERENCES contacts_projection(id) ON DELETE CASCADE,
    contact_group_id UUID NOT NULL REFERENCES contact_groups(id) ON DELETE CASCADE,
    PRIMARY KEY (contact_id, contact_group_id)
);

CREATE INDEX IF NOT EXISTS idx_contact_group_members_group ON contact_group_members(contact_group_id);

-- 6. Permission matrix: (user_group x contact_group) -> allowed actions
CREATE TABLE IF NOT EXISTS group_permission_matrix (
    user_group_id UUID NOT NULL REFERENCES user_groups(id) ON DELETE CASCADE,
    contact_group_id UUID NOT NULL REFERENCES contact_groups(id) ON DELETE CASCADE,
    permission_action_id SMALLINT NOT NULL REFERENCES permission_actions(id),
    PRIMARY KEY (user_group_id, contact_group_id, permission_action_id)
);

CREATE INDEX IF NOT EXISTS idx_group_permission_matrix_scope ON group_permission_matrix(contact_group_id);

-- 7. User wallet settings (default group selection for creators)
CREATE TABLE IF NOT EXISTS user_wallet_settings (
    wallet_id UUID NOT NULL REFERENCES wallets(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users_projection(id) ON DELETE CASCADE,
    default_contact_group_ids UUID[] NOT NULL DEFAULT '{}',
    default_transaction_group_ids UUID[] NOT NULL DEFAULT '{}',
    PRIMARY KEY (wallet_id, user_id)
);

-- Seed system groups and default matrix for each existing wallet
DO $$
DECLARE
    w RECORD;
    ug_id UUID;
    cg_id UUID;
    act_id SMALLINT;
BEGIN
    FOR w IN SELECT id FROM wallets WHERE is_active = true
    LOOP
        INSERT INTO user_groups (wallet_id, name, is_system)
        VALUES (w.id, 'all_users', true)
        ON CONFLICT (wallet_id, name) DO UPDATE SET is_system = true;

        INSERT INTO contact_groups (wallet_id, name, type, is_system)
        VALUES (w.id, 'all_contacts', 'static', true)
        ON CONFLICT (wallet_id, name) DO NOTHING;

        SELECT id INTO ug_id FROM user_groups WHERE wallet_id = w.id AND name = 'all_users' LIMIT 1;
        SELECT id INTO cg_id FROM contact_groups WHERE wallet_id = w.id AND name = 'all_contacts' LIMIT 1;

        FOR act_id IN SELECT id FROM permission_actions WHERE name IN ('contact:read', 'transaction:read', 'events:read')
        LOOP
            INSERT INTO group_permission_matrix (user_group_id, contact_group_id, permission_action_id)
            VALUES (ug_id, cg_id, act_id)
            ON CONFLICT (user_group_id, contact_group_id, permission_action_id) DO NOTHING;
        END LOOP;
    END LOOP;
END $$;

COMMENT ON TABLE permission_actions IS 'Global list of permission actions (contact:create, transaction:close, etc.).';
COMMENT ON TABLE user_groups IS 'Per-wallet user groups (who). all_users is system; every wallet member is implicitly in it.';
COMMENT ON TABLE contact_groups IS 'Per-wallet contact groups (scope). all_contacts is system; every contact is implicitly in it.';
COMMENT ON TABLE group_permission_matrix IS 'What each user group can do to each contact group. Many-to-many.';
COMMENT ON TABLE user_wallet_settings IS 'Per-user per-wallet settings: default contact/transaction group IDs when creating.';
