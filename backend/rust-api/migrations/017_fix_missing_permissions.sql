-- Fix missing system groups and permissions for wallets created between migration 014 and the fix in code.

DO $$
DECLARE
    w RECORD;
    ug_id UUID;
    cg_id UUID;
    act_id SMALLINT;
BEGIN
    FOR w IN SELECT id FROM wallets WHERE is_active = true
    LOOP
        -- Ensure all_users exists
        INSERT INTO user_groups (wallet_id, name, is_system)
        VALUES (w.id, 'all_users', true)
        ON CONFLICT (wallet_id, name) DO UPDATE SET is_system = true;

        -- Ensure all_contacts exists
        INSERT INTO contact_groups (wallet_id, name, type, is_system)
        VALUES (w.id, 'all_contacts', 'static', true)
        ON CONFLICT (wallet_id, name) DO NOTHING;

        -- Get IDs
        SELECT id INTO ug_id FROM user_groups WHERE wallet_id = w.id AND name = 'all_users' LIMIT 1;
        SELECT id INTO cg_id FROM contact_groups WHERE wallet_id = w.id AND name = 'all_contacts' LIMIT 1;

        -- Ensure permissions exist
        FOR act_id IN SELECT id FROM permission_actions WHERE resource IN ('contact', 'transaction', 'events')
        LOOP
            INSERT INTO group_permission_matrix (user_group_id, contact_group_id, permission_action_id)
            VALUES (ug_id, cg_id, act_id)
            ON CONFLICT (user_group_id, contact_group_id, permission_action_id) DO NOTHING;
        END LOOP;
    END LOOP;
END $$;
