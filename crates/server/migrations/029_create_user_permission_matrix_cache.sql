-- Create cached permission matrix table for O(1) lookups
--
-- This table caches the computed permissions for each user on each contact group.
-- It's built from: user → user_groups → group_permission_matrix → contact_groups
--
-- Instead of computing the matrix on every permission check (expensive joins),
-- we cache it and only rebuild when permission events occur (user added/removed or matrix changed).
--
-- Structure: (user, contact_group) → set of allowed actions
-- Used by: PermissionModel to check if user can perform action on resource

CREATE TABLE IF NOT EXISTS user_permission_matrix_cache (
    wallet_id UUID NOT NULL,
    user_id UUID NOT NULL REFERENCES users_projection(id) ON DELETE CASCADE,
    contact_group_id UUID NOT NULL,
    permission_action_id SMALLINT NOT NULL REFERENCES permission_actions(id),
    is_deny BOOLEAN NOT NULL DEFAULT false,

    PRIMARY KEY (wallet_id, user_id, contact_group_id, permission_action_id),

    FOREIGN KEY (wallet_id) REFERENCES wallets(id) ON DELETE CASCADE,
    FOREIGN KEY (contact_group_id) REFERENCES contact_groups(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_perm_cache_user ON user_permission_matrix_cache(wallet_id, user_id);
CREATE INDEX IF NOT EXISTS idx_perm_cache_contact_group ON user_permission_matrix_cache(wallet_id, contact_group_id);

COMMENT ON TABLE user_permission_matrix_cache IS 'Cached user permission matrix: O(1) lookup instead of computing joins every time';
COMMENT ON COLUMN user_permission_matrix_cache.is_deny IS 'false = allowed, true = denied (deny wins in resolution)';
