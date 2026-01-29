-- Admin users table for admin panel authentication (separate from regular users)
CREATE TABLE IF NOT EXISTS admin_users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    username VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    email VARCHAR(255),
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    last_login_at TIMESTAMP,
    is_active BOOLEAN NOT NULL DEFAULT true
);

CREATE INDEX IF NOT EXISTS idx_admin_users_username ON admin_users(username);
CREATE INDEX IF NOT EXISTS idx_admin_users_active ON admin_users(is_active) WHERE is_active = true;

-- Create default admin user if none exists
-- Default credentials: admin / admin123
DO $$
DECLARE
    admin_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO admin_count FROM admin_users;
    
    IF admin_count = 0 THEN
        INSERT INTO admin_users (username, password_hash, email, is_active)
        VALUES (
            'admin',
            '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5GyY5Y5Y5Y5Y5Y', -- Placeholder - will be set via manage script
            'admin@debitum.local',
            true
        );
    END IF;
END $$;

COMMENT ON TABLE admin_users IS 'Admin users for admin panel access (separate from regular application users)';
COMMENT ON COLUMN admin_users.username IS 'Admin username for login';
COMMENT ON COLUMN admin_users.is_active IS 'Whether this admin account is active';
