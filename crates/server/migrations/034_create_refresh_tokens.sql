-- Refresh tokens for "stay logged in" without long-lived access JWTs.
--
-- Access tokens (JWTs) stay short-lived (15 minutes). Refresh tokens are
-- long-lived random opaque strings (30 days) the client trades for a
-- fresh access+refresh pair on /api/auth/refresh.
--
-- We store only a SHA-256 hash of the raw token (column `token_hash`).
-- The raw token never lives at rest — leaking the DB doesn't leak
-- session credentials.
--
-- Rotation: every successful refresh issues a new refresh token AND
-- revokes the one that was used. `replaced_by_id` links old → new so
-- a "reused" old token is a strong signal of token theft (a stolen
-- copy was redeemed before the legitimate client redeemed it). On
-- detection, all of that user's refresh tokens are revoked, forcing
-- a re-login on every device.

CREATE TABLE IF NOT EXISTS refresh_tokens (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id       UUID NOT NULL REFERENCES users_projection(id) ON DELETE CASCADE,
    token_hash    TEXT NOT NULL UNIQUE,
    expires_at    TIMESTAMP NOT NULL,
    created_at    TIMESTAMP NOT NULL DEFAULT NOW(),
    revoked_at    TIMESTAMP,
    replaced_by_id UUID REFERENCES refresh_tokens(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_refresh_tokens_user ON refresh_tokens(user_id);
CREATE INDEX IF NOT EXISTS idx_refresh_tokens_hash ON refresh_tokens(token_hash);
CREATE INDEX IF NOT EXISTS idx_refresh_tokens_expires_at ON refresh_tokens(expires_at);
