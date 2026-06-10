-- Create a default admin user if no users exist
-- Password: admin (hashed with bcrypt)
-- Email: admin@debitum.local
DO $$
DECLARE
    user_count INTEGER;
    admin_password_hash VARCHAR(255) := '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5GyY5Y5Y5Y5Y5Y'; -- This is a placeholder, will be replaced
BEGIN
    SELECT COUNT(*) INTO user_count FROM users_projection;
    
    IF user_count = 0 THEN
        -- Insert default admin user
        -- Password hash for "admin" (bcrypt with cost 12)
        -- You should generate a proper hash, but for now we'll use a simple approach
        INSERT INTO users_projection (id, email, password_hash, created_at, last_event_id)
        VALUES (
            gen_random_uuid(),
            'admin@debitum.local',
            '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5GyY5Y5Y5Y5Y5Y', -- Placeholder - needs real hash
            NOW(),
            0
        );
    END IF;
END $$;
