use crate::database::error::DbError;
use crate::database::models::event::{Event, EventRow};
use crate::database::repository::Database;
use domain::DomainEvent;
use crate::permissions::PermissionModel;
use domain::PermissionContext;
use chrono::{DateTime, NaiveDateTime, Utc};
use serde_json::Value;
use sha2::{Digest, Sha256};
use sqlx::Row;
use uuid::Uuid;

// ============ EVENT DISCRIMINATOR (REPOSITORY INTERNAL) ============

/// Maps database storage format to serde tag discriminators.
/// This is repository internal logic - handles database-to-domain translation.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum EventDiscriminator {
    // Contact events
    ContactCreated,
    ContactUpdated,
    ContactDeleted,
    ContactUndone,
    // Transaction events
    TransactionCreated,
    TransactionUpdated,
    TransactionDeleted,
    TransactionUndone,
    // Permission events
    WalletUserAdded,
    WalletUserRoleChanged,
    WalletUserRemoved,
    UserGroupCreated,
    UserGroupUpdated,
    UserGroupDeleted,
    UserGroupMemberAdded,
    UserGroupMemberRemoved,
    ContactGroupCreated,
    ContactGroupUpdated,
    ContactGroupDeleted,
    ContactGroupMemberAdded,
    ContactGroupMemberRemoved,
    PermissionMatrixSet,
}

impl EventDiscriminator {
    /// Convert from database strings to strongly typed discriminator.
    fn from_database(aggregate_type: &str, event_type: &str) -> Result<Self, String> {
        match (aggregate_type, event_type) {
            ("contact", "CREATED") => Ok(Self::ContactCreated),
            ("contact", "UPDATED") => Ok(Self::ContactUpdated),
            ("contact", "DELETED") => Ok(Self::ContactDeleted),
            ("contact", "UNDO") => Ok(Self::ContactUndone),
            ("transaction", "CREATED") => Ok(Self::TransactionCreated),
            ("transaction", "UPDATED") => Ok(Self::TransactionUpdated),
            ("transaction", "DELETED") => Ok(Self::TransactionDeleted),
            ("transaction", "UNDO") => Ok(Self::TransactionUndone),
            ("permission", "WALLET_USER_ADDED") => Ok(Self::WalletUserAdded),
            ("permission", "WALLET_USER_ROLE_CHANGED") => Ok(Self::WalletUserRoleChanged),
            ("permission", "WALLET_USER_REMOVED") => Ok(Self::WalletUserRemoved),
            ("permission", "USER_GROUP_CREATED") => Ok(Self::UserGroupCreated),
            ("permission", "USER_GROUP_UPDATED") => Ok(Self::UserGroupUpdated),
            ("permission", "USER_GROUP_RENAMED") => Ok(Self::UserGroupUpdated),
            ("permission", "USER_GROUP_DELETED") => Ok(Self::UserGroupDeleted),
            ("permission", "USER_GROUP_MEMBER_ADDED") => Ok(Self::UserGroupMemberAdded),
            ("permission", "USER_GROUP_MEMBER_REMOVED") => Ok(Self::UserGroupMemberRemoved),
            ("permission", "CONTACT_GROUP_CREATED") => Ok(Self::ContactGroupCreated),
            ("permission", "CONTACT_GROUP_UPDATED") => Ok(Self::ContactGroupUpdated),
            ("permission", "CONTACT_GROUP_RENAMED") => Ok(Self::ContactGroupUpdated),
            ("permission", "CONTACT_GROUP_DELETED") => Ok(Self::ContactGroupDeleted),
            ("permission", "CONTACT_GROUP_MEMBER_ADDED") => Ok(Self::ContactGroupMemberAdded),
            ("permission", "CONTACT_GROUP_MEMBER_REMOVED") => Ok(Self::ContactGroupMemberRemoved),
            ("permission", "PERMISSION_MATRIX_SET") => Ok(Self::PermissionMatrixSet),
            (agg, evt) => Err(format!("Unknown event type: {} / {}", agg, evt)),
        }
    }

    /// Convert to serde tag discriminator string (e.g., "contact_created").
    fn as_str(&self) -> &'static str {
        match self {
            Self::ContactCreated => "contact_created",
            Self::ContactUpdated => "contact_updated",
            Self::ContactDeleted => "contact_deleted",
            Self::ContactUndone => "contact_undone",
            Self::TransactionCreated => "transaction_created",
            Self::TransactionUpdated => "transaction_updated",
            Self::TransactionDeleted => "transaction_deleted",
            Self::TransactionUndone => "transaction_undone",
            Self::WalletUserAdded => "wallet_user_added",
            Self::WalletUserRoleChanged => "wallet_user_role_changed",
            Self::WalletUserRemoved => "wallet_user_removed",
            Self::UserGroupCreated => "user_group_created",
            Self::UserGroupUpdated => "user_group_updated",
            Self::UserGroupDeleted => "user_group_deleted",
            Self::UserGroupMemberAdded => "user_group_member_added",
            Self::UserGroupMemberRemoved => "user_group_member_removed",
            Self::ContactGroupCreated => "contact_group_created",
            Self::ContactGroupUpdated => "contact_group_updated",
            Self::ContactGroupDeleted => "contact_group_deleted",
            Self::ContactGroupMemberAdded => "contact_group_member_added",
            Self::ContactGroupMemberRemoved => "contact_group_member_removed",
            Self::PermissionMatrixSet => "permission_matrix_set",
        }
    }
}

// Helper struct for mapping database columns to EventRow fields
#[derive(Debug, Clone, sqlx::FromRow)]
struct EventRowDb {
    id: i64,
    event_id: Uuid,
    aggregate_id: Uuid,
    aggregate_type: String,
    event_type: String,
    #[sqlx(rename = "event_data")]
    data: Value,
    wallet_id: Uuid,
    user_id: Uuid,
    created_at: NaiveDateTime,
    #[sqlx(rename = "event_version")]
    version: i32,
}

impl From<EventRowDb> for EventRow {
    fn from(db: EventRowDb) -> Self {
        EventRow {
            id: db.id,
            event_id: db.event_id,
            aggregate_id: db.aggregate_id,
            aggregate_type: db.aggregate_type,
            event_type: db.event_type,
            data: db.data,
            wallet_id: db.wallet_id,
            user_id: db.user_id,
            created_at: db.created_at,
            version: db.version,
        }
    }
}

impl Database {
    /// Convert database Event to domain DomainEvent.
    /// This is internal conversion logic - domain layer should not depend on storage types.
    fn event_to_domain(event: &Event) -> Result<DomainEvent, DbError> {
        // Use strongly-typed discriminator to ensure we handle all event types
        let discriminator =
            EventDiscriminator::from_database(&event.aggregate_type, &event.event_type)
                .map_err(DbError::SerializationError)?;

        // Reconstruct EventData by adding the "type" field back (it was removed during storage)
        let mut event_data_with_type = event.data.clone();
        if let Some(obj) = event_data_with_type.as_object_mut() {
            obj.insert(
                "type".to_string(),
                serde_json::Value::String(discriminator.as_str().to_string()),
            );
        }

        let event_data =
            serde_json::from_value::<domain::EventData>(event_data_with_type)
                .map_err(|e| {
                    DbError::SerializationError(format!("Failed to deserialize event data: {}", e))
                })?;

        Ok(DomainEvent {
            id: event.id,
            aggregate_id: event.aggregate_id,
            wallet_id: event.wallet_id,
            user_id: event.user_id,
            created_at: event.created_at,
            version: event.version,
            event_data,
        })
    }

    pub async fn get_wallet_events_impl(
        &self,
        wallet_id: Uuid,
        since: Option<DateTime<Utc>>,
    ) -> Result<Vec<DomainEvent>, DbError> {
        let rows = match since {
            Some(since_timestamp) => {
                sqlx::query_as::<_, EventRowDb>(
                    r#"
                    SELECT id, event_id, aggregate_type, aggregate_id, event_type, event_data,
                           wallet_id, user_id, created_at, event_version
                    FROM events
                    WHERE wallet_id = $1 AND created_at > $2
                    ORDER BY created_at ASC
                    "#,
                )
                .bind(wallet_id)
                .bind(since_timestamp)
                .fetch_all(&self.pool)
                .await?
            }
            None => {
                sqlx::query_as::<_, EventRowDb>(
                    r#"
                    SELECT id, event_id, aggregate_type, aggregate_id, event_type, event_data,
                           wallet_id, user_id, created_at, event_version
                    FROM events
                    WHERE wallet_id = $1
                    ORDER BY created_at ASC
                    "#,
                )
                .bind(wallet_id)
                .fetch_all(&self.pool)
                .await?
            }
        };

        let mut events = Vec::new();
        for db in rows {
            let event_row: EventRow = db.into();
            let event: Event = event_row.into();
            let domain_event = Self::event_to_domain(&event)?;
            events.push(domain_event);
        }
        Ok(events)
    }

    pub async fn get_event_by_id_impl(
        &self,
        event_id: Uuid,
    ) -> Result<Option<DomainEvent>, DbError> {
        let row = sqlx::query_as::<_, EventRowDb>(
            r#"
            SELECT id, event_id, aggregate_type, aggregate_id, event_type, event_data,
                   wallet_id, user_id, created_at, event_version
            FROM events
            WHERE event_id = $1
            "#,
        )
        .bind(event_id)
        .fetch_optional(&self.pool)
        .await?;

        match row {
            None => Ok(None),
            Some(db) => {
                let event_row: EventRow = db.into();
                let event: Event = event_row.into();
                let domain_event = Self::event_to_domain(&event)?;
                Ok(Some(domain_event))
            }
        }
    }

    pub async fn get_readable_events_impl(
        &self,
        wallet_id: Uuid,
        user_id: Uuid,
        since: Option<DateTime<Utc>>,
    ) -> Result<Vec<DomainEvent>, DbError> {
        let rows = match since {
            Some(since_timestamp) => {
                sqlx::query_as::<_, EventRowDb>(
                    r#"
                    SELECT e.id, e.event_id, e.aggregate_type, e.aggregate_id, e.event_type,
                           e.event_data, e.wallet_id, e.user_id, e.created_at, e.event_version
                    FROM events e
                    INNER JOIN user_readable_events ure ON e.event_id = ure.event_id
                    WHERE e.wallet_id = $1 AND ure.user_id = $2 AND e.created_at > $3
                    ORDER BY e.created_at ASC
                    "#,
                )
                .bind(wallet_id)
                .bind(user_id)
                .bind(since_timestamp)
                .fetch_all(&self.pool)
                .await?
            }
            None => {
                sqlx::query_as::<_, EventRowDb>(
                    r#"
                    SELECT e.id, e.event_id, e.aggregate_type, e.aggregate_id, e.event_type,
                           e.event_data, e.wallet_id, e.user_id, e.created_at, e.event_version
                    FROM events e
                    INNER JOIN user_readable_events ure ON e.event_id = ure.event_id
                    WHERE e.wallet_id = $1 AND ure.user_id = $2
                    ORDER BY e.created_at ASC
                    "#,
                )
                .bind(wallet_id)
                .bind(user_id)
                .fetch_all(&self.pool)
                .await?
            }
        };

        let mut events = Vec::new();
        for db in rows {
            let event_row: EventRow = db.into();
            let event: Event = event_row.into();
            let domain_event = Self::event_to_domain(&event)?;
            events.push(domain_event);
        }

        Ok(events)
    }

    /// Return readable events whose `user_readable_events.id` is strictly
    /// greater than `start_id`, ordered by that id ASC. Used by the pull
    /// endpoint after resolving the client's last_hash to its row id.
    /// Pass start_id = -1 for "return everything readable".
    ///
    /// Runs inside a caller-supplied transaction so the lookup of the
    /// client's hash, the events query, and the latest_hash query all
    /// observe the same REPEATABLE READ snapshot.
    pub async fn get_readable_events_after_in_tx(
        &self,
        tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
        wallet_id: Uuid,
        user_id: Uuid,
        start_id: i64,
    ) -> Result<Vec<DomainEvent>, DbError> {
        let rows = sqlx::query_as::<_, EventRowDb>(
            r#"
            SELECT e.id, e.event_id, e.aggregate_type, e.aggregate_id, e.event_type,
                   e.event_data, e.wallet_id, e.user_id, e.created_at, e.event_version
            FROM events e
            INNER JOIN user_readable_events ure
                ON e.event_id = ure.event_id AND ure.wallet_id = e.wallet_id
            WHERE e.wallet_id = $1 AND ure.user_id = $2 AND ure.id > $3
            ORDER BY ure.id ASC
            "#,
        )
        .bind(wallet_id)
        .bind(user_id)
        .bind(start_id)
        .fetch_all(&mut **tx)
        .await?;
        let mut events = Vec::with_capacity(rows.len());
        for db in rows {
            let event_row: EventRow = db.into();
            let event: Event = event_row.into();
            let domain_event = Self::event_to_domain(&event)?;
            events.push(domain_event);
        }
        Ok(events)
    }

    /// Insert an event. Dedup on `(wallet_id, event_id)` — a duplicate is silently
    /// dropped and returns 0; a new insert returns the BIGSERIAL row id.
    /// Callers use `result > 0` to distinguish new vs duplicate without exception flow.
    pub async fn insert_event_impl(
        &self,
        event_id: Uuid,
        aggregate_id: Uuid,
        aggregate_type: String,
        event_type: String,
        data: Value,
        wallet_id: Uuid,
        user_id: Uuid,
        version: i32,
    ) -> Result<i64, DbError> {
        let result = sqlx::query_scalar::<_, i64>(
            r#"
            INSERT INTO events (event_id, aggregate_id, aggregate_type, event_type, event_data, wallet_id, user_id, event_version, created_at)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, NOW())
            ON CONFLICT (wallet_id, event_id) DO NOTHING
            RETURNING id
            "#
        )
        .bind(event_id)
        .bind(aggregate_id)
        .bind(&aggregate_type)
        .bind(&event_type)
        .bind(&data)
        .bind(wallet_id)
        .bind(user_id)
        .bind(version)
        .fetch_optional(&self.pool)
        .await?;

        Ok(result.unwrap_or(0))
    }

    /// Populate readable events cache after synced events are inserted.
    /// This is called by the sync handler after inserting a batch of client events.
    /// Database responsibility: make events visible to users based on their permissions.
    pub async fn populate_events_cache_after_sync(
        &self,
        wallet_id: Uuid,
        events: &[DomainEvent],
    ) -> Result<(), DbError> {
        self.populate_event_cache(wallet_id, events).await
    }

    /// Populate readable_events cache for inserted events.
    /// Automatically called after events are inserted to make them visible to users based on permissions.
    /// TODO: Optimize by calling this automatically from insert_event_impl batch processing
    /// instead of requiring explicit calls from handlers.
    async fn populate_event_cache(
        &self,
        wallet_id: Uuid,
        events: &[DomainEvent],
    ) -> Result<(), DbError> {
        if events.is_empty() {
            return Ok(());
        }

        // Get all wallet users
        let wallet_users = self.get_wallet_users_impl(wallet_id).await?;
        let perm_model = PermissionModel::new(self.pool.clone());

        // For each event, check which users can read it and populate cache
        for event in events {
            for (wallet_user_id, role_str) in &wallet_users {
                let user_role = domain::WalletRole::from_str(role_str)
                    .unwrap_or(domain::WalletRole::Member);
                let user_perm_ctx = PermissionContext::new(wallet_id, *wallet_user_id, user_role);

                // Check if user can read this event
                if let Ok(readable_ids) = perm_model
                    .get_readable_event_ids(&user_perm_ctx, std::slice::from_ref(event))
                    .await
                {
                    if !readable_ids.is_empty() {
                        // Add to user's readable events
                        let _ = self
                            .add_readable_event_impl(wallet_id, *wallet_user_id, event.id)
                            .await;
                    }
                }
            }
        }

        Ok(())
    }

    pub async fn delete_event_impl(&self, event_id: Uuid) -> Result<bool, DbError> {
        let result = sqlx::query("DELETE FROM events WHERE event_id = $1")
            .bind(event_id)
            .execute(&self.pool)
            .await?;

        Ok(result.rows_affected() > 0)
    }

    pub async fn get_hash_for_sync_impl(&self, wallet_id: Uuid) -> Result<(String, i64), DbError> {
        let rows = sqlx::query(
            r#"
            SELECT event_id, aggregate_type, aggregate_id, event_type, event_data, created_at
            FROM events
            WHERE wallet_id = $1
            ORDER BY created_at ASC
            "#,
        )
        .bind(wallet_id)
        .fetch_all(&self.pool)
        .await?;

        let mut hasher = Sha256::new();
        for row in &rows {
            let event_id: Uuid = row.get("event_id");
            let aggregate_type: String = row.get("aggregate_type");
            let aggregate_id: Uuid = row.get("aggregate_id");
            let event_type: String = row.get("event_type");
            let data: Value = row.get("event_data");

            hasher.update(event_id.to_string().as_bytes());
            hasher.update(aggregate_type.as_bytes());
            hasher.update(aggregate_id.to_string().as_bytes());
            hasher.update(event_type.as_bytes());
            hasher.update(data.to_string().as_bytes());
        }

        let hash = format!("{:x}", hasher.finalize());
        Ok((hash, rows.len() as i64))
    }

    pub async fn get_latest_event_id_impl(&self) -> Result<Option<i64>, DbError> {
        let id = sqlx::query_scalar::<_, Option<i64>>("SELECT MAX(id) FROM events")
            .fetch_one(&self.pool)
            .await?;

        Ok(id)
    }

    /// Type-driven version: assigns contact to all_contacts + given group_ids (full sync).
    /// Replaces any existing group memberships for this contact within this wallet.

    /// Type-driven event batch processor.
    ///
    /// Parses each row's raw event_data into the strongly-typed [`EventData`] enum,
    /// then dispatches to type-specific handlers based on the aggregate. The compiler
    /// enforces exhaustive matching, so adding a new event variant fails to compile
    /// until a handler is added.
    pub async fn apply_event_batch(
        &self,
        events: &[&sqlx::postgres::PgRow],
        user_id: Uuid,
        wallet_id: Uuid,
        undone_event_ids: &mut std::collections::HashSet<Uuid>,
    ) -> Result<(), sqlx::Error> {
        tracing::info!("apply_event_batch: processing {} events", events.len());

        // First pass: collect IDs of events undone by UNDO events in this batch.
        // The (aggregate_type, event_type) strings come from the SQL row — this
        // is the wire→type boundary, parsed once here so the rest of the loop
        // branches on typed values.
        if undone_event_ids.is_empty() {
            for row in events.iter() {
                let event_type_str: String = row.get("event_type");
                let event_type = domain::EventType::from_str(&event_type_str);
                if event_type == Some(domain::EventType::Undo) {
                    let event_data: Value = row.get("event_data");
                    if let Some(undone_id_str) =
                        event_data.get("undone_event_id").and_then(|v| v.as_str())
                    {
                        if let Ok(undone_id) = Uuid::parse_str(undone_id_str) {
                            undone_event_ids.insert(undone_id);
                        }
                    }
                }
            }
        }

        // Second pass: parse and dispatch each event via typed handlers
        for row in events {
            let event_id: Uuid = row.get("event_id");
            let aggregate_type_str: String = row.get("aggregate_type");
            let aggregate_id: Uuid = row.get("aggregate_id");
            let event_type_str: String = row.get("event_type");
            let raw_data: Value = row.get("event_data");
            let created_at: NaiveDateTime = row.get("created_at");
            let event_db_id: i64 = row.get("id");
            let event_type = domain::EventType::from_str(&event_type_str);

            tracing::info!(
                "apply_event_batch processing: type={}/{}",
                aggregate_type_str,
                event_type_str
            );

            // Skip raw UNDO records - their effect is already captured in undone_event_ids
            if event_type == Some(domain::EventType::Undo) {
                continue;
            }

            // Skip events that were undone by an UNDO event
            if undone_event_ids.contains(&event_id) {
                continue;
            }

            // Parse raw event_data into typed EventData enum
            let event_data = match Self::parse_event_data_typed(
                &aggregate_type_str,
                &event_type_str,
                raw_data.clone(),
            ) {
                Ok(d) => d,
                Err(e) => {
                    tracing::warn!(
                        "Skipping event {}/{} - failed type-driven parse: {}",
                        aggregate_type_str,
                        event_type_str,
                        e
                    );
                    continue;
                }
            };

            // Type-driven dispatch by aggregate kind
            match event_data.aggregate_type() {
                domain::AggregateType::Contact => {
                    // Step 3a: contact events flow through the shared applier
                    // crate (Projection trait). The translation rules
                    // ("ContactCreated also adds to all_contacts", "ContactDeleted
                    // cascades to transactions", etc.) live in applier::apply;
                    // the SQL lives in ServerProjection.
                    let domain_event = domain::DomainEvent {
                        id: event_id,
                        aggregate_id,
                        wallet_id,
                        user_id,
                        created_at: chrono::DateTime::<chrono::Utc>::from_naive_utc_and_offset(
                            created_at, chrono::Utc,
                        ),
                        version: 1,
                        event_data: event_data.clone(),
                    };
                    let mut proj = super::server_projection::ServerProjection::new(
                        &self.pool,
                        event_db_id,
                        created_at,
                    );
                    applier::apply(&mut proj, &domain_event).await?;
                }
                domain::AggregateType::Transaction => {
                    // Step 3b: transactions through applier::apply, same as
                    // contacts above. Server-rule "skip if contact deleted"
                    // lives in applier::apply (uses Projection::contact_is_active).
                    let domain_event = domain::DomainEvent {
                        id: event_id,
                        aggregate_id,
                        wallet_id,
                        user_id,
                        created_at: chrono::DateTime::<chrono::Utc>::from_naive_utc_and_offset(
                            created_at, chrono::Utc,
                        ),
                        version: 1,
                        event_data: event_data.clone(),
                    };
                    let mut proj = super::server_projection::ServerProjection::new(
                        &self.pool,
                        event_db_id,
                        created_at,
                    );
                    applier::apply(&mut proj, &domain_event).await?;
                }
                domain::AggregateType::Permission => {
                    // Step 3c: permission events through applier::apply.
                    // PermissionMatrixSet, WalletDeleted, and OwnershipTransferred
                    // remain intentional no-ops in applier::apply (matrix
                    // writes flow through put_permission_matrix handler;
                    // wallet-lifecycle events have no projection rows today).
                    let domain_event = domain::DomainEvent {
                        id: event_id,
                        aggregate_id,
                        wallet_id,
                        user_id,
                        created_at: chrono::DateTime::<chrono::Utc>::from_naive_utc_and_offset(
                            created_at, chrono::Utc,
                        ),
                        version: 1,
                        event_data: event_data.clone(),
                    };
                    let mut proj = super::server_projection::ServerProjection::new(
                        &self.pool,
                        event_db_id,
                        created_at,
                    );
                    applier::apply(&mut proj, &domain_event).await?;
                }
            }
        }

        Ok(())
    }

    /// Parse raw database event_data into typed EventData enum.
    /// Rebuilds the `type` tag from (aggregate_type, event_type) since storage strips it.
    ///
    /// Permission events have inconsistent storage: events written via the sync handler
    /// path are wrapped as `{"data": {...}}`, while those written via
    /// insert_permission_event_and_apply store the payload directly. Normalize both
    /// shapes into the typed variant's `data` field.
    fn parse_event_data_typed(
        aggregate_type_str: &str,
        event_type_str: &str,
        raw_data: Value,
    ) -> Result<domain::EventData, String> {
        let discriminator =
            EventDiscriminator::from_database(aggregate_type_str, event_type_str)?;
        let aggregate_type = domain::AggregateType::from_str(aggregate_type_str)
            .ok_or_else(|| format!("Unknown aggregate type: {}", aggregate_type_str))?;

        let mut data_with_type = if aggregate_type == domain::AggregateType::Permission
            && raw_data.get("data").is_none()
        {
            serde_json::json!({ "data": raw_data })
        } else {
            raw_data
        };

        if let Some(obj) = data_with_type.as_object_mut() {
            obj.insert(
                "type".to_string(),
                Value::String(discriminator.as_str().to_string()),
            );
        }

        serde_json::from_value::<domain::EventData>(data_with_type)
            .map_err(|e| format!("deserialization failed: {}", e))
    }

    /// Apply a contact-aggregate event to the contacts_projection table.
    /// Exhaustive on contact EventData variants; non-contact variants are ignored.

    /// Apply a transaction-aggregate event to the transactions_projection table.
    /// Exhaustive on transaction EventData variants.

    /// Apply a permission-aggregate event to operational permission tables.
    /// Compiler enforces exhaustive matching across all 14+ permission variants.
    /// Apply a single event by fetching it from DB and using the batch processor
    /// This consolidates event application logic into one place
    pub async fn apply_event_to_projections(
        &self,
        event_uuid: Uuid,
        user_id: Uuid,
        wallet_id: Uuid,
    ) -> Result<(), sqlx::Error> {
        // Fetch the event from database
        let event_row = sqlx::query(
            r#"
            SELECT event_id, aggregate_type, aggregate_id, event_type, event_data, created_at, id
            FROM events
            WHERE event_id = $1 AND wallet_id = $2
            "#,
        )
        .bind(event_uuid)
        .bind(wallet_id)
        .fetch_optional(&self.pool)
        .await?;

        if let Some(row) = event_row {
            let row_ref: &sqlx::postgres::PgRow = &row;
            self.apply_event_batch(
                &[row_ref],
                user_id,
                wallet_id,
                &mut std::collections::HashSet::new(),
            )
            .await?;
        }

        Ok(())
    }

    pub async fn restore_projections_from_snapshot(
        &self,
        snapshot: &crate::services::snapshots::ProjectionSnapshot,
        user_id: uuid::Uuid,
        wallet_id: uuid::Uuid,
        undone_event_ids: &std::collections::HashSet<uuid::Uuid>,
    ) -> Result<(), sqlx::Error> {
        sqlx::query("DELETE FROM transactions_projection WHERE wallet_id = $1")
            .bind(wallet_id)
            .execute(&self.pool)
            .await?;

        sqlx::query("DELETE FROM contacts_projection WHERE wallet_id = $1")
            .bind(wallet_id)
            .execute(&self.pool)
            .await?;

        let mut undone_transaction_ids = std::collections::HashSet::new();
        let mut undone_contact_ids = std::collections::HashSet::new();

        if !undone_event_ids.is_empty() {
            let undone_event_ids_vec: Vec<uuid::Uuid> = undone_event_ids.iter().copied().collect();
            let undone_aggregates = sqlx::query(
                r#"
                SELECT aggregate_type, aggregate_id
                FROM events
                WHERE event_id = ANY($1) AND event_type = 'CREATED'
                "#,
            )
            .bind(&undone_event_ids_vec[..])
            .fetch_all(&self.pool)
            .await?;

            for row in undone_aggregates {
                let aggregate_type: String = row.get("aggregate_type");
                let aggregate_id: uuid::Uuid = row.get("aggregate_id");
                match aggregate_type.as_str() {
                    "transaction" => {
                        undone_transaction_ids.insert(aggregate_id);
                    }
                    "contact" => {
                        undone_contact_ids.insert(aggregate_id);
                    }
                    _ => {}
                }
            }
        }

        if let Some(contacts_array) = snapshot.contacts_snapshot.as_array() {
            for contact_json in contacts_array {
                let id_str = contact_json
                    .get("id")
                    .and_then(|v| v.as_str())
                    .unwrap_or("");
                if let Ok(contact_id) = uuid::Uuid::parse_str(id_str) {
                    if undone_contact_ids.contains(&contact_id) {
                        continue;
                    }
                    let name = contact_json
                        .get("name")
                        .and_then(|v| v.as_str())
                        .unwrap_or("");
                    let username = contact_json.get("username").and_then(|v| v.as_str());
                    let phone = contact_json.get("phone").and_then(|v| v.as_str());
                    let email = contact_json.get("email").and_then(|v| v.as_str());
                    let notes = contact_json.get("notes").and_then(|v| v.as_str());
                    let created_at_str = contact_json
                        .get("created_at")
                        .and_then(|v| v.as_str())
                        .unwrap_or("");
                    let updated_at_str = contact_json
                        .get("updated_at")
                        .and_then(|v| v.as_str())
                        .unwrap_or("");

                    let created_at = chrono::NaiveDateTime::parse_from_str(
                        created_at_str,
                        "%Y-%m-%d %H:%M:%S%.f",
                    )
                    .unwrap_or_else(|_| chrono::Utc::now().naive_utc());
                    let updated_at = chrono::NaiveDateTime::parse_from_str(
                        updated_at_str,
                        "%Y-%m-%d %H:%M:%S%.f",
                    )
                    .unwrap_or(created_at);

                    sqlx::query(
                        r#"
                        INSERT INTO contacts_projection
                        (id, user_id, wallet_id, name, username, phone, email, notes, is_deleted, created_at, updated_at, last_event_id)
                        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, false, $9, $10, 0)
                        "#
                    )
                    .bind(contact_id)
                    .bind(user_id)
                    .bind(wallet_id)
                    .bind(name)
                    .bind(username)
                    .bind(phone)
                    .bind(email)
                    .bind(notes)
                    .bind(created_at)
                    .bind(updated_at)
                    .execute(&self.pool)
                    .await?;
                }
            }
        }

        if let Some(transactions_array) = snapshot.transactions_snapshot.as_array() {
            for transaction_json in transactions_array {
                let id_str = transaction_json
                    .get("id")
                    .and_then(|v| v.as_str())
                    .unwrap_or("");
                if let Ok(transaction_id) = uuid::Uuid::parse_str(id_str) {
                    if undone_transaction_ids.contains(&transaction_id) {
                        continue;
                    }

                    let contact_id_str = transaction_json
                        .get("contact_id")
                        .and_then(|v| v.as_str())
                        .unwrap_or("");
                    if let Ok(contact_id) = uuid::Uuid::parse_str(contact_id_str) {
                        // Parse to typed values; defaults match the live event
                        // applier defaults (Money / IQD) — note that the prior
                        // string-literal defaults here were inconsistent
                        // ("USD" / "lent"), masked by Rust because everything
                        // was &str. Typed enums make the defaults explicit.
                        let tx_type = transaction_json
                            .get("type")
                            .and_then(|v| v.as_str())
                            .and_then(domain::TransactionType::from_str)
                            .unwrap_or(domain::TransactionType::Money);
                        let direction = transaction_json
                            .get("direction")
                            .and_then(|v| v.as_str())
                            .and_then(domain::TransactionDirection::from_str)
                            .unwrap_or(domain::TransactionDirection::Owed);
                        let amount = transaction_json
                            .get("amount")
                            .and_then(|v| v.as_i64())
                            .unwrap_or(0);
                        let currency = transaction_json
                            .get("currency")
                            .and_then(|v| v.as_str())
                            .and_then(domain::Currency::from_str)
                            .unwrap_or(domain::Currency::IQD);
                        let description =
                            transaction_json.get("description").and_then(|v| v.as_str());
                        let transaction_date_str = transaction_json
                            .get("transaction_date")
                            .and_then(|v| v.as_str())
                            .unwrap_or("");
                        let due_date_str =
                            transaction_json.get("due_date").and_then(|v| v.as_str());
                        let created_at_str = transaction_json
                            .get("created_at")
                            .and_then(|v| v.as_str())
                            .unwrap_or("");
                        let updated_at_str = transaction_json
                            .get("updated_at")
                            .and_then(|v| v.as_str())
                            .unwrap_or("");

                        let transaction_date = if !transaction_date_str.is_empty() {
                            chrono::NaiveDate::parse_from_str(transaction_date_str, "%Y-%m-%d").ok()
                        } else {
                            None
                        };

                        let due_date = due_date_str
                            .and_then(|d| chrono::NaiveDate::parse_from_str(d, "%Y-%m-%d").ok());

                        let created_at = chrono::NaiveDateTime::parse_from_str(
                            created_at_str,
                            "%Y-%m-%d %H:%M:%S%.f",
                        )
                        .unwrap_or_else(|_| chrono::Utc::now().naive_utc());
                        let updated_at = chrono::NaiveDateTime::parse_from_str(
                            updated_at_str,
                            "%Y-%m-%d %H:%M:%S%.f",
                        )
                        .unwrap_or(created_at);

                        if let Some(txn_date) = transaction_date {
                            sqlx::query(
                                r#"
                                INSERT INTO transactions_projection
                                (id, user_id, wallet_id, contact_id, type, direction, amount, currency, description, transaction_date, due_date, is_deleted, created_at, updated_at, last_event_id)
                                VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, false, $12, $13, 0)
                                "#
                            )
                            .bind(transaction_id)
                            .bind(user_id)
                            .bind(wallet_id)
                            .bind(contact_id)
                            .bind(tx_type.as_str())
                            .bind(direction.as_str())
                            .bind(amount)
                            .bind(currency.as_str())
                            .bind(description)
                            .bind(txn_date)
                            .bind(due_date)
                            .bind(created_at)
                            .bind(updated_at)
                            .execute(&self.pool)
                            .await?;
                        }
                    }
                }
            }
        }

        Ok(())
    }

    pub async fn get_transaction_contact_map(
        &self,
        wallet_id: Uuid,
        transaction_ids: &[Uuid],
    ) -> Result<std::collections::HashMap<Uuid, Uuid>, sqlx::Error> {
        if transaction_ids.is_empty() {
            return Ok(std::collections::HashMap::new());
        }
        let rows = sqlx::query(
            "SELECT id, contact_id FROM transactions_projection WHERE wallet_id = $1 AND id = ANY($2)",
        )
        .bind(wallet_id)
        .bind(transaction_ids)
        .fetch_all(&self.pool)
        .await?;
        Ok(rows
            .iter()
            .map(|r| (r.get::<Uuid, _>("id"), r.get::<Uuid, _>("contact_id")))
            .collect())
    }

    pub async fn calculate_total_debt(&self, wallet_id: Uuid) -> i64 {
        let result = sqlx::query_scalar::<_, i64>(
            r#"
            SELECT COALESCE(SUM(
                CASE
                    WHEN t.direction = 'lent' THEN t.amount
                    WHEN t.direction = 'owed' THEN -t.amount
                    ELSE 0
                END
            )::BIGINT, 0)
            FROM contacts_projection c
            LEFT JOIN transactions_projection t ON t.contact_id = c.id AND t.is_deleted = false AND t.wallet_id = $1
            WHERE c.is_deleted = false AND c.wallet_id = $1
            "#
        )
        .bind(wallet_id)
        .fetch_one(&self.pool)
        .await;

        match result {
            Ok(total) => total,
            Err(e) => {
                tracing::error!(
                    "calculate_total_debt failed for wallet {}: {:?}",
                    wallet_id,
                    e
                );
                0
            }
        }
    }

    pub async fn get_event_count(&self) -> i64 {
        sqlx::query_scalar("SELECT COUNT(*) FROM events")
            .fetch_one(&self.pool)
            .await
            .unwrap_or(0)
    }

    pub async fn get_event_count_for_wallet(&self, wallet_id: Uuid) -> i64 {
        sqlx::query_scalar("SELECT COUNT(*) FROM events WHERE wallet_id = $1")
            .bind(wallet_id)
            .fetch_one(&self.pool)
            .await
            .unwrap_or(0)
    }

    pub async fn get_event_db_id_by_uuid(
        &self,
        event_id: Uuid,
    ) -> Result<Option<i64>, sqlx::Error> {
        sqlx::query_scalar::<_, i64>("SELECT id FROM events WHERE event_id = $1")
            .bind(event_id)
            .fetch_optional(&self.pool)
            .await
    }

    /// Check if a user can read a specific event based on permission filtering
    /// Returns true if user is allowed to read this event
    pub fn event_read_allowed(
        contact_ids_allowed: &Option<std::collections::HashSet<Uuid>>,
        transaction_contact_ids_allowed: &Option<std::collections::HashSet<Uuid>>,
        aggregate_type: domain::AggregateType,
        aggregate_id: Uuid,
        event_data: &serde_json::Value,
        transaction_contact_map: &std::collections::HashMap<Uuid, Uuid>,
    ) -> bool {
        match aggregate_type {
            domain::AggregateType::Permission => true,
            domain::AggregateType::Contact => match contact_ids_allowed {
                None => true,
                Some(set) => set.contains(&aggregate_id),
            },
            domain::AggregateType::Transaction => {
                let contact_id = event_data
                    .get("contact_id")
                    .and_then(|v| v.as_str())
                    .and_then(|s| Uuid::parse_str(s).ok())
                    .or_else(|| transaction_contact_map.get(&aggregate_id).copied());
                let Some(contact_id) = contact_id else {
                    return false;
                };
                match transaction_contact_ids_allowed {
                    None => true,
                    Some(set) => set.contains(&contact_id),
                }
            }
        }
    }
}
