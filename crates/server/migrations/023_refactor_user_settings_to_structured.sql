-- Refactor user_settings from key-value pairs to structured columns
-- This migration adds structured columns and migrates existing data

-- Step 1: Add new structured columns to user_settings
ALTER TABLE user_settings
ADD COLUMN IF NOT EXISTS dark_mode BOOLEAN DEFAULT true,
ADD COLUMN IF NOT EXISTS default_direction VARCHAR(32) DEFAULT 'give',
ADD COLUMN IF NOT EXISTS flip_colors BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS due_date_enabled BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS default_due_date_days INT DEFAULT 30,
ADD COLUMN IF NOT EXISTS default_due_date_switch BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS created_at TIMESTAMP DEFAULT NOW();

-- Step 2: Migrate existing key-value pairs to structured columns
UPDATE user_settings
SET
    dark_mode = CASE
        WHEN setting_key = 'dark_mode' AND setting_value = 'true' THEN true
        ELSE dark_mode
    END,
    default_direction = CASE
        WHEN setting_key = 'default_direction' THEN COALESCE(setting_value, 'give')
        ELSE default_direction
    END,
    flip_colors = CASE
        WHEN setting_key = 'flip_colors' AND setting_value = 'true' THEN true
        ELSE flip_colors
    END,
    due_date_enabled = CASE
        WHEN setting_key = 'due_date_enabled' AND setting_value = 'true' THEN true
        ELSE due_date_enabled
    END,
    default_due_date_days = CASE
        WHEN setting_key = 'default_due_date_days' THEN COALESCE((setting_value::INT), 30)
        ELSE default_due_date_days
    END,
    default_due_date_switch = CASE
        WHEN setting_key = 'default_due_date_switch' AND setting_value = 'true' THEN true
        ELSE default_due_date_switch
    END
WHERE setting_key IN ('dark_mode', 'default_direction', 'flip_colors', 'due_date_enabled', 'default_due_date_days', 'default_due_date_switch');

-- Step 3: Create unique constraint on user_id to maintain one row per user (after consolidation)
-- We'll use a two-step process: group by user_id and keep the most recent record
DELETE FROM user_settings
WHERE (user_id, updated_at) NOT IN (
    SELECT user_id, MAX(updated_at)
    FROM user_settings
    WHERE user_id IS NOT NULL
    GROUP BY user_id
);

-- Step 4: Drop old key-value columns (setting_key, setting_value)
ALTER TABLE user_settings
DROP COLUMN setting_key,
DROP COLUMN setting_value;

-- Step 5: Ensure user_id is PRIMARY KEY
ALTER TABLE user_settings
DROP CONSTRAINT IF EXISTS user_settings_pkey;

ALTER TABLE user_settings
ADD PRIMARY KEY (user_id);

-- Step 6: Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_user_settings_created_at ON user_settings(created_at);
CREATE INDEX IF NOT EXISTS idx_user_settings_updated_at ON user_settings(updated_at);
