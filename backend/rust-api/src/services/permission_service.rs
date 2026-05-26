//! Group-group permission resolution (Discord/Telegram style).
//! Owner/admin bypass; else resolve user groups x contact groups -> matrix -> allowed actions.

use sqlx::{PgPool, Row};
use std::collections::HashSet;
use uuid::Uuid;

/// Precomputed read permissions for sync: one batch of queries, then filter events in memory.
#[derive(Clone)]
pub struct SyncReadContext {
    /// True when user has transaction:read on all_contacts (can read all transactions). Used to set transaction_contact_ids_allowed = None.
    #[allow(dead_code)]
    pub has_transaction_read: bool,
    /// None = can read all contacts; Some(set) = can only read these contact ids (from contact:read groups).
    pub contact_ids_allowed: Option<HashSet<Uuid>>,
    /// None = can read all transactions; Some(set) = can only read transactions for these contact ids.
    /// Transactions don't have their own groups; they follow the contact's contact groups. So we derive
    /// this from contact groups where the user has transaction:read.
    pub transaction_contact_ids_allowed: Option<HashSet<Uuid>>,
}

/// If wallet role is owner or admin, user has all actions. Otherwise check matrix.
pub async fn can_perform(
    pool: &PgPool,
    wallet_id: Uuid,
    user_id: Uuid,
    user_role: &str,
    action_name: &str,
    resource_type: ResourceType,
    resource_id: Option<Uuid>,
) -> Result<bool, sqlx::Error> {
    if user_role == "owner" || user_role == "admin" {
        return Ok(true);
    }
    let allowed = resolve_allowed_actions(pool, wallet_id, user_id, resource_type, resource_id).await?;
    if allowed.contains(action_name) {
        return Ok(true);
    }
    // contact:edit is UI alias for contact:update (sync push checks contact:update)
    if action_name == "contact:update" && allowed.contains("contact:edit") {
        return Ok(true);
    }
    if action_name == "contact:edit" && allowed.contains("contact:update") {
        return Ok(true);
    }
    Ok(false)
}

/// True if the user has the given action on the given contact group (via user groups × matrix). Owner/admin have all.
pub async fn can_perform_action_on_contact_group(
    pool: &PgPool,
    wallet_id: Uuid,
    user_id: Uuid,
    user_role: &str,
    contact_group_id: Uuid,
    action_name: &str,
) -> Result<bool, sqlx::Error> {
    if user_role == "owner" || user_role == "admin" {
        return Ok(true);
    }
    let user_group_ids = resolve_user_groups(pool, wallet_id, user_id).await?;
    if user_group_ids.is_empty() {
        return Ok(false);
    }
    let has_action: bool = sqlx::query_scalar(
        r#"
        SELECT EXISTS(
            SELECT 1 FROM group_permission_matrix m
            JOIN permission_actions pa ON pa.id = m.permission_action_id
            JOIN contact_groups cg ON cg.id = m.contact_group_id AND cg.wallet_id = $1
            WHERE m.user_group_id = ANY($2)
              AND m.contact_group_id = $3
              AND pa.name = $4
        )
        "#,
    )
    .bind(wallet_id)
    .bind(&user_group_ids)
    .bind(contact_group_id)
    .bind(action_name)
    .fetch_one(pool)
    .await?;
    Ok(has_action)
}

#[derive(Clone, Copy)]
pub enum ResourceType {
    Contact,
    Transaction,
    Wallet,
}

/// Resolve allowed action names for (user, resource) via user groups x contact groups matrix.
/// Owner/admin are handled by caller (full access). Here we only do matrix resolution for members.
pub async fn resolve_allowed_actions(
    pool: &PgPool,
    wallet_id: Uuid,
    user_id: Uuid,
    resource_type: ResourceType,
    resource_id: Option<Uuid>,
) -> Result<HashSet<String>, sqlx::Error> {
    let user_group_ids = resolve_user_groups(pool, wallet_id, user_id).await?;
    let contact_group_ids = resolve_contact_groups_for_resource(pool, wallet_id, resource_type, resource_id).await?;

    if user_group_ids.is_empty() || contact_group_ids.is_empty() {
        return Ok(HashSet::new());
    }

    let action_names: Vec<String> = sqlx::query_scalar(
        r#"
        SELECT DISTINCT pa.name
        FROM group_permission_matrix m
        JOIN permission_actions pa ON pa.id = m.permission_action_id
        WHERE m.user_group_id = ANY($1)
          AND m.contact_group_id = ANY($2)
        "#,
    )
    .bind(&user_group_ids)
    .bind(&contact_group_ids)
    .fetch_all(pool)
    .await?;

    Ok(action_names.into_iter().collect())
}

/// User's groups in this wallet: all_users (implicit for every member) + explicit user_group_members.
async fn resolve_user_groups(pool: &PgPool, wallet_id: Uuid, user_id: Uuid) -> Result<Vec<Uuid>, sqlx::Error> {
    let ids: Vec<Uuid> = sqlx::query_scalar(
        r#"
        SELECT ug.id FROM user_groups ug
        WHERE ug.wallet_id = $1
          AND (
            ug.name = 'all_users'
            OR EXISTS (
              SELECT 1 FROM user_group_members ugm
              WHERE ugm.user_group_id = ug.id AND ugm.user_id = $2
            )
          )
        "#,
    )
    .bind(wallet_id)
    .bind(user_id)
    .fetch_all(pool)
    .await?;
    Ok(ids)
}

/// Contact groups for the resource. For contact: all_contacts (implicit) + contact_group_members. For wallet-level (events, list): just all_contacts.
async fn resolve_contact_groups_for_resource(
    pool: &PgPool,
    wallet_id: Uuid,
    resource_type: ResourceType,
    resource_id: Option<Uuid>,
) -> Result<Vec<Uuid>, sqlx::Error> {
    let all_contacts_id: Option<Uuid> = sqlx::query_scalar(
        "SELECT id FROM contact_groups WHERE wallet_id = $1 AND name = 'all_contacts' LIMIT 1",
    )
    .bind(wallet_id)
    .fetch_optional(pool)
    .await?;

    let mut group_ids = if let Some(id) = all_contacts_id {
        vec![id]
    } else {
        Vec::new()
    };

    if let (ResourceType::Contact, Some(contact_id)) = (resource_type, resource_id) {
        let extra: Vec<Uuid> = sqlx::query_scalar(
            "SELECT contact_group_id FROM contact_group_members WHERE contact_id = $1",
        )
        .bind(contact_id)
        .fetch_all(pool)
        .await?;
        for id in extra {
            if !group_ids.contains(&id) {
                group_ids.push(id);
            }
        }
    }

    Ok(group_ids)
}

/// Compute read context for sync in one batch (avoids N per-event permission queries).
pub async fn sync_read_context(
    pool: &PgPool,
    wallet_id: Uuid,
    user_id: Uuid,
    user_role: &str,
) -> Result<SyncReadContext, sqlx::Error> {
    if user_role == "owner" || user_role == "admin" {
        return Ok(SyncReadContext {
            has_transaction_read: true,
            contact_ids_allowed: None,
            transaction_contact_ids_allowed: None,
        });
    }
    let user_group_ids = resolve_user_groups(pool, wallet_id, user_id).await?;
    let all_contacts_id: Option<Uuid> = sqlx::query_scalar(
        "SELECT id FROM contact_groups WHERE wallet_id = $1 AND name = 'all_contacts' LIMIT 1",
    )
    .bind(wallet_id)
    .fetch_optional(pool)
    .await?;

    if user_group_ids.is_empty() {
        return Ok(SyncReadContext {
            has_transaction_read: false,
            contact_ids_allowed: Some(HashSet::new()),
            transaction_contact_ids_allowed: Some(HashSet::new()),
        });
    }

    // One query: which contact groups grant contact:read or transaction:read for this user's groups
    let rows = sqlx::query(
        r#"
        SELECT m.contact_group_id, pa.name
        FROM group_permission_matrix m
        JOIN permission_actions pa ON pa.id = m.permission_action_id
        WHERE m.user_group_id = ANY($1)
          AND pa.name IN ('contact:read', 'transaction:read')
        "#,
    )
    .bind(&user_group_ids)
    .fetch_all(pool)
    .await?;

    let mut contact_read_groups = HashSet::new();
    let mut transaction_read_groups = HashSet::new();
    for row in &rows {
        let cg_id: Uuid = row.get("contact_group_id");
        let name: String = row.get("name");
        if name == "contact:read" {
            contact_read_groups.insert(cg_id);
        } else if name == "transaction:read" {
            transaction_read_groups.insert(cg_id);
        }
    }

    let has_transaction_read = all_contacts_id
        .map(|id| transaction_read_groups.contains(&id))
        .unwrap_or(false);

    let contact_ids_allowed = if all_contacts_id
        .map(|id| contact_read_groups.contains(&id))
        .unwrap_or(false)
    {
        None
    } else if contact_read_groups.is_empty() {
        Some(HashSet::new())
    } else {
        let ids: Vec<Uuid> = sqlx::query_scalar(
            "SELECT contact_id FROM contact_group_members WHERE contact_group_id = ANY($1)",
        )
        .bind(contact_read_groups.into_iter().collect::<Vec<_>>())
        .fetch_all(pool)
        .await?;
        Some(ids.into_iter().collect())
    };

    // Transactions don't have their own groups; visibility is by contact's contact groups (transaction:read).
    let transaction_contact_ids_allowed = if has_transaction_read {
        None
    } else if transaction_read_groups.is_empty() {
        Some(HashSet::new())
    } else {
        let ids: Vec<Uuid> = sqlx::query_scalar(
            "SELECT contact_id FROM contact_group_members WHERE contact_group_id = ANY($1)",
        )
        .bind(transaction_read_groups.into_iter().collect::<Vec<_>>())
        .fetch_all(pool)
        .await?;
        Some(ids.into_iter().collect())
    };

    Ok(SyncReadContext {
        has_transaction_read,
        contact_ids_allowed,
        transaction_contact_ids_allowed,
    })
}

/// Return 403 body with DEBITUM_INSUFFICIENT_WALLET_PERMISSION for use in handlers.
pub fn insufficient_permission_response() -> (axum::http::StatusCode, axum::Json<serde_json::Value>) {
    (
        axum::http::StatusCode::FORBIDDEN,
        axum::Json(serde_json::json!({
            "code": "DEBITUM_INSUFFICIENT_WALLET_PERMISSION",
            "message": "Insufficient permissions for this action"
        })),
    )
}
