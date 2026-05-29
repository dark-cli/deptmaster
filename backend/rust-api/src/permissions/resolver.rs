use sqlx::PgPool;
use uuid::Uuid;
use std::collections::HashSet;

use crate::database::error::DbError;
use super::action::Action;
use super::context::PermissionContext;
use super::resource::Resource;
use super::queries;

/// Resolve allowed actions for a user on a resource
/// Uses single JOIN query for efficiency
pub async fn resolve_actions(
    pool: &PgPool,
    ctx: &PermissionContext,
    resource: &Resource,
) -> Result<HashSet<Action>, DbError> {
    // Owner and admin bypass - they can do everything
    if ctx.bypasses_permissions() {
        return Ok(Action::all().iter().copied().collect());
    }

    // Get resource ID (None for wildcard resources)
    let resource_id = resource.id();

    // Execute single query to get allowed actions
    let action_names: Vec<String> = sqlx::query_scalar(queries::RESOLVE_ACTIONS_QUERY)
        .bind(ctx.wallet_id)
        .bind(ctx.user_id)
        .bind(resource_id)
        .fetch_all(pool)
        .await
        .map_err(|e| DbError::PermissionResolution(e.to_string()))?;

    // Convert string action names to enum
    let mut actions = HashSet::new();
    for name in action_names {
        if let Some(action) = Action::from_str(&name) {
            actions.insert(action);
        }
    }

    Ok(actions)
}

/// Check if user can perform action on resource
pub async fn can_perform(
    pool: &PgPool,
    ctx: &PermissionContext,
    action: Action,
    resource: &Resource,
) -> Result<bool, DbError> {
    // Owner and admin bypass
    if ctx.bypasses_permissions() {
        return Ok(true);
    }

    let allowed = resolve_actions(pool, ctx, resource).await?;

    // Check if action is allowed directly or via dependency
    Ok(allowed.iter().any(|a| a.implies(action)))
}

/// Get all readable contacts for sync filtering
/// Returns contact IDs the user can read
pub async fn get_readable_contacts(
    pool: &PgPool,
    ctx: &PermissionContext,
) -> Result<Option<HashSet<Uuid>>, DbError> {
    // Owner and admin can read all
    if ctx.bypasses_permissions() {
        return Ok(None); // None = can read all
    }

    // Try explicit contact groups first
    let explicit: Vec<Uuid> = sqlx::query_scalar(queries::GET_READABLE_CONTACTS_QUERY)
        .bind(ctx.wallet_id)
        .bind(ctx.user_id)
        .fetch_all(pool)
        .await
        .map_err(|e| DbError::PermissionResolution(e.to_string()))?;

    // Check if user can read via all_contacts group
    let query = format!(
        "SELECT EXISTS(SELECT 1 FROM ({}) AS t LIMIT 1)",
        queries::GET_READABLE_CONTACTS_VIA_ALL_QUERY
    );
    let can_read_all: bool = sqlx::query_scalar(&query)
        .bind(ctx.wallet_id)
        .bind(ctx.user_id)
        .fetch_one(pool)
        .await
        .map_err(|e| DbError::PermissionResolution(e.to_string()))?;

    if can_read_all {
        Ok(None) // Can read all contacts
    } else {
        Ok(Some(explicit.into_iter().collect())) // Specific contacts only
    }
}
