-- Add explicit ownership tracking for multi-owner support
-- This allows multiple owners per wallet with equal authority
-- Owners are tracked explicitly rather than via role string

CREATE TABLE IF NOT EXISTS wallet_owners (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    wallet_id UUID NOT NULL REFERENCES wallets(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users_projection(id) ON DELETE CASCADE,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE(wallet_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_wallet_owners_wallet_id ON wallet_owners(wallet_id);
CREATE INDEX IF NOT EXISTS idx_wallet_owners_user_id ON wallet_owners(user_id);

COMMENT ON TABLE wallet_owners IS 'Explicit ownership tracking for wallets. Owners can transfer ownership, modify any user permissions, delete wallet. Multiple owners per wallet allowed.';

-- Migrate existing owners from wallet_users.role = 'owner' to wallet_owners table
INSERT INTO wallet_owners (wallet_id, user_id, created_at)
SELECT wu.wallet_id, wu.user_id, NOW()
FROM wallet_users wu
WHERE wu.role = 'owner'
ON CONFLICT DO NOTHING;
