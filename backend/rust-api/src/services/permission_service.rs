//! Group-group permission resolution (Discord/Telegram style).
//! Owner/admin bypass; else resolve user groups x contact groups -> matrix -> allowed actions.

use sqlx::PgPool;
use std::collections::HashSet;
use uuid::Uuid;

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
    Ok(allowed.contains(action_name))
}

#[derive(Clone, Copy)]
pub enum ResourceType {
    Contact,
    Transaction,
    Events,
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
