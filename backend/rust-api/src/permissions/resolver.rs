use sqlx::PgPool;
use std::collections::HashSet;
use uuid::Uuid;

use super::action::Action;
use super::context::PermissionContext;
use super::queries;
use super::resource::Resource;
use crate::database::error::DbError;

/// Check if user is a wallet owner (stored in wallet_owners table)
async fn is_wallet_owner(pool: &PgPool, wallet_id: Uuid, user_id: Uuid) -> Result<bool, DbError> {
    let is_owner: bool = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM wallet_owners WHERE wallet_id = $1 AND user_id = $2)",
    )
    .bind(wallet_id)
    .bind(user_id)
    .fetch_one(pool)
    .await
    .map_err(|e| DbError::PermissionResolution(e.to_string()))?;

    Ok(is_owner)
}

/// Resolve allowed actions for a user on a resource
/// Uses single JOIN query for efficiency
pub async fn resolve_actions(
    pool: &PgPool,
    ctx: &PermissionContext,
    resource: &Resource,
) -> Result<HashSet<Action>, DbError> {
    // Owners have all permissions
    if is_wallet_owner(pool, ctx.wallet_id, ctx.user_id).await? {
        return Ok(Action::all().iter().copied().collect());
    }

    // Handle ContactGroup resources specially using cached permission matrix
    if let Resource::ContactGroup(group_id) = resource {
        // Query cached matrix: O(1) index lookup instead of expensive JOINs
        // The cache is computed when users are added/permissions change
        let cached_perms: Vec<(String, bool)> = sqlx::query_as(
            r#"
            SELECT pa.name, ucpm.is_deny
            FROM user_permission_matrix_cache ucpm
            JOIN permission_actions pa ON pa.id = ucpm.permission_action_id
            WHERE ucpm.wallet_id = $1
              AND ucpm.user_id = $2
              AND ucpm.contact_group_id = $3
            "#,
        )
        .bind(ctx.wallet_id)
        .bind(ctx.user_id)
        .bind(group_id)
        .fetch_all(pool)
        .await
        .map_err(|e| DbError::PermissionResolution(e.to_string()))?;

        // Build allowed actions, respecting deny overrides
        let mut actions = HashSet::new();
        for (name, is_deny) in cached_perms {
            if !is_deny {
                if let Some(action) = Action::from_str(&name) {
                    actions.insert(action);
                }
            }
        }
        return Ok(actions);
    }

    // Get resource ID (None for wildcard resources)
    let resource_id = resource.id();

    // Execute single query to get allowed actions for Contact/Transaction/Wallet resources
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
    // Owners can perform any action
    if is_wallet_owner(pool, ctx.wallet_id, ctx.user_id).await? {
        return Ok(true);
    }

    let allowed = resolve_actions(pool, ctx, resource).await?;

    // Check if action is allowed directly or via dependency
    Ok(allowed.iter().any(|a| a.implies(action)))
}

/// Rebuild user readable events cache by computing permissions for all events
pub async fn rebuild_readable_events_cache(
    pool: &PgPool,
    ctx: &PermissionContext,
    all_events: &[crate::domain::events::DomainEvent],
) -> Result<(), DbError> {
    // Delete existing cache
    sqlx::query(
        "DELETE FROM user_readable_events WHERE wallet_id = $1 AND user_id = $2",
    )
    .bind(ctx.wallet_id)
    .bind(ctx.user_id)
    .execute(pool)
    .await?;

    if all_events.is_empty() {
        return Ok(());
    }

    // Compute readable events and populate cache
    let readable_ids = filter_readable_events(pool, ctx, all_events).await?;

    // Batch insert readable events
    for event_id in readable_ids {
        sqlx::query(
            r#"
            INSERT INTO user_readable_events (wallet_id, user_id, event_id)
            VALUES ($1, $2, $3)
            ON CONFLICT (wallet_id, user_id, event_id) DO NOTHING
            "#,
        )
        .bind(ctx.wallet_id)
        .bind(ctx.user_id)
        .bind(event_id)
        .execute(pool)
        .await?;
    }

    Ok(())
}

/// Get all readable contacts for sync filtering
/// Returns contact IDs the user can read
pub async fn get_readable_contacts(
    pool: &PgPool,
    ctx: &PermissionContext,
) -> Result<HashSet<Uuid>, DbError> {
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
        // Get all contacts for this wallet
        let all_contacts: Vec<Uuid> = sqlx::query_scalar(
            "SELECT id FROM contacts_projection WHERE wallet_id = $1 AND is_deleted = false",
        )
        .bind(ctx.wallet_id)
        .fetch_all(pool)
        .await
        .map_err(|e| DbError::PermissionResolution(e.to_string()))?;
        Ok(all_contacts.into_iter().collect())
    } else {
        Ok(explicit.into_iter().collect()) // Specific contacts only
    }
}

/// Get all contacts whose transactions a user can read (for sync filtering)
/// Returns contact IDs whose transactions the user can read
pub async fn get_readable_transaction_contacts(
    pool: &PgPool,
    ctx: &PermissionContext,
) -> Result<HashSet<Uuid>, DbError> {
    // Try explicit contact groups first
    let explicit: Vec<Uuid> = sqlx::query_scalar(queries::GET_READABLE_TRANSACTION_CONTACTS_QUERY)
        .bind(ctx.wallet_id)
        .bind(ctx.user_id)
        .fetch_all(pool)
        .await
        .map_err(|e| DbError::PermissionResolution(e.to_string()))?;

    // Check if user can read via all_contacts group
    let query = format!(
        "SELECT EXISTS(SELECT 1 FROM ({}) AS t LIMIT 1)",
        queries::GET_READABLE_TRANSACTION_CONTACTS_VIA_ALL_QUERY
    );
    let can_read_all: bool = sqlx::query_scalar(&query)
        .bind(ctx.wallet_id)
        .bind(ctx.user_id)
        .fetch_one(pool)
        .await
        .map_err(|e| DbError::PermissionResolution(e.to_string()))?;

    if can_read_all {
        // Get all contacts for this wallet
        let all_contacts: Vec<Uuid> = sqlx::query_scalar(
            "SELECT id FROM contacts_projection WHERE wallet_id = $1 AND is_deleted = false",
        )
        .bind(ctx.wallet_id)
        .fetch_all(pool)
        .await
        .map_err(|e| DbError::PermissionResolution(e.to_string()))?;
        Ok(all_contacts.into_iter().collect())
    } else {
        Ok(explicit.into_iter().collect()) // Specific contacts only
    }
}

/// Filter events to return only those readable by user
/// Uses proven permission computation functions with single SQL filter query
pub async fn filter_readable_events(
    pool: &PgPool,
    ctx: &PermissionContext,
    events: &[crate::domain::events::DomainEvent],
) -> Result<Vec<Uuid>, DbError> {
    if events.is_empty() {
        return Ok(Vec::new());
    }

    // Use proven permission functions to compute readable sets
    let readable_contacts = get_readable_contacts(pool, ctx).await?;
    let readable_transaction_contacts = get_readable_transaction_contacts(pool, ctx).await?;

    // Single SQL query to filter events using computed permission sets
    let event_ids: Vec<Uuid> = events.iter().map(|e| e.id).collect();
    let readable_contact_uuids: Vec<Uuid> = readable_contacts.iter().copied().collect();
    let readable_transaction_contact_uuids: Vec<Uuid> =
        readable_transaction_contacts.iter().copied().collect();

    let readable_ids: Vec<Uuid> = sqlx::query_scalar(
        r#"
        SELECT DISTINCT e.event_id
        FROM events e
        WHERE e.wallet_id = $1
          AND e.event_id = ANY($2::uuid[])
          AND (
            -- Contact events
            (e.aggregate_type = 'contact' AND e.aggregate_id = ANY($3::uuid[]))
            -- Transaction events
            OR (e.aggregate_type = 'transaction' AND e.event_type IN ('CREATED', 'UPDATED')
                AND (e.event_data->>'contact_id')::uuid = ANY($4::uuid[]))
            -- Delete/Undo events
            OR (e.aggregate_type = 'transaction' AND e.event_type IN ('DELETED', 'UNDO')
                AND ARRAY_LENGTH($4::uuid[], 1) > 0)
            -- Permission and wallet events
            OR (e.aggregate_type = 'permission' OR e.aggregate_type = 'wallet')
          )
        "#,
    )
    .bind(ctx.wallet_id)
    .bind(&event_ids)
    .bind(&readable_contact_uuids)
    .bind(&readable_transaction_contact_uuids)
    .fetch_all(pool)
    .await
    .map_err(|e| DbError::PermissionResolution(e.to_string()))?;

    Ok(readable_ids)
}
