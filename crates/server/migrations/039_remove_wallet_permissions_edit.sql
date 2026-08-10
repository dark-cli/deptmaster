-- Remove `wallet:permissions_edit` (the "super admin" permission).
--
-- Per vault/04-permissions-and-undo/11-permission-implementation-plan.md,
-- modifications of Layer 1/2/2.5 permissions are OWNER ONLY (hardcoded
-- is_wallet_owner() check in the handler). The wallet:permissions_edit
-- action was a delegable admin permission that let its holder grant
-- themselves any other permission — an escalation loophole that the
-- design explicitly disallows.
--
-- After this migration:
--   - No matrix row can grant wallet:permissions_edit to a group
--   - The action name is dropped from permission_actions
--   - The Rust Action enum has already removed the variant
--
-- Any existing grants are silently discarded (they no longer had effect
-- after the handler switch to owner-only checks).

BEGIN;

-- 1. Remove any existing grants (wallet_permission_matrix uses `action` as text)
DELETE FROM wallet_permission_matrix
WHERE action = 'wallet:permissions_edit';

-- 2. Remove the row from the permission_actions catalog. Use IF EXISTS-style
--    guard to keep the migration idempotent even on databases where the seed
--    row was never inserted.
DELETE FROM permission_actions
WHERE name = 'wallet:permissions_edit';

COMMIT;
