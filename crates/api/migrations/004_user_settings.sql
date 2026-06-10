-- User settings table for storing user preferences on the server
CREATE TABLE IF NOT EXISTS user_settings (
    user_id UUID NOT NULL REFERENCES users_projection(id) ON DELETE CASCADE,
    setting_key VARCHAR(100) NOT NULL,
    setting_value TEXT,
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, setting_key)
);

CREATE INDEX IF NOT EXISTS idx_user_settings_user_id ON user_settings(user_id);
