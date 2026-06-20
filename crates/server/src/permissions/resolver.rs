use sqlx::PgPool;
use std::collections::HashSet;
use uuid::Uuid;

use crate::database::error::DbError;
use domain::Action;
use domain::PermissionContext;
use domain::Resource;

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

/// Resolve allowed actions for a user on a resource.
///
/// Thin wrapper around the shared `resolver::resolve_actions`. The rules
/// (3-state matrix, deny wins, all_contacts wildcard, owner short-circuit)
/// live in the resolver crate; here we just plug in the server's
/// PermissionStore impl and a cache short-circuit.
pub async fn resolve_actions(
    pool: &PgPool,
    ctx: &PermissionContext,
    resource: &Resource,
) -> Result<HashSet<Action>, DbError> {
    // Server-only optimization: ContactGroup resources have a precomputed
    // user_permission_matrix_cache row. O(1) lookup beats the full
    // resolution pipeline. Owners still skip the cache (they get
    // Action::all unconditionally).
    if !super::server_store::ServerPermissionStore::new(pool)
        .is_wallet_owner(ctx.wallet_id, ctx.user_id)
        .await?
    {
        if let Resource::ContactGroup(group_id) = resource {
            let cached: Vec<(String, bool)> = sqlx::query_as(
                r#"
                SELECT pa.name, ucpm.is_deny
                  FROM user_permission_matrix_cache ucpm
                  JOIN permission_actions pa ON pa.id = ucpm.permission_action_id
                 WHERE ucpm.wallet_id = $1 AND ucpm.user_id = $2 AND ucpm.contact_group_id = $3
                "#,
            )
            .bind(ctx.wallet_id)
            .bind(ctx.user_id)
            .bind(group_id)
            .fetch_all(pool)
            .await
            .map_err(|e| DbError::PermissionResolution(e.to_string()))?;
            let mut allowed = HashSet::new();
            let mut denied = HashSet::new();
            for (name, is_deny) in cached {
                if let Some(action) = Action::from_str(&name) {
                    if is_deny {
                        denied.insert(action);
                    } else {
                        allowed.insert(action);
                    }
                }
            }
            return Ok(allowed.difference(&denied).copied().collect());
        }
    }

    let store = super::server_store::ServerPermissionStore::new(pool);
    resolver::resolve_actions(&store, ctx, resource).await
}

use resolver::PermissionStore as _;

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

/// Rebuild the per-user readable-events cache (and its incremental hash) from
/// scratch. Use after any change that may have flipped visibility for the user
/// (matrix update, group membership change, fresh wallet join).
///
/// Both the readable-events set and the `user_event_hashes` row are reset and
/// repopulated. `filter_readable_events` returns events in canonical
/// `events.id ASC` order so the rebuilt hash matches the value an incremental
/// `add_readable_event_impl` sequence would produce.
pub async fn rebuild_readable_events_cache(
    pool: &PgPool,
    ctx: &PermissionContext,
    all_events: &[domain::DomainEvent],
) -> Result<(), DbError> {
    // Wipe the cache + reset the hash. Both are derived state for this user.
    sqlx::query("DELETE FROM user_readable_events WHERE wallet_id = $1 AND user_id = $2")
        .bind(ctx.wallet_id)
        .bind(ctx.user_id)
        .execute(pool)
        .await?;
    crate::database::repository::hash::UserEventHash::reset(pool, ctx.wallet_id, ctx.user_id)
        .await?;

    if all_events.is_empty() {
        return Ok(());
    }

    // filter_readable_events returns canonical-ordered events.id ASC.
    // Per-row hash chaining (migration 033): each row's hash is
    // md5(prior_latest_hash || event_id::text), computed inside the
    // INSERT itself. The legacy user_event_hashes table is still reset
    // above for back-compat but no longer load-bearing for sync.
    let readable_ids = filter_readable_events(pool, ctx, all_events).await?;
    for event_id in readable_ids {
        sqlx::query(
            r#"
            INSERT INTO user_readable_events (wallet_id, user_id, event_id, hash)
            VALUES (
                $1, $2, $3,
                md5(
                    COALESCE(
                        (SELECT hash FROM user_readable_events
                         WHERE wallet_id = $1 AND user_id = $2
                         ORDER BY id DESC
                         LIMIT 1),
                        ''
                    ) || $3::text
                )
            )
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

/// Return the set of contact IDs the user has **permission** to read in this wallet.
///
/// This is a *permission* query (used by [`filter_readable_events`] to populate the
/// readable-events cache), not a *current-visibility* query: soft-deleted contacts
/// remain in the result so DELETE / UNDO events for a contact the user had access
/// to are still classified as readable. UI/display code should query
/// `contacts_projection` directly and filter `is_deleted = false`.
///
/// Implements the three-state (allowed / denied / unset) resolution: a contact is
/// returned iff at least one of the user's groups allows `contact:read` for it AND
/// no group denies it. Deny wins.
pub async fn get_permitted_contacts(
    pool: &PgPool,
    ctx: &PermissionContext,
) -> Result<HashSet<Uuid>, DbError> {
    permitted_contacts_for_action(pool, ctx, domain::Action::ContactRead).await
}

/// Return the set of contact IDs whose transactions the user has **permission** to read.
/// Same contract as [`get_permitted_contacts`], for the `transaction:read` action.
pub async fn get_permitted_transaction_contacts(
    pool: &PgPool,
    ctx: &PermissionContext,
) -> Result<HashSet<Uuid>, DbError> {
    permitted_contacts_for_action(pool, ctx, domain::Action::TransactionRead).await
}

/// Shared implementation: resolves the user's allow-minus-deny contact set for one action.
/// Delegates to `resolver::permitted_contacts_for_action`.
async fn permitted_contacts_for_action(
    pool: &PgPool,
    ctx: &PermissionContext,
    action: domain::Action,
) -> Result<HashSet<Uuid>, DbError> {
    let store = super::server_store::ServerPermissionStore::new(pool);
    resolver::permitted_contacts_for_action(&store, ctx, action).await
}

/// Filter events to return only those readable by user
/// Uses proven permission computation functions with single SQL filter query
pub async fn filter_readable_events(
    pool: &PgPool,
    ctx: &PermissionContext,
    events: &[domain::DomainEvent],
) -> Result<Vec<Uuid>, DbError> {
    if events.is_empty() {
        return Ok(Vec::new());
    }

    // Compute permission sets ONCE for this user. These answer "what does the user have
    // permission to read", regardless of current is_deleted state.
    let permitted_contacts = get_permitted_contacts(pool, ctx).await?;
    let permitted_transaction_contacts = get_permitted_transaction_contacts(pool, ctx).await?;

    let event_ids: Vec<Uuid> = events.iter().map(|e| e.id).collect();
    let permitted_contact_uuids: Vec<Uuid> = permitted_contacts.iter().copied().collect();
    let permitted_transaction_contact_uuids: Vec<Uuid> =
        permitted_transaction_contacts.iter().copied().collect();

    // No DISTINCT: each row in `events` is one event, and the OR conditions
    // are over mutually-exclusive aggregate_types, so a single event can only
    // match one clause. Ordering by `e.id ASC` (the BIGSERIAL insertion key)
    // gives canonical event order — required so that the incremental
    // user_event_hashes value matches what a fresh sequential sync would
    // produce. (DISTINCT here would forbid ORDER BY on a non-selected column.)
    let readable_ids: Vec<Uuid> = sqlx::query_scalar(
        r#"
        SELECT e.event_id
        FROM events e
        WHERE e.wallet_id = $1
          AND e.event_id = ANY($2::uuid[])
          AND (
            -- Contact events (CREATED / UPDATED / DELETED / UNDO).
            -- aggregate_id is the contact id for all four. Visible iff the user has
            -- permission to read this contact; soft-delete is intentionally ignored by
            -- get_permitted_contacts (it's a permission query, not a display query).
            (e.aggregate_type = 'contact' AND e.aggregate_id = ANY($3::uuid[]))

            -- Transaction CREATED / UPDATED: event_data carries contact_id, check directly.
            OR (e.aggregate_type = 'transaction' AND e.event_type IN ('CREATED', 'UPDATED')
                AND (e.event_data->>'contact_id')::uuid = ANY($4::uuid[]))

            -- Transaction DELETED / UNDO: event_data does NOT carry contact_id (only
            -- `comment` or `undone_event_id`). Resolve the contact link by looking up the
            -- CREATED event for the same transaction (same aggregate_id) and checking
            -- THAT contact_id against the user's permitted set.
            OR (e.aggregate_type = 'transaction' AND e.event_type IN ('DELETED', 'UNDO')
                AND EXISTS (
                    SELECT 1 FROM events orig
                    WHERE orig.wallet_id = e.wallet_id
                      AND orig.aggregate_type = 'transaction'
                      AND orig.aggregate_id = e.aggregate_id
                      AND orig.event_type = 'CREATED'
                      AND (orig.event_data->>'contact_id')::uuid = ANY($4::uuid[])
                ))

            -- Permission and wallet events: broadcast to all wallet users.
            OR (e.aggregate_type = 'permission' OR e.aggregate_type = 'wallet')
          )
        ORDER BY e.id ASC
        "#,
    )
    .bind(ctx.wallet_id)
    .bind(&event_ids)
    .bind(&permitted_contact_uuids)
    .bind(&permitted_transaction_contact_uuids)
    .fetch_all(pool)
    .await
    .map_err(|e| DbError::PermissionResolution(e.to_string()))?;

    Ok(readable_ids)
}
