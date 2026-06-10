-- Add username column to contacts_projection
ALTER TABLE contacts_projection ADD COLUMN IF NOT EXISTS username VARCHAR(100);

-- Create index for username searches
CREATE INDEX IF NOT EXISTS idx_contacts_username ON contacts_projection(username) WHERE username IS NOT NULL AND is_deleted = FALSE;
