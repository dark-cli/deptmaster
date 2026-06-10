-- Multi-wallet system: Create wallets and wallet_users tables
-- This enables users to have multiple isolated wallets with their own contacts and transactions

-- Wallets table: Container for isolated data (contacts, transactions, events)
CREATE TABLE IF NOT EXISTS wallets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(255) NOT NULL,
    description TEXT,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
    created_by UUID REFERENCES users_projection(id),
    is_active BOOLEAN NOT NULL DEFAULT true
);

CREATE INDEX IF NOT EXISTS idx_wallets_created_by ON wallets(created_by);
CREATE INDEX IF NOT EXISTS idx_wallets_active ON wallets(is_active) WHERE is_active = true;
CREATE INDEX IF NOT EXISTS idx_wallets_name ON wallets(name);

-- Wallet users table: Many-to-many relationship between users and wallets
-- Tracks which users have access to which wallets and their roles
CREATE TABLE IF NOT EXISTS wallet_users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    wallet_id UUID NOT NULL REFERENCES wallets(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users_projection(id) ON DELETE CASCADE,
    role VARCHAR(50) NOT NULL DEFAULT 'member', -- 'owner', 'admin', 'member'
    subscribed_at TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE(wallet_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_wallet_users_wallet_id ON wallet_users(wallet_id);
CREATE INDEX IF NOT EXISTS idx_wallet_users_user_id ON wallet_users(user_id);
CREATE INDEX IF NOT EXISTS idx_wallet_users_role ON wallet_users(role);

-- Add comments for documentation
COMMENT ON TABLE wallets IS 'Isolated containers for contacts, transactions, and events. Each wallet has its own data space.';
COMMENT ON TABLE wallet_users IS 'Many-to-many relationship tracking which users have access to which wallets and their roles.';
COMMENT ON COLUMN wallet_users.role IS 'User role in wallet: owner (full control), admin (manage users), member (view/create data)';

-- Create a default wallet for existing users
-- This migration will assign all existing data to a default wallet
DO $$
DECLARE
    default_wallet_id UUID;
    existing_user_id UUID;
BEGIN
    -- Create a default wallet
    INSERT INTO wallets (name, description, is_active)
    VALUES ('Default Wallet', 'Default wallet for existing data', true)
    RETURNING id INTO default_wallet_id;
    
    -- Assign all existing users to the default wallet as owners
    FOR existing_user_id IN SELECT id FROM users_projection
    LOOP
        INSERT INTO wallet_users (wallet_id, user_id, role)
        VALUES (default_wallet_id, existing_user_id, 'owner')
        ON CONFLICT (wallet_id, user_id) DO NOTHING;
    END LOOP;
    
    RAISE NOTICE 'Created default wallet with ID: %', default_wallet_id;
END $$;
