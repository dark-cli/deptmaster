-- Remove is_settled and settled_at from transactions
-- We track net balance per contact instead, not individual transaction settlement

ALTER TABLE transactions_projection 
    DROP COLUMN IF EXISTS is_settled,
    DROP COLUMN IF EXISTS settled_at;
