-- Add soft delete support for wallets
-- Wallets are marked deleted rather than removed from database
-- This preserves historical data and event audit trail

ALTER TABLE wallets ADD COLUMN deleted_at TIMESTAMP NULL DEFAULT NULL;
ALTER TABLE wallets ADD COLUMN deleted_by_user_id UUID NULL REFERENCES users_projection(id);

CREATE INDEX IF NOT EXISTS idx_wallets_deleted_at ON wallets(deleted_at);

-- Update the is_active filter to include deleted_at check
-- Queries should filter: WHERE is_active = true AND deleted_at IS NULL
