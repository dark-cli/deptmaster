use crate::database::error::DbError;
use crate::database::models::event::{Event, EventRow};
use crate::database::repository::Database;
use crate::domain::events::DomainEvent;
use crate::permissions::{PermissionContext, PermissionModel};
use chrono::{DateTime, NaiveDateTime, Utc};
use serde_json::Value;
use sha2::{Digest, Sha256};
use sqlx::Row;
use std::str::FromStr;
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
            ("permission", "USER_GROUP_DELETED") => Ok(Self::UserGroupDeleted),
            ("permission", "USER_GROUP_MEMBER_ADDED") => Ok(Self::UserGroupMemberAdded),
            ("permission", "USER_GROUP_MEMBER_REMOVED") => Ok(Self::UserGroupMemberRemoved),
            ("permission", "CONTACT_GROUP_CREATED") => Ok(Self::ContactGroupCreated),
            ("permission", "CONTACT_GROUP_UPDATED") => Ok(Self::ContactGroupUpdated),
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
    idempotency_key: Option<String>,
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
            idempotency_key: db.idempotency_key,
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
                .map_err(|e| DbError::SerializationError(e))?;

        // Reconstruct EventData by adding the "type" field back (it was removed during storage)
        let mut event_data_with_type = event.data.clone();
        if let Some(obj) = event_data_with_type.as_object_mut() {
            obj.insert(
                "type".to_string(),
                serde_json::Value::String(discriminator.as_str().to_string()),
            );
        }

        let event_data =
            serde_json::from_value::<crate::domain::events::EventData>(event_data_with_type)
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
            idempotency_key: event
                .idempotency_key
                .clone()
                .unwrap_or_else(|| Uuid::new_v4().to_string()),
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
                           wallet_id, user_id, created_at, event_version, idempotency_key
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
                           wallet_id, user_id, created_at, event_version, idempotency_key
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
                   wallet_id, user_id, created_at, event_version, idempotency_key
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

    pub async fn get_existing_event_ids_impl(
        &self,
        event_ids: &[Uuid],
    ) -> Result<Vec<Uuid>, DbError> {
        if event_ids.is_empty() {
            return Ok(Vec::new());
        }

        let existing: Vec<Uuid> = sqlx::query_scalar(
            "SELECT event_id FROM events WHERE event_id = ANY($1)",
        )
        .bind(event_ids)
        .fetch_all(&self.pool)
        .await?;

        Ok(existing)
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
                           e.event_data, e.wallet_id, e.user_id, e.created_at, e.event_version, e.idempotency_key
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
                           e.event_data, e.wallet_id, e.user_id, e.created_at, e.event_version, e.idempotency_key
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
        idempotency_key: Option<String>,
    ) -> Result<i64, DbError> {
        let result = sqlx::query_scalar::<_, i64>(
            r#"
            INSERT INTO events (event_id, aggregate_id, aggregate_type, event_type, event_data, wallet_id, user_id, event_version, idempotency_key, created_at)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, NOW())
            ON CONFLICT (event_id) DO NOTHING
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
        .bind(&idempotency_key)
        .fetch_optional(&self.pool)
        .await?;

        Ok(result.unwrap_or(0))
    }

    /// Populate readable_events cache for inserted events.
    /// Automatically called after events are inserted to make them visible to users based on permissions.
    pub async fn populate_event_cache(
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
                let user_role = crate::permissions::WalletRole::from_str(role_str)
                    .unwrap_or(crate::permissions::WalletRole::Member);
                let user_perm_ctx = PermissionContext::new(wallet_id, *wallet_user_id, user_role);

                // Check if user can read this event
                if let Ok(readable_ids) = perm_model
                    .get_readable_event_ids(&user_perm_ctx, &[event.clone()])
                    .await
                {
                    if !readable_ids.is_empty() {
                        // Add to user's readable events
                        let _ = self.add_readable_event_impl(wallet_id, *wallet_user_id, event.id).await;
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

    pub async fn apply_contact_group_ids_from_event_data_impl(
        &self,
        wallet_id: Uuid,
        contact_id: Uuid,
        event_data: &Value,
    ) -> Result<(), sqlx::Error> {
        let Some(arr) = event_data.get("group_ids").and_then(|v| v.as_array()) else {
            return Ok(());
        };
        let mut desired: std::collections::HashSet<Uuid> = std::collections::HashSet::new();
        if let Some(all_contacts_id) = sqlx::query_scalar::<_, Uuid>(
            "SELECT id FROM contact_groups WHERE wallet_id = $1 AND name = 'all_contacts' LIMIT 1",
        )
        .bind(wallet_id)
        .fetch_optional(&self.pool)
        .await?
        {
            desired.insert(all_contacts_id);
        }
        for g in arr {
            if let Some(s) = g.as_str().and_then(|s| Uuid::parse_str(s).ok()) {
                let in_wallet = sqlx::query_scalar::<_, bool>(
                    "SELECT EXISTS(SELECT 1 FROM contact_groups WHERE id = $1 AND wallet_id = $2)",
                )
                .bind(s)
                .bind(wallet_id)
                .fetch_one(&self.pool)
                .await
                .unwrap_or(false);
                if in_wallet {
                    desired.insert(s);
                }
            }
        }
        sqlx::query(
            "DELETE FROM contact_group_members WHERE contact_id = $1 AND contact_group_id IN (SELECT id FROM contact_groups WHERE wallet_id = $2)",
        )
        .bind(contact_id)
        .bind(wallet_id)
        .execute(&self.pool)
        .await?;
        for cg_id in &desired {
            sqlx::query(
                "INSERT INTO contact_group_members (contact_id, contact_group_id) VALUES ($1, $2) ON CONFLICT (contact_id, contact_group_id) DO NOTHING",
            )
            .bind(contact_id)
            .bind(cg_id)
            .execute(&self.pool)
            .await?;
        }
        Ok(())
    }

    pub async fn apply_event_batch(
        &self,
        events: &[&sqlx::postgres::PgRow],
        user_id: Uuid,
        wallet_id: Uuid,
        undone_event_ids: &mut std::collections::HashSet<Uuid>,
    ) -> Result<(), sqlx::Error> {
        tracing::info!("apply_event_batch: processing {} events", events.len());

        if undone_event_ids.is_empty() {
            for row in events.iter() {
                let event_type: String = row.get("event_type");
                if event_type == "UNDO" {
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

        for row in events {
            let event_id: Uuid = row.get("event_id");
            let aggregate_type: String = row.get("aggregate_type");
            let aggregate_id: Uuid = row.get("aggregate_id");
            let event_type: String = row.get("event_type");
            let event_data: Value = row.get("event_data");
            let created_at: NaiveDateTime = row.get("created_at");
            let event_db_id: i64 = row.get("id");

            tracing::info!(
                "apply_event_batch processing: type={}/{}",
                aggregate_type,
                event_type
            );

            if event_type == "UNDO" {
                continue;
            }

            if undone_event_ids.contains(&event_id) {
                continue;
            }

            if aggregate_type == "contact" {
                match event_type.as_str() {
                    "CREATED" => {
                        let name = event_data
                            .get("name")
                            .and_then(|v| v.as_str())
                            .unwrap_or("");
                        let username = event_data.get("username").and_then(|v| v.as_str());
                        let phone = event_data.get("phone").and_then(|v| v.as_str());
                        let email = event_data.get("email").and_then(|v| v.as_str());
                        let notes = event_data.get("notes").and_then(|v| v.as_str());

                        sqlx::query(
                            r#"
                            INSERT INTO contacts_projection
                            (id, user_id, wallet_id, name, username, phone, email, notes, is_deleted, created_at, updated_at, last_event_id)
                            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, false, $9, $9, $10)
                            ON CONFLICT (id) DO UPDATE SET
                                name = EXCLUDED.name,
                                username = EXCLUDED.username,
                                phone = EXCLUDED.phone,
                                email = EXCLUDED.email,
                                notes = EXCLUDED.notes,
                                updated_at = EXCLUDED.updated_at,
                                last_event_id = EXCLUDED.last_event_id
                            "#
                        )
                        .bind(aggregate_id)
                        .bind(user_id)
                        .bind(wallet_id)
                        .bind(name)
                        .bind(username)
                        .bind(phone)
                        .bind(email)
                        .bind(notes)
                        .bind(created_at)
                        .bind(event_db_id)
                        .execute(&self.pool)
                        .await?;

                        if let Some(all_contacts_id) = sqlx::query_scalar::<_, Uuid>(
                            "SELECT id FROM contact_groups WHERE wallet_id = $1 AND name = 'all_contacts' LIMIT 1",
                        )
                        .bind(wallet_id)
                        .fetch_optional(&self.pool)
                        .await?
                        {
                            let _ = sqlx::query(
                                "INSERT INTO contact_group_members (contact_id, contact_group_id) VALUES ($1, $2) ON CONFLICT DO NOTHING",
                            )
                            .bind(aggregate_id)
                            .bind(all_contacts_id)
                            .execute(&self.pool)
                            .await;
                        }
                        if let Some(arr) = event_data.get("group_ids").and_then(|v| v.as_array()) {
                            for g in arr {
                                if let Some(s) = g.as_str().and_then(|s| Uuid::parse_str(s).ok()) {
                                    let in_wallet = sqlx::query_scalar::<_, bool>(
                                        "SELECT EXISTS(SELECT 1 FROM contact_groups WHERE id = $1 AND wallet_id = $2)",
                                    )
                                    .bind(s)
                                    .bind(wallet_id)
                                    .fetch_one(&self.pool)
                                    .await
                                    .unwrap_or(false);
                                    if in_wallet {
                                        let _ = sqlx::query(
                                            "INSERT INTO contact_group_members (contact_id, contact_group_id) VALUES ($1, $2) ON CONFLICT DO NOTHING",
                                        )
                                        .bind(aggregate_id)
                                        .bind(s)
                                        .execute(&self.pool)
                                        .await;
                                    }
                                }
                            }
                        }
                    }
                    "UPDATED" => {
                        let current = sqlx::query(
                            "SELECT name, username, phone, email, notes FROM contacts_projection WHERE id = $1 AND wallet_id = $2"
                        )
                        .bind(aggregate_id)
                        .bind(wallet_id)
                        .fetch_optional(&self.pool)
                        .await?;

                        if let Some(current_row) = current {
                            let current_name: String = current_row.get("name");
                            let current_username: Option<String> = current_row.get("username");
                            let current_phone: Option<String> = current_row.get("phone");
                            let current_email: Option<String> = current_row.get("email");
                            let current_notes: Option<String> = current_row.get("notes");

                            let name = event_data
                                .get("name")
                                .and_then(|v| v.as_str())
                                .unwrap_or(&current_name);
                            let username = event_data
                                .get("username")
                                .and_then(|v| v.as_str())
                                .or(current_username.as_deref());
                            let phone = event_data
                                .get("phone")
                                .and_then(|v| v.as_str())
                                .or(current_phone.as_deref());
                            let email = event_data
                                .get("email")
                                .and_then(|v| v.as_str())
                                .or(current_email.as_deref());
                            let notes = event_data
                                .get("notes")
                                .and_then(|v| v.as_str())
                                .or(current_notes.as_deref());

                            sqlx::query(
                                r#"
                                UPDATE contacts_projection SET
                                    name = $2,
                                    username = $3,
                                    phone = $4,
                                    email = $5,
                                    notes = $6,
                                    updated_at = $7,
                                    last_event_id = $9
                                WHERE id = $1 AND wallet_id = $8
                                "#,
                            )
                            .bind(aggregate_id)
                            .bind(name)
                            .bind(username)
                            .bind(phone)
                            .bind(email)
                            .bind(notes)
                            .bind(created_at)
                            .bind(wallet_id)
                            .bind(event_db_id)
                            .execute(&self.pool)
                            .await?;
                        }
                        self.apply_contact_group_ids_from_event_data_impl(
                            wallet_id,
                            aggregate_id,
                            &event_data,
                        )
                        .await?;
                    }
                    "DELETED" => {
                        sqlx::query(
                            "UPDATE contacts_projection SET is_deleted = true, updated_at = $2, last_event_id = $4 WHERE id = $1 AND wallet_id = $3"
                        )
                        .bind(aggregate_id)
                        .bind(created_at)
                        .bind(wallet_id)
                        .bind(event_db_id)
                        .execute(&self.pool)
                        .await?;

                        let deleted_transactions = sqlx::query(
                            "UPDATE transactions_projection SET is_deleted = true, updated_at = $1, last_event_id = $4 WHERE contact_id = $2 AND wallet_id = $3 AND is_deleted = false"
                        )
                        .bind(created_at)
                        .bind(aggregate_id)
                        .bind(wallet_id)
                        .bind(event_db_id)
                        .execute(&self.pool)
                        .await?;

                        if deleted_transactions.rows_affected() > 0 {
                            tracing::info!(
                                "Deleted {} transaction(s) for deleted contact {}",
                                deleted_transactions.rows_affected(),
                                aggregate_id
                            );
                        }
                    }
                    _ => {}
                }
            } else if aggregate_type == "transaction" {
                match event_type.as_str() {
                    "CREATED" => {
                        let contact_id_str = event_data
                            .get("contact_id")
                            .and_then(|v| v.as_str())
                            .unwrap_or("");
                        let contact_id = Uuid::parse_str(contact_id_str).ok();

                        if let Some(cid) = contact_id {
                            let contact_exists = sqlx::query_scalar::<_, bool>(
                                "SELECT EXISTS(SELECT 1 FROM contacts_projection WHERE id = $1 AND wallet_id = $2 AND is_deleted = false)"
                            )
                            .bind(cid)
                            .bind(wallet_id)
                            .fetch_one(&self.pool)
                            .await?;

                            if !contact_exists {
                                tracing::warn!(
                                    "Skipping transaction creation for deleted contact {}",
                                    cid
                                );
                                continue;
                            }
                            let tx_type = event_data
                                .get("type")
                                .and_then(|v| v.as_str())
                                .unwrap_or("money");
                            let direction = event_data
                                .get("direction")
                                .and_then(|v| v.as_str())
                                .unwrap_or("lent");
                            let amount = event_data
                                .get("amount")
                                .and_then(|v| v.as_i64())
                                .unwrap_or(0);
                            let currency = event_data
                                .get("currency")
                                .and_then(|v| v.as_str())
                                .unwrap_or("USD");
                            let description =
                                event_data.get("description").and_then(|v| v.as_str());
                            let transaction_date_str = event_data
                                .get("transaction_date")
                                .and_then(|v| v.as_str())
                                .unwrap_or("");
                            let due_date_str = event_data.get("due_date").and_then(|v| v.as_str());

                            let transaction_date = if !transaction_date_str.is_empty() {
                                chrono::NaiveDate::parse_from_str(transaction_date_str, "%Y-%m-%d")
                                    .ok()
                            } else {
                                Some(created_at.date())
                            };

                            let due_date = due_date_str.and_then(|d| {
                                chrono::NaiveDate::parse_from_str(d, "%Y-%m-%d").ok()
                            });

                            if let Some(txn_date) = transaction_date {
                                sqlx::query(
                                    r#"
                                    INSERT INTO transactions_projection
                                    (id, user_id, wallet_id, contact_id, type, direction, amount, currency, description, transaction_date, due_date, is_deleted, created_at, updated_at, last_event_id)
                                    VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, false, $12, $12, $13)
                                    ON CONFLICT (id) DO UPDATE SET
                                        contact_id = EXCLUDED.contact_id,
                                        type = EXCLUDED.type,
                                        direction = EXCLUDED.direction,
                                        amount = EXCLUDED.amount,
                                        currency = EXCLUDED.currency,
                                        description = EXCLUDED.description,
                                        transaction_date = EXCLUDED.transaction_date,
                                        due_date = EXCLUDED.due_date,
                                        updated_at = EXCLUDED.updated_at,
                                        last_event_id = EXCLUDED.last_event_id
                                    "#
                                )
                                .bind(aggregate_id)
                                .bind(user_id)
                                .bind(wallet_id)
                                .bind(cid)
                                .bind(tx_type)
                                .bind(direction)
                                .bind(amount)
                                .bind(currency)
                                .bind(description)
                                .bind(txn_date)
                                .bind(due_date)
                                .bind(created_at)
                                .bind(event_db_id)
                                .execute(&self.pool)
                                .await?;
                            }
                        }
                    }
                    "UPDATED" => {
                        let current = sqlx::query(
                            "SELECT contact_id, type, direction, amount, currency, description, transaction_date, due_date FROM transactions_projection WHERE id = $1 AND wallet_id = $2"
                        )
                        .bind(aggregate_id)
                        .bind(wallet_id)
                        .fetch_optional(&self.pool)
                        .await?;

                        if let Some(current_row) = current {
                            let current_contact_id: Uuid = current_row.get("contact_id");
                            let current_type: String = current_row.get("type");
                            let current_direction: String = current_row.get("direction");
                            let current_amount: i64 = current_row.get("amount");
                            let current_currency: String = current_row.get("currency");
                            let current_description: Option<String> =
                                current_row.get("description");
                            let current_transaction_date: chrono::NaiveDate =
                                current_row.get("transaction_date");
                            let current_due_date: Option<chrono::NaiveDate> =
                                current_row.get("due_date");

                            let contact_id_str =
                                event_data.get("contact_id").and_then(|v| v.as_str());
                            let contact_id = contact_id_str
                                .and_then(|s| Uuid::parse_str(s).ok())
                                .unwrap_or(current_contact_id);

                            let tx_type = event_data
                                .get("type")
                                .and_then(|v| v.as_str())
                                .unwrap_or(&current_type);
                            let direction = event_data
                                .get("direction")
                                .and_then(|v| v.as_str())
                                .unwrap_or(&current_direction);
                            let amount = event_data
                                .get("amount")
                                .and_then(|v| v.as_i64())
                                .unwrap_or(current_amount);
                            let currency = event_data
                                .get("currency")
                                .and_then(|v| v.as_str())
                                .unwrap_or(&current_currency);
                            let description = event_data
                                .get("description")
                                .and_then(|v| v.as_str())
                                .or(current_description.as_deref());

                            let transaction_date_str =
                                event_data.get("transaction_date").and_then(|v| v.as_str());
                            let transaction_date = transaction_date_str
                                .and_then(|d| chrono::NaiveDate::parse_from_str(d, "%Y-%m-%d").ok())
                                .unwrap_or(current_transaction_date);

                            let due_date_str = event_data.get("due_date").and_then(|v| v.as_str());
                            let due_date = due_date_str
                                .and_then(|d| chrono::NaiveDate::parse_from_str(d, "%Y-%m-%d").ok())
                                .or(current_due_date);

                            sqlx::query(
                                r#"
                                UPDATE transactions_projection SET
                                    contact_id = $2,
                                    type = $3,
                                    direction = $4,
                                    amount = $5,
                                    currency = $6,
                                    description = $7,
                                    transaction_date = $8,
                                    due_date = $9,
                                    updated_at = $10,
                                    last_event_id = $12
                                WHERE id = $1 AND wallet_id = $11
                                "#,
                            )
                            .bind(aggregate_id)
                            .bind(contact_id)
                            .bind(tx_type)
                            .bind(direction)
                            .bind(amount)
                            .bind(currency)
                            .bind(description)
                            .bind(transaction_date)
                            .bind(due_date)
                            .bind(created_at)
                            .bind(wallet_id)
                            .bind(event_db_id)
                            .execute(&self.pool)
                            .await?;
                        }
                    }
                    "DELETED" => {
                        sqlx::query(
                            "UPDATE transactions_projection SET is_deleted = true, updated_at = $2, last_event_id = $4 WHERE id = $1 AND wallet_id = $3"
                        )
                        .bind(aggregate_id)
                        .bind(created_at)
                        .bind(wallet_id)
                        .bind(event_db_id)
                        .execute(&self.pool)
                        .await?;
                    }
                    _ => {}
                }
            } else if aggregate_type == "permission" {
                // Permission events are applied to operational tables (wallet_users, user_groups, etc.)
                // They don't have a separate projection table since they're normalized and frequently queried
                // Permission event data is nested in a "data" field because EventData variants use generic Value
                tracing::info!("Processing permission event: {}", event_type);
                let data = event_data.get("data").unwrap_or(&event_data);
                match event_type.as_str() {
                    "WALLET_USER_ADDED" => {
                        let user_id_str =
                            data.get("user_id").and_then(|v| v.as_str()).unwrap_or("");
                        tracing::info!("WALLET_USER_ADDED: inserting user {}", user_id_str);
                        if let Ok(perm_user_id) = Uuid::parse_str(user_id_str) {
                            let role = data
                                .get("role")
                                .and_then(|v| v.as_str())
                                .unwrap_or("member");
                            let result = sqlx::query(
                                r#"
                                INSERT INTO wallet_users (wallet_id, user_id, role, subscribed_at)
                                VALUES ($1, $2, $3, $4)
                                ON CONFLICT (wallet_id, user_id) DO UPDATE SET role = $3, subscribed_at = $4
                                "#
                            )
                            .bind(wallet_id)
                            .bind(perm_user_id)
                            .bind(role)
                            .bind(created_at)
                            .execute(&self.pool)
                            .await;

                            if let Err(e) = result {
                                tracing::error!("Error inserting wallet user: {:?}", e);
                            } else {
                                tracing::info!("Successfully inserted wallet user");
                            }
                        }
                    }
                    "WALLET_USER_ROLE_CHANGED" => {
                        let user_id_str =
                            data.get("user_id").and_then(|v| v.as_str()).unwrap_or("");
                        if let Ok(perm_user_id) = Uuid::parse_str(user_id_str) {
                            if let Some(role) = data.get("role").and_then(|v| v.as_str()) {
                                let _ = sqlx::query(
                                    "UPDATE wallet_users SET role = $1 WHERE wallet_id = $2 AND user_id = $3"
                                )
                                .bind(role)
                                .bind(wallet_id)
                                .bind(perm_user_id)
                                .execute(&self.pool)
                                .await;
                            }
                        }
                    }
                    "WALLET_USER_REMOVED" => {
                        let user_id_str =
                            data.get("user_id").and_then(|v| v.as_str()).unwrap_or("");
                        if let Ok(perm_user_id) = Uuid::parse_str(user_id_str) {
                            let _ = sqlx::query(
                                "DELETE FROM wallet_users WHERE wallet_id = $1 AND user_id = $2",
                            )
                            .bind(wallet_id)
                            .bind(perm_user_id)
                            .execute(&self.pool)
                            .await;
                        }
                    }
                    "USER_GROUP_CREATED" => {
                        let name = data.get("name").and_then(|v| v.as_str()).unwrap_or("");
                        let _ = sqlx::query(
                            "INSERT INTO user_groups (id, wallet_id, name, is_system) VALUES ($1, $2, $3, false) ON CONFLICT (id) DO UPDATE SET name = $3"
                        )
                        .bind(aggregate_id)
                        .bind(wallet_id)
                        .bind(name)
                        .execute(&self.pool)
                        .await;
                    }
                    "USER_GROUP_RENAMED" => {
                        let name = data.get("name").and_then(|v| v.as_str()).unwrap_or("");
                        let _ = sqlx::query(
                            "UPDATE user_groups SET name = $1 WHERE id = $2 AND wallet_id = $3 AND is_system = false"
                        )
                        .bind(name)
                        .bind(aggregate_id)
                        .bind(wallet_id)
                        .execute(&self.pool)
                        .await;
                    }
                    "USER_GROUP_DELETED" => {
                        let _ = sqlx::query("DELETE FROM user_groups WHERE id = $1 AND wallet_id = $2 AND is_system = false")
                            .bind(aggregate_id)
                            .bind(wallet_id)
                            .execute(&self.pool)
                            .await;
                    }
                    "USER_GROUP_MEMBER_ADDED" => {
                        let user_id_str =
                            data.get("user_id").and_then(|v| v.as_str()).unwrap_or("");
                        if let Ok(perm_user_id) = Uuid::parse_str(user_id_str) {
                            let _ = sqlx::query(
                                "INSERT INTO user_group_members (user_id, user_group_id) VALUES ($1, $2) ON CONFLICT (user_id, user_group_id) DO NOTHING"
                            )
                            .bind(perm_user_id)
                            .bind(aggregate_id)
                            .execute(&self.pool)
                            .await;
                        }
                    }
                    "USER_GROUP_MEMBER_REMOVED" => {
                        let user_id_str =
                            data.get("user_id").and_then(|v| v.as_str()).unwrap_or("");
                        if let Ok(perm_user_id) = Uuid::parse_str(user_id_str) {
                            let _ = sqlx::query("DELETE FROM user_group_members WHERE user_id = $1 AND user_group_id = $2")
                                .bind(perm_user_id)
                                .bind(aggregate_id)
                                .execute(&self.pool)
                                .await;
                        }
                    }
                    "CONTACT_GROUP_CREATED" => {
                        let name = data.get("name").and_then(|v| v.as_str()).unwrap_or("");
                        let _ = sqlx::query(
                            "INSERT INTO contact_groups (id, wallet_id, name, is_system) VALUES ($1, $2, $3, false) ON CONFLICT (id) DO UPDATE SET name = $3"
                        )
                        .bind(aggregate_id)
                        .bind(wallet_id)
                        .bind(name)
                        .execute(&self.pool)
                        .await;
                    }
                    "CONTACT_GROUP_RENAMED" => {
                        let name = data.get("name").and_then(|v| v.as_str()).unwrap_or("");
                        let _ = sqlx::query(
                            "UPDATE contact_groups SET name = $1 WHERE id = $2 AND wallet_id = $3 AND is_system = false"
                        )
                        .bind(name)
                        .bind(aggregate_id)
                        .bind(wallet_id)
                        .execute(&self.pool)
                        .await;
                    }
                    "CONTACT_GROUP_DELETED" => {
                        let _ = sqlx::query("DELETE FROM contact_groups WHERE id = $1 AND wallet_id = $2 AND is_system = false")
                            .bind(aggregate_id)
                            .bind(wallet_id)
                            .execute(&self.pool)
                            .await;
                    }
                    _ => {}
                }
            }
        }

        Ok(())
    }

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
            // TODO: Use type-driven approach (apply_event_batch_type_driven) once all handlers are complete
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
                        let tx_type = transaction_json
                            .get("type")
                            .and_then(|v| v.as_str())
                            .unwrap_or("money");
                        let direction = transaction_json
                            .get("direction")
                            .and_then(|v| v.as_str())
                            .unwrap_or("lent");
                        let amount = transaction_json
                            .get("amount")
                            .and_then(|v| v.as_i64())
                            .unwrap_or(0);
                        let currency = transaction_json
                            .get("currency")
                            .and_then(|v| v.as_str())
                            .unwrap_or("USD");
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
                            .bind(tx_type)
                            .bind(direction)
                            .bind(amount)
                            .bind(currency)
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
        aggregate_type: &str,
        aggregate_id: Uuid,
        event_data: &serde_json::Value,
        transaction_contact_map: &std::collections::HashMap<Uuid, Uuid>,
    ) -> bool {
        if aggregate_type == "permission" {
            return true;
        }
        if aggregate_type == "contact" {
            return match contact_ids_allowed {
                None => true,
                Some(set) => set.contains(&aggregate_id),
            };
        }
        if aggregate_type == "transaction" {
            let contact_id = event_data
                .get("contact_id")
                .and_then(|v| v.as_str())
                .and_then(|s| Uuid::parse_str(s).ok())
                .or_else(|| transaction_contact_map.get(&aggregate_id).copied());
            let Some(contact_id) = contact_id else {
                return false;
            };
            return match transaction_contact_ids_allowed {
                None => true,
                Some(set) => set.contains(&contact_id),
            };
        }
        false
    }
}
