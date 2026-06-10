-- Login logs table for tracking user authentication attempts
CREATE TABLE IF NOT EXISTS login_logs (
    id BIGSERIAL PRIMARY KEY,
    user_id UUID REFERENCES users_projection(id) ON DELETE CASCADE, -- NULL for failed logins with unknown user
    login_at TIMESTAMP NOT NULL DEFAULT NOW(),
    ip_address VARCHAR(45), -- IPv4 or IPv6
    user_agent TEXT,
    success BOOLEAN NOT NULL DEFAULT true,
    failure_reason TEXT -- Only set when success = false
);

CREATE INDEX IF NOT EXISTS idx_login_logs_user ON login_logs(user_id, login_at DESC);
CREATE INDEX IF NOT EXISTS idx_login_logs_time ON login_logs(login_at DESC);

COMMENT ON TABLE login_logs IS 'Logs all login attempts (successful and failed) for security auditing';
COMMENT ON COLUMN login_logs.success IS 'true for successful logins, false for failed attempts';
COMMENT ON COLUMN login_logs.failure_reason IS 'Reason for failed login (e.g., "invalid_password", "user_not_found")';
