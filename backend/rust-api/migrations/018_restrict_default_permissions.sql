-- Restrict default permissions for existing wallets
-- Only allow 'contact:read', 'transaction:read', 'events:read' for 'all_users' -> 'all_contacts'

DELETE FROM group_permission_matrix m
USING user_groups ug, contact_groups cg, permission_actions pa
WHERE m.user_group_id = ug.id
  AND m.contact_group_id = cg.id
  AND m.permission_action_id = pa.id
  AND ug.name = 'all_users'
  AND cg.name = 'all_contacts'
  AND ug.wallet_id = cg.wallet_id
  AND pa.name NOT IN ('contact:read', 'transaction:read', 'events:read');
