/// SQL queries for permission resolution
///
/// These are constants to centralize all permission-related SQL

/// Get allowed actions for a user on a resource.
///
/// Resolution rule (matches the Discord-style allow+deny model from migration 020):
///   - An action is allowed if at least one allow row (`is_deny = false`) matches.
///   - Any deny row (`is_deny = true`) for the same action overrides — deny wins.
///   - "Matches" = user is in a group whose matrix row covers (all_contacts OR a
///     specific contact group that contains this contact $3).
pub const RESOLVE_ACTIONS_QUERY: &str = r#"
WITH user_matrix AS (
  SELECT m.permission_action_id, m.is_deny
  FROM user_groups ug
    JOIN user_group_members ugm ON ugm.user_group_id = ug.id
    JOIN group_permission_matrix m ON m.user_group_id = ug.id
    JOIN contact_groups cg ON cg.id = m.contact_group_id
  WHERE ug.wallet_id = $1
    AND ugm.user_id = $2
    AND (
      cg.name = 'all_contacts'
      OR EXISTS (
        SELECT 1 FROM contact_group_members cgm
        WHERE cgm.contact_group_id = cg.id
          AND cgm.contact_id = $3
      )
    )
),
allowed AS (
  SELECT DISTINCT permission_action_id FROM user_matrix WHERE is_deny = false
),
denied AS (
  SELECT DISTINCT permission_action_id FROM user_matrix WHERE is_deny = true
)
SELECT pa.name
FROM permission_actions pa
WHERE pa.id IN (SELECT permission_action_id FROM allowed)
  AND pa.id NOT IN (SELECT permission_action_id FROM denied)
"#;

/// Get all contacts a user can read (for sync filtering)
/// Uses UNION to split implicit all_users path from explicit membership path
/// for optimal query planning and performance
pub const GET_READABLE_CONTACTS_QUERY: &str = r#"
(
  SELECT DISTINCT c.id
  FROM user_groups ug
    JOIN group_permission_matrix m ON m.user_group_id = ug.id
    JOIN permission_actions pa ON pa.id = m.permission_action_id
    JOIN contact_groups cg ON cg.id = m.contact_group_id
    JOIN contact_group_members cgm ON cgm.contact_group_id = cg.id
    JOIN contacts_projection c ON c.id = cgm.contact_id
  WHERE ug.wallet_id = $1
    AND ug.name = 'all_users'
    AND pa.name = 'contact:read'
    AND c.wallet_id = $1
    -- NOTE: is_deleted filter intentionally omitted. These queries decide "what is
    -- the user allowed to read events about" (used by filter_readable_events for
    -- sync). A user must still receive the DELETE/UNDO events for a contact they
    -- had access to — filtering them out here makes the contact's own deletion
    -- invisible to other apps.
)
UNION
(
  SELECT DISTINCT c.id
  FROM user_group_members ugm
    JOIN group_permission_matrix m ON m.user_group_id = ugm.user_group_id
    JOIN permission_actions pa ON pa.id = m.permission_action_id
    JOIN contact_groups cg ON cg.id = m.contact_group_id
    JOIN contact_group_members cgm ON cgm.contact_group_id = cg.id
    JOIN contacts_projection c ON c.id = cgm.contact_id
    JOIN user_groups ug ON ug.id = ugm.user_group_id
  WHERE ugm.user_id = $2
    AND ug.wallet_id = $1
    AND pa.name = 'contact:read'
    AND c.wallet_id = $1
    -- NOTE: is_deleted filter intentionally omitted. These queries decide "what is
    -- the user allowed to read events about" (used by filter_readable_events for
    -- sync). A user must still receive the DELETE/UNDO events for a contact they
    -- had access to — filtering them out here makes the contact's own deletion
    -- invisible to other apps.
)
"#;

/// Get all contacts a user can read via all_contacts group (for sync filtering)
/// Uses UNION to split implicit all_users path from explicit membership path
pub const GET_READABLE_CONTACTS_VIA_ALL_QUERY: &str = r#"
(
  SELECT DISTINCT c.id
  FROM user_groups ug
    JOIN group_permission_matrix m ON m.user_group_id = ug.id
    JOIN permission_actions pa ON pa.id = m.permission_action_id
    JOIN contact_groups cg ON cg.id = m.contact_group_id AND cg.name = 'all_contacts'
    JOIN contacts_projection c ON c.wallet_id = cg.wallet_id
  WHERE ug.wallet_id = $1
    AND ug.name = 'all_users'
    AND pa.name = 'contact:read'
    -- NOTE: is_deleted filter intentionally omitted. These queries decide "what is
    -- the user allowed to read events about" (used by filter_readable_events for
    -- sync). A user must still receive the DELETE/UNDO events for a contact they
    -- had access to — filtering them out here makes the contact's own deletion
    -- invisible to other apps.
)
UNION
(
  SELECT DISTINCT c.id
  FROM user_group_members ugm
    JOIN group_permission_matrix m ON m.user_group_id = ugm.user_group_id
    JOIN permission_actions pa ON pa.id = m.permission_action_id
    JOIN contact_groups cg ON cg.id = m.contact_group_id AND cg.name = 'all_contacts'
    JOIN contacts_projection c ON c.wallet_id = cg.wallet_id
    JOIN user_groups ug ON ug.id = ugm.user_group_id
  WHERE ugm.user_id = $2
    AND ug.wallet_id = $1
    AND pa.name = 'contact:read'
    -- NOTE: is_deleted filter intentionally omitted. These queries decide "what is
    -- the user allowed to read events about" (used by filter_readable_events for
    -- sync). A user must still receive the DELETE/UNDO events for a contact they
    -- had access to — filtering them out here makes the contact's own deletion
    -- invisible to other apps.
)
"#;

/// Get all contacts whose transactions a user can read (for sync filtering)
/// Uses UNION to split implicit all_users path from explicit membership path
pub const GET_READABLE_TRANSACTION_CONTACTS_QUERY: &str = r#"
(
  SELECT DISTINCT c.id
  FROM user_groups ug
    JOIN group_permission_matrix m ON m.user_group_id = ug.id
    JOIN permission_actions pa ON pa.id = m.permission_action_id
    JOIN contact_groups cg ON cg.id = m.contact_group_id
    JOIN contact_group_members cgm ON cgm.contact_group_id = cg.id
    JOIN contacts_projection c ON c.id = cgm.contact_id
  WHERE ug.wallet_id = $1
    AND ug.name = 'all_users'
    AND pa.name = 'transaction:read'
    AND c.wallet_id = $1
    -- NOTE: is_deleted filter intentionally omitted. These queries decide "what is
    -- the user allowed to read events about" (used by filter_readable_events for
    -- sync). A user must still receive the DELETE/UNDO events for a contact they
    -- had access to — filtering them out here makes the contact's own deletion
    -- invisible to other apps.
)
UNION
(
  SELECT DISTINCT c.id
  FROM user_group_members ugm
    JOIN group_permission_matrix m ON m.user_group_id = ugm.user_group_id
    JOIN permission_actions pa ON pa.id = m.permission_action_id
    JOIN contact_groups cg ON cg.id = m.contact_group_id
    JOIN contact_group_members cgm ON cgm.contact_group_id = cg.id
    JOIN contacts_projection c ON c.id = cgm.contact_id
    JOIN user_groups ug ON ug.id = ugm.user_group_id
  WHERE ugm.user_id = $2
    AND ug.wallet_id = $1
    AND pa.name = 'transaction:read'
    AND c.wallet_id = $1
    -- NOTE: is_deleted filter intentionally omitted. These queries decide "what is
    -- the user allowed to read events about" (used by filter_readable_events for
    -- sync). A user must still receive the DELETE/UNDO events for a contact they
    -- had access to — filtering them out here makes the contact's own deletion
    -- invisible to other apps.
)
"#;

/// Get all contacts whose transactions a user can read via all_contacts group (for sync filtering)
/// Uses UNION to split implicit all_users path from explicit membership path
pub const GET_READABLE_TRANSACTION_CONTACTS_VIA_ALL_QUERY: &str = r#"
(
  SELECT DISTINCT c.id
  FROM user_groups ug
    JOIN group_permission_matrix m ON m.user_group_id = ug.id
    JOIN permission_actions pa ON pa.id = m.permission_action_id
    JOIN contact_groups cg ON cg.id = m.contact_group_id AND cg.name = 'all_contacts'
    JOIN contacts_projection c ON c.wallet_id = cg.wallet_id
  WHERE ug.wallet_id = $1
    AND ug.name = 'all_users'
    AND pa.name = 'transaction:read'
    -- NOTE: is_deleted filter intentionally omitted. These queries decide "what is
    -- the user allowed to read events about" (used by filter_readable_events for
    -- sync). A user must still receive the DELETE/UNDO events for a contact they
    -- had access to — filtering them out here makes the contact's own deletion
    -- invisible to other apps.
)
UNION
(
  SELECT DISTINCT c.id
  FROM user_group_members ugm
    JOIN group_permission_matrix m ON m.user_group_id = ugm.user_group_id
    JOIN permission_actions pa ON pa.id = m.permission_action_id
    JOIN contact_groups cg ON cg.id = m.contact_group_id AND cg.name = 'all_contacts'
    JOIN contacts_projection c ON c.wallet_id = cg.wallet_id
    JOIN user_groups ug ON ug.id = ugm.user_group_id
  WHERE ugm.user_id = $2
    AND ug.wallet_id = $1
    AND pa.name = 'transaction:read'
    -- NOTE: is_deleted filter intentionally omitted. These queries decide "what is
    -- the user allowed to read events about" (used by filter_readable_events for
    -- sync). A user must still receive the DELETE/UNDO events for a contact they
    -- had access to — filtering them out here makes the contact's own deletion
    -- invisible to other apps.
)
"#;

/// Check if user is a member of a wallet
pub const CHECK_WALLET_MEMBER_QUERY: &str = r#"
SELECT EXISTS(
  SELECT 1 FROM wallet_users
  WHERE wallet_id = $1 AND user_id = $2
)
"#;

/// Get user's wallet role
pub const GET_USER_ROLE_QUERY: &str = r#"
SELECT role FROM wallet_users
WHERE wallet_id = $1 AND user_id = $2
LIMIT 1
"#;
