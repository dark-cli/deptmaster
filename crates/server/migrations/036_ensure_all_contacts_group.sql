-- Ensure all_contacts group exists for all wallets
-- This migration creates missing all_contacts groups for wallets that don't have them

INSERT INTO contact_groups (id, wallet_id, name, type, is_system)
SELECT 
  gen_random_uuid(),
  w.id,
  'all_contacts',
  'static',
  true
FROM wallets w
WHERE w.id NOT IN (
  SELECT DISTINCT wallet_id FROM contact_groups WHERE name = 'all_contacts'
)
ON CONFLICT (wallet_id, name) DO NOTHING;
