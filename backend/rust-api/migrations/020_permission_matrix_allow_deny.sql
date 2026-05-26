-- Layered permissions: allow + deny (Discord-style). One row per (ug, cg, action); is_deny = true means deny.
-- Resolution: allow_union - deny_union. Unset = no row.

ALTER TABLE group_permission_matrix
ADD COLUMN IF NOT EXISTS is_deny BOOLEAN NOT NULL DEFAULT false;

-- One row per (ug, cg, action): is_deny false = allow, true = deny. PK unchanged.
COMMENT ON COLUMN group_permission_matrix.is_deny IS 'false = allow, true = deny (deny wins in resolution).';
