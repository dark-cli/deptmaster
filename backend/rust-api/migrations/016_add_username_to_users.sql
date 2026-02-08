-- Add username to users_projection and make it the primary identifier
ALTER TABLE users_projection ADD COLUMN username VARCHAR(255);

-- Populate username with email for existing users
UPDATE users_projection SET username = email;

-- Make username unique and not null
ALTER TABLE users_projection ALTER COLUMN username SET NOT NULL;
ALTER TABLE users_projection ADD CONSTRAINT users_projection_username_key UNIQUE (username);

-- Make email nullable (optional)
ALTER TABLE users_projection ALTER COLUMN email DROP NOT NULL;
