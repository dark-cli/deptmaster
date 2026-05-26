-- Add created_at to wallet_invite_codes for expiration if not exists
-- Or rather, ensure the table exists correctly.
-- Since 015_wallet_invite_codes.sql was already listed in previous list_dir output (likely created before),
-- I should check if I need to MODIFY it or add a NEW migration.
-- The file 015_wallet_invite_codes.sql existed.
-- Let's check its content if possible, or just create a new migration 019 to modify it.
-- Wait, the previous file list showed `015_wallet_invite_codes.sql`.
-- The user request is new. I should probably add a new migration to ALTER the table if it exists, or create it if not.
-- But wait, where was `wallet_invite_codes` created originally?
-- It seems it was likely created in a previous migration that I don't see the content of right now (maybe 015 was it?).
-- Let's create 019_update_invite_codes.sql.

CREATE TABLE IF NOT EXISTS wallet_invite_codes (
    wallet_id UUID PRIMARY KEY REFERENCES wallets(id) ON DELETE CASCADE,
    code VARCHAR(8) NOT NULL UNIQUE,
    created_by UUID REFERENCES users_projection(id) ON DELETE SET NULL,
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

-- If table already existed without created_at:
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'wallet_invite_codes' AND column_name = 'created_at') THEN
        ALTER TABLE wallet_invite_codes ADD COLUMN created_at TIMESTAMP NOT NULL DEFAULT NOW();
    END IF;
END $$;
