/// SQL queries for permission resolution
///
/// These are constants to centralize all permission-related SQL

/// Get allowed actions for a user on a resource (single JOIN query)
///
/// Joins user groups → membership → permission matrix → contact groups → permission actions
/// Returns action names that the user is allowed to perform
pub const RESOLVE_ACTIONS_QUERY: &str = r#"
SELECT DISTINCT pa.name
FROM user_groups ug
  JOIN user_group_members ugm ON ugm.user_group_id = ug.id
  JOIN group_permission_matrix m ON m.user_group_id = ug.id
  JOIN contact_groups cg ON cg.id = m.contact_group_id
  JOIN permission_actions pa ON pa.id = m.permission_action_id
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
    AND c.is_deleted = false
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
    AND c.is_deleted = false
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
    AND c.is_deleted = false
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
    AND c.is_deleted = false
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
    AND c.is_deleted = false
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
    AND c.is_deleted = false
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
    AND c.is_deleted = false
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
    AND c.is_deleted = false
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
