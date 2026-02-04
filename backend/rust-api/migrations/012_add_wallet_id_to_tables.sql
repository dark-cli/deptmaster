-- Multi-wallet system: Add wallet_id to all tables that need wallet isolation
-- This migration adds wallet_id columns and migrates existing data to the default wallet

-- Step 1: Add wallet_id columns (nullable initially for migration)
ALTER TABLE events 
ADD COLUMN IF NOT EXISTS wallet_id UUID REFERENCES wallets(id) ON DELETE CASCADE;

ALTER TABLE contacts_projection 
ADD COLUMN IF NOT EXISTS wallet_id UUID REFERENCES wallets(id) ON DELETE CASCADE;

ALTER TABLE transactions_projection 
ADD COLUMN IF NOT EXISTS wallet_id UUID REFERENCES wallets(id) ON DELETE CASCADE;

-- Add wallet_id to projection_snapshots if it exists
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'projection_snapshots') THEN
        ALTER TABLE projection_snapshots 
        ADD COLUMN IF NOT EXISTS wallet_id UUID REFERENCES wallets(id) ON DELETE CASCADE;
    END IF;
END $$;

-- Add wallet_id to client_sync_state if it exists
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'client_sync_state') THEN
        ALTER TABLE client_sync_state 
        ADD COLUMN IF NOT EXISTS wallet_id UUID REFERENCES wallets(id) ON DELETE CASCADE;
    END IF;
END $$;

-- Step 2: Migrate existing data to default wallet
-- Get the default wallet ID (should be the first one created)
DO $$
DECLARE
    default_wallet_id UUID;
    migrated_events INTEGER;
    migrated_contacts INTEGER;
    migrated_transactions INTEGER;
BEGIN
    -- Get the default wallet (created in previous migration)
    SELECT id INTO default_wallet_id 
    FROM wallets 
    WHERE name = 'Default Wallet' 
    ORDER BY created_at ASC 
    LIMIT 1;
    
    IF default_wallet_id IS NULL THEN
        RAISE EXCEPTION 'Default wallet not found. Please run migration 011_create_wallets.sql first.';
    END IF;
    
    -- Migrate events: Assign to default wallet based on user_id
    -- Each user's events go to their default wallet
    UPDATE events e
    SET wallet_id = (
        SELECT wu.wallet_id 
        FROM wallet_users wu 
        WHERE wu.user_id = e.user_id 
        AND wu.role = 'owner'
        ORDER BY wu.subscribed_at ASC
        LIMIT 1
    )
    WHERE e.wallet_id IS NULL;
    
    GET DIAGNOSTICS migrated_events = ROW_COUNT;
    
    -- Migrate contacts: Assign to default wallet based on user_id
    UPDATE contacts_projection c
    SET wallet_id = (
        SELECT wu.wallet_id 
        FROM wallet_users wu 
        WHERE wu.user_id = c.user_id 
        AND wu.role = 'owner'
        ORDER BY wu.subscribed_at ASC
        LIMIT 1
    )
    WHERE c.wallet_id IS NULL;
    
    GET DIAGNOSTICS migrated_contacts = ROW_COUNT;
    
    -- Migrate transactions: Assign to default wallet based on user_id
    UPDATE transactions_projection t
    SET wallet_id = (
        SELECT wu.wallet_id 
        FROM wallet_users wu 
        WHERE wu.user_id = t.user_id 
        AND wu.role = 'owner'
        ORDER BY wu.subscribed_at ASC
        LIMIT 1
    )
    WHERE t.wallet_id IS NULL;
    
    GET DIAGNOSTICS migrated_transactions = ROW_COUNT;
    
    -- Migrate projection_snapshots if it exists
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'projection_snapshots') THEN
        UPDATE projection_snapshots ps
        SET wallet_id = (
            SELECT wu.wallet_id 
            FROM wallet_users wu 
            JOIN events e ON e.user_id = wu.user_id
            WHERE e.id = ps.last_event_id
            AND wu.role = 'owner'
            ORDER BY wu.subscribed_at ASC
            LIMIT 1
        )
        WHERE ps.wallet_id IS NULL;
    END IF;
    
    -- Migrate client_sync_state if it exists
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'client_sync_state') THEN
        UPDATE client_sync_state css
        SET wallet_id = (
            SELECT wu.wallet_id 
            FROM wallet_users wu 
            WHERE wu.user_id = css.user_id 
            AND wu.role = 'owner'
            ORDER BY wu.subscribed_at ASC
            LIMIT 1
        )
        WHERE css.wallet_id IS NULL;
    END IF;
    
    RAISE NOTICE 'Migration complete: % events, % contacts, % transactions migrated to default wallet', 
        migrated_events, migrated_contacts, migrated_transactions;
END $$;

-- Step 3: Make wallet_id NOT NULL and add indexes
-- First, ensure all records have wallet_id (should be done by migration above)
DO $$
DECLARE
    null_events INTEGER;
    null_contacts INTEGER;
    null_transactions INTEGER;
BEGIN
    SELECT COUNT(*) INTO null_events FROM events WHERE wallet_id IS NULL;
    SELECT COUNT(*) INTO null_contacts FROM contacts_projection WHERE wallet_id IS NULL;
    SELECT COUNT(*) INTO null_transactions FROM transactions_projection WHERE wallet_id IS NULL;
    
    IF null_events > 0 OR null_contacts > 0 OR null_transactions > 0 THEN
        RAISE EXCEPTION 'Migration incomplete: Some records still have NULL wallet_id. Events: %, Contacts: %, Transactions: %', 
            null_events, null_contacts, null_transactions;
    END IF;
END $$;

-- Now make wallet_id NOT NULL
ALTER TABLE events 
ALTER COLUMN wallet_id SET NOT NULL;

ALTER TABLE contacts_projection 
ALTER COLUMN wallet_id SET NOT NULL;

ALTER TABLE transactions_projection 
ALTER COLUMN wallet_id SET NOT NULL;

-- Add composite indexes for wallet-scoped queries
CREATE INDEX IF NOT EXISTS idx_events_wallet_user_aggregate ON events(wallet_id, user_id, aggregate_type, aggregate_id);
CREATE INDEX IF NOT EXISTS idx_events_wallet_created ON events(wallet_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_events_wallet_aggregate ON events(wallet_id, aggregate_type, aggregate_id);

CREATE INDEX IF NOT EXISTS idx_contacts_wallet_user ON contacts_projection(wallet_id, user_id) WHERE is_deleted = FALSE;
CREATE INDEX IF NOT EXISTS idx_contacts_wallet ON contacts_projection(wallet_id) WHERE is_deleted = FALSE;

CREATE INDEX IF NOT EXISTS idx_transactions_wallet_user_date ON transactions_projection(wallet_id, user_id, transaction_date DESC) WHERE is_deleted = FALSE;
CREATE INDEX IF NOT EXISTS idx_transactions_wallet_contact ON transactions_projection(wallet_id, contact_id) WHERE is_deleted = FALSE;

-- Update existing indexes to include wallet_id where appropriate
-- Drop old indexes that don't include wallet_id (will be recreated with wallet_id)
DROP INDEX IF EXISTS idx_events_user_aggregate;
DROP INDEX IF EXISTS idx_events_user_created;
DROP INDEX IF EXISTS idx_contacts_user;
DROP INDEX IF EXISTS idx_transactions_user_date;

-- Add comments
COMMENT ON COLUMN events.wallet_id IS 'Wallet this event belongs to. All events are scoped to a wallet.';
COMMENT ON COLUMN contacts_projection.wallet_id IS 'Wallet this contact belongs to. Contacts are isolated per wallet.';
COMMENT ON COLUMN transactions_projection.wallet_id IS 'Wallet this transaction belongs to. Transactions are isolated per wallet.';
