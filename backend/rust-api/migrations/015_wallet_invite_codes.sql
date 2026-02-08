-- Invite codes: 4-digit code per wallet (for testing; later can be longer invite links).
-- One active code per wallet; generating a new code replaces the previous.
CREATE TABLE IF NOT EXISTS wallet_invite_codes (
    wallet_id UUID NOT NULL REFERENCES wallets(id) ON DELETE CASCADE,
    code VARCHAR(10) NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    created_by UUID REFERENCES users_projection(id),
    PRIMARY KEY (wallet_id),
    UNIQUE (code)
);

CREATE INDEX IF NOT EXISTS idx_wallet_invite_codes_code ON wallet_invite_codes(code);
COMMENT ON TABLE wallet_invite_codes IS 'One invite code per wallet. Anyone with the code can join the wallet as member.';
