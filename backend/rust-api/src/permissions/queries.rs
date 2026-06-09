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

/// Permitted contacts for a single permission action (`$3`), respecting deny-wins.
///
/// Returns the set of contact IDs the user has permission to perform `$3` on.
/// "User's groups" = `all_users` (every wallet member) + any user-groups the
/// user is explicitly a member of via `user_group_members`. A matrix row matches
/// a contact if its contact_group is `all_contacts` (covers every contact in the
/// wallet) or contains the contact via `contact_group_members`.
///
/// Resolution (three states per action × group):
///   - allowed: matrix row with `is_deny = false`
///   - denied:  matrix row with `is_deny = true` — wins over any allow
///   - unset:   no matrix row — contributes nothing
///
/// `is_deleted` on contacts_projection is intentionally NOT filtered: this query
/// is used by filter_readable_events to decide event visibility, and a user with
/// access to a contact must still see that contact's DELETE event. Display-layer
/// filtering for soft-deleted contacts belongs at the API boundary.
pub const PERMITTED_CONTACTS_FOR_ACTION: &str = r#"
WITH user_groups_for_user AS (
  SELECT ug.id
  FROM user_groups ug
  WHERE ug.wallet_id = $1
    AND (
      ug.name = 'all_users'
      OR EXISTS (
        SELECT 1 FROM user_group_members ugm
        WHERE ugm.user_group_id = ug.id AND ugm.user_id = $2
      )
    )
),
user_matrix AS (
  SELECT m.contact_group_id, m.is_deny
  FROM group_permission_matrix m
    JOIN permission_actions pa ON pa.id = m.permission_action_id
    JOIN contact_groups cg ON cg.id = m.contact_group_id AND cg.wallet_id = $1
  WHERE m.user_group_id IN (SELECT id FROM user_groups_for_user)
    AND pa.name = $3
),
allowed_contacts AS (
  SELECT c.id
  FROM user_matrix um
    JOIN contact_groups cg ON cg.id = um.contact_group_id AND cg.name = 'all_contacts'
    JOIN contacts_projection c ON c.wallet_id = $1
  WHERE um.is_deny = false
  UNION
  SELECT cgm.contact_id AS id
  FROM user_matrix um
    JOIN contact_groups cg ON cg.id = um.contact_group_id AND cg.name <> 'all_contacts'
    JOIN contact_group_members cgm ON cgm.contact_group_id = cg.id
  WHERE um.is_deny = false
),
denied_contacts AS (
  SELECT c.id
  FROM user_matrix um
    JOIN contact_groups cg ON cg.id = um.contact_group_id AND cg.name = 'all_contacts'
    JOIN contacts_projection c ON c.wallet_id = $1
  WHERE um.is_deny = true
  UNION
  SELECT cgm.contact_id AS id
  FROM user_matrix um
    JOIN contact_groups cg ON cg.id = um.contact_group_id AND cg.name <> 'all_contacts'
    JOIN contact_group_members cgm ON cgm.contact_group_id = cg.id
  WHERE um.is_deny = true
)
SELECT DISTINCT id FROM allowed_contacts
WHERE id NOT IN (SELECT id FROM denied_contacts)
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
