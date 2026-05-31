use async_trait::async_trait;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Deserializer, Serialize};
use sqlx::Row;
use uuid::Uuid;

// ============ AGGREGATE TYPE ENUM ============

/// Strongly-typed aggregate types. Use instead of string matching.
/// Add new types here as the system grows (user, team, etc.)
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum AggregateType {
    Contact,
    Transaction,
    Permission,
}

impl AggregateType {
    pub fn as_str(&self) -> &'static str {
        match self {
            AggregateType::Contact => "contact",
            AggregateType::Transaction => "transaction",
            AggregateType::Permission => "permission",
        }
    }

    pub fn from_str(s: &str) -> Option<Self> {
        match s {
            "contact" => Some(AggregateType::Contact),
            "transaction" => Some(AggregateType::Transaction),
            "permission" => Some(AggregateType::Permission),
            _ => None,
        }
    }
}

// ============ EVENT DATA PAYLOAD ============

/// Strongly-typed event data payload. Each variant carries only its specific fields.
/// Serialized with #[serde(tag = "type")] so each variant is discriminated by a "type" field.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum EventData {
    // Contact events
    ContactCreated {
        name: String,
        #[serde(default)]
        username: Option<String>,
        #[serde(default)]
        phone: Option<String>,
        #[serde(default)]
        email: Option<String>,
        #[serde(default)]
        notes: Option<String>,
    },
    ContactUpdated {
        #[serde(default)]
        name: Option<String>,
        #[serde(default)]
        username: Option<String>,
        #[serde(default)]
        phone: Option<String>,
        #[serde(default)]
        email: Option<String>,
        #[serde(default)]
        notes: Option<String>,
    },
    ContactDeleted {
        #[serde(default)]
        comment: Option<String>,
    },
    ContactUndone {
        undone_event_id: String,
    },

    // Transaction events
    TransactionCreated {
        contact_id: String,
        amount: i64,
        direction: String,
        #[serde(default)]
        transaction_type: Option<String>,
        #[serde(default)]
        currency: Option<String>,
        #[serde(default)]
        description: Option<String>,
        #[serde(default)]
        transaction_date: Option<String>,
        #[serde(default)]
        due_date: Option<String>,
    },
    TransactionUpdated {
        #[serde(default)]
        contact_id: Option<String>,
        #[serde(default)]
        amount: Option<i64>,
        #[serde(default)]
        direction: Option<String>,
        #[serde(default)]
        transaction_type: Option<String>,
        #[serde(default)]
        currency: Option<String>,
        #[serde(default)]
        description: Option<String>,
        #[serde(default)]
        transaction_date: Option<String>,
        #[serde(default)]
        due_date: Option<String>,
    },
    TransactionDeleted {
        #[serde(default)]
        comment: Option<String>,
    },
    TransactionUndone {
        undone_event_id: String,
    },

    // Permission events (14 variants with generic untyped data)
    WalletUserAdded {
        #[serde(default)]
        data: serde_json::Value,
    },
    WalletUserRoleChanged {
        #[serde(default)]
        data: serde_json::Value,
    },
    WalletUserRemoved {
        #[serde(default)]
        data: serde_json::Value,
    },
    UserGroupCreated {
        #[serde(default)]
        data: serde_json::Value,
    },
    UserGroupUpdated {
        #[serde(default)]
        data: serde_json::Value,
    },
    UserGroupDeleted {
        #[serde(default)]
        data: serde_json::Value,
    },
    UserGroupMemberAdded {
        #[serde(default)]
        data: serde_json::Value,
    },
    UserGroupMemberRemoved {
        #[serde(default)]
        data: serde_json::Value,
    },
    ContactGroupCreated {
        #[serde(default)]
        data: serde_json::Value,
    },
    ContactGroupUpdated {
        #[serde(default)]
        data: serde_json::Value,
    },
    ContactGroupDeleted {
        #[serde(default)]
        data: serde_json::Value,
    },
    ContactGroupMemberAdded {
        #[serde(default)]
        data: serde_json::Value,
    },
    ContactGroupMemberRemoved {
        #[serde(default)]
        data: serde_json::Value,
    },
    PermissionMatrixSet {
        #[serde(default)]
        data: serde_json::Value,
    },
}

impl EventData {
    /// Get the aggregate type for this event data
    pub fn aggregate_type(&self) -> AggregateType {
        match self {
            EventData::ContactCreated { .. }
            | EventData::ContactUpdated { .. }
            | EventData::ContactDeleted { .. }
            | EventData::ContactUndone { .. } => AggregateType::Contact,
            EventData::TransactionCreated { .. }
            | EventData::TransactionUpdated { .. }
            | EventData::TransactionDeleted { .. }
            | EventData::TransactionUndone { .. } => AggregateType::Transaction,
            _ => AggregateType::Permission,
        }
    }

    /// Get the event type string
    pub fn event_type(&self) -> &'static str {
        match self {
            EventData::ContactCreated { .. } => "CREATED",
            EventData::ContactUpdated { .. } => "UPDATED",
            EventData::ContactDeleted { .. } => "DELETED",
            EventData::ContactUndone { .. } => "UNDO",
            EventData::TransactionCreated { .. } => "CREATED",
            EventData::TransactionUpdated { .. } => "UPDATED",
            EventData::TransactionDeleted { .. } => "DELETED",
            EventData::TransactionUndone { .. } => "UNDO",
            EventData::WalletUserAdded { .. } => "WALLET_USER_ADDED",
            EventData::WalletUserRoleChanged { .. } => "WALLET_USER_ROLE_CHANGED",
            EventData::WalletUserRemoved { .. } => "WALLET_USER_REMOVED",
            EventData::UserGroupCreated { .. } => "USER_GROUP_CREATED",
            EventData::UserGroupUpdated { .. } => "USER_GROUP_UPDATED",
            EventData::UserGroupDeleted { .. } => "USER_GROUP_DELETED",
            EventData::UserGroupMemberAdded { .. } => "USER_GROUP_MEMBER_ADDED",
            EventData::UserGroupMemberRemoved { .. } => "USER_GROUP_MEMBER_REMOVED",
            EventData::ContactGroupCreated { .. } => "CONTACT_GROUP_CREATED",
            EventData::ContactGroupUpdated { .. } => "CONTACT_GROUP_UPDATED",
            EventData::ContactGroupDeleted { .. } => "CONTACT_GROUP_DELETED",
            EventData::ContactGroupMemberAdded { .. } => "CONTACT_GROUP_MEMBER_ADDED",
            EventData::ContactGroupMemberRemoved { .. } => "CONTACT_GROUP_MEMBER_REMOVED",
            EventData::PermissionMatrixSet { .. } => "PERMISSION_MATRIX_SET",
        }
    }
}

// ============ EVENT APPLIER TRAIT ============

/// Trait for events that know how to apply themselves during projection rebuilds.
/// Each aggregate type implements this to handle its own application logic.
#[async_trait]
pub trait EventApplier: Send + Sync {
    /// Apply this event to the database during sync or rebuild
    async fn apply(
        &self,
        pool: &sqlx::PgPool,
        wallet_id: Uuid,
        user_id: Uuid,
        event_db_id: i64,
        created_at: chrono::NaiveDateTime,
    ) -> Result<(), sqlx::Error>;

    /// Clear all projections/data for this aggregate type in a wallet during rebuild with UNDO events
    async fn clear_for_rebuild(
        &self,
        pool: &sqlx::PgPool,
        wallet_id: Uuid,
    ) -> Result<(), sqlx::Error>;

    /// Get the aggregate type for this event (contact, transaction, permission, etc.)
    fn aggregate_type(&self) -> &'static str;
}

// ============ DOMAIN EVENT ============

/// Strongly-typed domain event with metadata in the struct and payload in EventData enum.
/// This separates concerns: metadata (id, wallet_id, user_id, created_at, version) from
/// event-specific payload (in event_data).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DomainEvent {
    pub id: Uuid,
    pub aggregate_id: Uuid,
    pub wallet_id: Uuid,
    pub user_id: Uuid,
    #[serde(deserialize_with = "deserialize_datetime_utc")]
    pub created_at: DateTime<Utc>,
    pub version: i32,
    pub idempotency_key: Option<String>,
    pub event_data: EventData,
}

impl DomainEvent {
    /// Get the strongly-typed aggregate type for this event
    pub fn aggregate_type_enum(&self) -> AggregateType {
        self.event_data.aggregate_type()
    }

    /// Get the aggregate type as a string (for database storage)
    pub fn aggregate_type(&self) -> &'static str {
        self.aggregate_type_enum().as_str()
    }

    /// Get the event type string
    pub fn event_type(&self) -> &'static str {
        self.event_data.event_type()
    }

    /// Convert DomainEvent to a generic Event for database storage
    pub fn to_event(&self) -> crate::database::models::Event {
        crate::database::models::Event {
            id: self.id,
            aggregate_id: self.aggregate_id,
            aggregate_type: self.aggregate_type().to_string(),
            event_type: self.event_type().to_string(),
            data: serde_json::to_value(self).unwrap_or(serde_json::json!({})),
            wallet_id: self.wallet_id,
            user_id: self.user_id,
            created_at: self.created_at,
            version: self.version,
            idempotency_key: self.idempotency_key.clone(),
        }
    }

    /// Convert a generic Event to DomainEvent
    pub fn from_event(event: &crate::database::models::Event) -> Result<Self, String> {
        serde_json::from_value(event.data.clone())
            .map_err(|e| format!("Failed to deserialize event: {}", e))
    }

    /// Apply this event based on its aggregate type
    /// This is the main entry point for event application during sync and rebuild
    pub async fn apply_self(
        &self,
        pool: &sqlx::PgPool,
        wallet_id: Uuid,
        user_id: Uuid,
        event_db_id: i64,
        created_at: chrono::NaiveDateTime,
    ) -> Result<(), sqlx::Error> {
        match self.aggregate_type_enum() {
            AggregateType::Contact => {
                self.apply_contact_event(pool, wallet_id, user_id, event_db_id, created_at)
                    .await
            }
            AggregateType::Transaction => {
                self.apply_transaction_event(pool, wallet_id, user_id, event_db_id, created_at)
                    .await
            }
            AggregateType::Permission => {
                self.apply_permission_event(pool, wallet_id, user_id, event_db_id, created_at)
                    .await
            }
        }
    }

    /// Clear projections/data for a given aggregate type during rebuild with UNDO events
    pub async fn clear_aggregate_type(
        pool: &sqlx::PgPool,
        agg_type: AggregateType,
        wallet_id: Uuid,
    ) -> Result<(), sqlx::Error> {
        match agg_type {
            AggregateType::Contact => {
                sqlx::query("DELETE FROM contacts_projection WHERE wallet_id = $1")
                    .bind(wallet_id)
                    .execute(pool)
                    .await?;
            }
            AggregateType::Transaction => {
                sqlx::query("DELETE FROM transactions_projection WHERE wallet_id = $1")
                    .bind(wallet_id)
                    .execute(pool)
                    .await?;
            }
            AggregateType::Permission => {
                sqlx::query("DELETE FROM contact_group_members WHERE contact_group_id IN (SELECT id FROM contact_groups WHERE wallet_id = $1 AND is_system = false)")
                    .bind(wallet_id)
                    .execute(pool)
                    .await?;
                sqlx::query(
                    "DELETE FROM contact_groups WHERE wallet_id = $1 AND is_system = false",
                )
                .bind(wallet_id)
                .execute(pool)
                .await?;
                sqlx::query("DELETE FROM user_group_members WHERE user_group_id IN (SELECT id FROM user_groups WHERE wallet_id = $1 AND is_system = false)")
                    .bind(wallet_id)
                    .execute(pool)
                    .await?;
                sqlx::query("DELETE FROM user_groups WHERE wallet_id = $1 AND is_system = false")
                    .bind(wallet_id)
                    .execute(pool)
                    .await?;
                sqlx::query("DELETE FROM wallet_users WHERE wallet_id = $1 AND role != 'owner'")
                    .bind(wallet_id)
                    .execute(pool)
                    .await?;
            }
        }
        Ok(())
    }

    /// Apply contact-specific events
    async fn apply_contact_event(
        &self,
        pool: &sqlx::PgPool,
        wallet_id: Uuid,
        user_id: Uuid,
        event_db_id: i64,
        created_at: chrono::NaiveDateTime,
    ) -> Result<(), sqlx::Error> {
        match &self.event_data {
            EventData::ContactCreated {
                name,
                username,
                phone,
                email,
                notes,
            } => {
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
                .bind(self.aggregate_id)
                .bind(user_id)
                .bind(wallet_id)
                .bind(name)
                .bind(username)
                .bind(phone)
                .bind(email)
                .bind(notes)
                .bind(created_at)
                .bind(event_db_id)
                .execute(pool)
                .await?;
                Ok(())
            }
            EventData::ContactUpdated {
                name,
                username,
                phone,
                email,
                notes,
            } => {
                let current = sqlx::query(
                    "SELECT name, username, phone, email, notes FROM contacts_projection WHERE id = $1 AND wallet_id = $2"
                )
                .bind(self.aggregate_id)
                .bind(wallet_id)
                .fetch_optional(pool)
                .await?;

                if let Some(current_row) = current {
                    let current_name: String = current_row.get("name");
                    let current_username: Option<String> = current_row.get("username");
                    let current_phone: Option<String> = current_row.get("phone");
                    let current_email: Option<String> = current_row.get("email");
                    let current_notes: Option<String> = current_row.get("notes");

                    let final_name = name.as_ref().unwrap_or(&current_name);
                    let final_username = username.as_ref().or(current_username.as_ref());
                    let final_phone = phone.as_ref().or(current_phone.as_ref());
                    let final_email = email.as_ref().or(current_email.as_ref());
                    let final_notes = notes.as_ref().or(current_notes.as_ref());

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
                    .bind(self.aggregate_id)
                    .bind(final_name)
                    .bind(final_username)
                    .bind(final_phone)
                    .bind(final_email)
                    .bind(final_notes)
                    .bind(created_at)
                    .bind(wallet_id)
                    .bind(event_db_id)
                    .execute(pool)
                    .await?;
                }
                Ok(())
            }
            EventData::ContactDeleted { .. } => {
                sqlx::query(
                    "UPDATE contacts_projection SET is_deleted = true, updated_at = $2, last_event_id = $4 WHERE id = $1 AND wallet_id = $3"
                )
                .bind(self.aggregate_id)
                .bind(created_at)
                .bind(wallet_id)
                .bind(event_db_id)
                .execute(pool)
                .await?;

                let _ = sqlx::query(
                    "UPDATE transactions_projection SET is_deleted = true, updated_at = $1, last_event_id = $4 WHERE contact_id = $2 AND wallet_id = $3 AND is_deleted = false"
                )
                .bind(created_at)
                .bind(self.aggregate_id)
                .bind(wallet_id)
                .bind(event_db_id)
                .execute(pool)
                .await;

                Ok(())
            }
            EventData::ContactUndone { .. } => {
                // UNDO events are skipped at a higher level
                Ok(())
            }
            _ => Ok(()),
        }
    }

    /// Apply transaction-specific events
    async fn apply_transaction_event(
        &self,
        pool: &sqlx::PgPool,
        wallet_id: Uuid,
        user_id: Uuid,
        event_db_id: i64,
        created_at: chrono::NaiveDateTime,
    ) -> Result<(), sqlx::Error> {
        match &self.event_data {
            EventData::TransactionCreated {
                contact_id,
                amount,
                direction,
                transaction_type,
                currency,
                description,
                transaction_date,
                due_date,
            } => {
                let contact_uuid = Uuid::parse_str(contact_id)
                    .map_err(|_| sqlx::Error::RowNotFound)?;
                let txn_date = transaction_date
                    .as_ref()
                    .and_then(|d| DateTime::parse_from_rfc3339(d).ok())
                    .map(|dt| dt.with_timezone(&Utc));
                let due = due_date
                    .as_ref()
                    .and_then(|d| DateTime::parse_from_rfc3339(d).ok())
                    .map(|dt| dt.with_timezone(&Utc));

                sqlx::query(
                    r#"
                    INSERT INTO transactions_projection (
                        id, wallet_id, user_id, contact_id, amount, direction,
                        transaction_type, currency, description, transaction_date, due_date,
                        created_at, updated_at, is_deleted, last_event_id
                    ) VALUES (
                        $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $12, false, $13
                    )
                    ON CONFLICT (id) DO UPDATE SET
                        contact_id = EXCLUDED.contact_id,
                        amount = EXCLUDED.amount,
                        direction = EXCLUDED.direction,
                        transaction_type = EXCLUDED.transaction_type,
                        currency = EXCLUDED.currency,
                        description = EXCLUDED.description,
                        transaction_date = EXCLUDED.transaction_date,
                        due_date = EXCLUDED.due_date,
                        updated_at = EXCLUDED.updated_at,
                        last_event_id = EXCLUDED.last_event_id
                    "#,
                )
                .bind(self.aggregate_id)
                .bind(wallet_id)
                .bind(user_id)
                .bind(contact_uuid)
                .bind(amount)
                .bind(direction)
                .bind(transaction_type)
                .bind(currency)
                .bind(description)
                .bind(txn_date)
                .bind(due)
                .bind(created_at)
                .bind(event_db_id)
                .execute(pool)
                .await?;
                Ok(())
            }
            EventData::TransactionUpdated {
                contact_id,
                amount,
                direction,
                transaction_type,
                currency,
                description,
                transaction_date,
                due_date,
            } => {
                let current = sqlx::query(
                    "SELECT contact_id, amount, direction, transaction_type, currency, description, transaction_date, due_date FROM transactions_projection WHERE id = $1 AND wallet_id = $2"
                )
                .bind(self.aggregate_id)
                .bind(wallet_id)
                .fetch_optional(pool)
                .await?;

                if let Some(current_row) = current {
                    let current_contact_id: Uuid = current_row.get("contact_id");
                    let current_amount: i64 = current_row.get("amount");
                    let current_direction: String = current_row.get("direction");
                    let current_transaction_type: Option<String> =
                        current_row.get("transaction_type");
                    let current_currency: Option<String> = current_row.get("currency");
                    let current_description: Option<String> = current_row.get("description");
                    let current_transaction_date: Option<DateTime<Utc>> =
                        current_row.get("transaction_date");
                    let current_due_date: Option<DateTime<Utc>> = current_row.get("due_date");

                    let final_contact_id = contact_id
                        .as_ref()
                        .and_then(|c| Uuid::parse_str(c).ok())
                        .unwrap_or(current_contact_id);
                    let final_amount = amount.unwrap_or(current_amount);
                    let final_direction = direction.as_ref().unwrap_or(&current_direction);
                    let final_transaction_type = transaction_type
                        .as_ref()
                        .or(current_transaction_type.as_ref());
                    let final_currency = currency.as_ref().or(current_currency.as_ref());
                    let final_description = description.as_ref().or(current_description.as_ref());
                    let final_transaction_date = transaction_date
                        .as_ref()
                        .and_then(|d| DateTime::parse_from_rfc3339(d).ok())
                        .map(|dt| dt.with_timezone(&Utc))
                        .or(current_transaction_date);
                    let final_due_date = due_date
                        .as_ref()
                        .and_then(|d| DateTime::parse_from_rfc3339(d).ok())
                        .map(|dt| dt.with_timezone(&Utc))
                        .or(current_due_date);

                    sqlx::query(
                        r#"
                        UPDATE transactions_projection SET
                            contact_id = $2,
                            amount = $3,
                            direction = $4,
                            transaction_type = $5,
                            currency = $6,
                            description = $7,
                            transaction_date = $8,
                            due_date = $9,
                            updated_at = $10,
                            last_event_id = $11
                        WHERE id = $1 AND wallet_id = $12
                        "#,
                    )
                    .bind(self.aggregate_id)
                    .bind(final_contact_id)
                    .bind(final_amount)
                    .bind(final_direction)
                    .bind(final_transaction_type)
                    .bind(final_currency)
                    .bind(final_description)
                    .bind(final_transaction_date)
                    .bind(final_due_date)
                    .bind(created_at)
                    .bind(event_db_id)
                    .bind(wallet_id)
                    .execute(pool)
                    .await?;
                }
                Ok(())
            }
            EventData::TransactionDeleted { .. } => {
                sqlx::query(
                    "UPDATE transactions_projection SET is_deleted = true, updated_at = $2, last_event_id = $4 WHERE id = $1 AND wallet_id = $3"
                )
                .bind(self.aggregate_id)
                .bind(created_at)
                .bind(wallet_id)
                .bind(event_db_id)
                .execute(pool)
                .await?;
                Ok(())
            }
            EventData::TransactionUndone { .. } => {
                // UNDO events are skipped at a higher level
                Ok(())
            }
            _ => Ok(()),
        }
    }

    /// Apply permission-specific events
    async fn apply_permission_event(
        &self,
        pool: &sqlx::PgPool,
        wallet_id: Uuid,
        _user_id: Uuid,
        _event_db_id: i64,
        _created_at: chrono::NaiveDateTime,
    ) -> Result<(), sqlx::Error> {
        match &self.event_data {
            EventData::WalletUserAdded { data } => {
                if let Some(user_id_str) = data.get("user_id").and_then(|v| v.as_str()) {
                    if let Ok(perm_user_id) = Uuid::parse_str(user_id_str) {
                        let role = data
                            .get("role")
                            .and_then(|v| v.as_str())
                            .unwrap_or("member");
                        let _ = sqlx::query(
                            r#"
                            INSERT INTO wallet_users (wallet_id, user_id, role, subscribed_at)
                            VALUES ($1, $2, $3, NOW())
                            ON CONFLICT (wallet_id, user_id) DO UPDATE SET role = $3
                            "#,
                        )
                        .bind(wallet_id)
                        .bind(perm_user_id)
                        .bind(role)
                        .execute(pool)
                        .await;
                    }
                }
                Ok(())
            }
            EventData::WalletUserRoleChanged { data } => {
                if let Some(user_id_str) = data.get("user_id").and_then(|v| v.as_str()) {
                    if let Ok(perm_user_id) = Uuid::parse_str(user_id_str) {
                        if let Some(role) = data.get("role").and_then(|v| v.as_str()) {
                            let _ = sqlx::query(
                                "UPDATE wallet_users SET role = $1 WHERE wallet_id = $2 AND user_id = $3"
                            )
                            .bind(role)
                            .bind(wallet_id)
                            .bind(perm_user_id)
                            .execute(pool)
                            .await;
                        }
                    }
                }
                Ok(())
            }
            EventData::WalletUserRemoved { data } => {
                if let Some(user_id_str) = data.get("user_id").and_then(|v| v.as_str()) {
                    if let Ok(perm_user_id) = Uuid::parse_str(user_id_str) {
                        let _ = sqlx::query(
                            "DELETE FROM wallet_users WHERE wallet_id = $1 AND user_id = $2",
                        )
                        .bind(wallet_id)
                        .bind(perm_user_id)
                        .execute(pool)
                        .await;
                    }
                }
                Ok(())
            }
            EventData::UserGroupCreated { data } => {
                let name = data.get("name").and_then(|v| v.as_str()).unwrap_or("");
                let _ = sqlx::query(
                    "INSERT INTO user_groups (id, wallet_id, name, is_system) VALUES ($1, $2, $3, false) ON CONFLICT (id) DO UPDATE SET name = $3"
                )
                .bind(self.aggregate_id)
                .bind(wallet_id)
                .bind(name)
                .execute(pool)
                .await;
                Ok(())
            }
            _ => Ok(()),
        }
    }

    /// Get required permissions for this event (type-driven)
    /// Permission events require Admin or Owner role
    pub fn required_permissions(
        &self,
    ) -> Vec<(crate::permissions::Action, crate::permissions::Resource)> {
        use crate::permissions::{Action, Resource};

        match &self.event_data {
            // Contact events
            EventData::ContactCreated { .. } => {
                vec![(Action::ContactCreate, Resource::AllContacts)]
            }
            EventData::ContactUpdated { .. } => {
                vec![(Action::ContactUpdate, Resource::Contact(self.aggregate_id))]
            }
            EventData::ContactDeleted { .. } => {
                vec![(Action::ContactDelete, Resource::Contact(self.aggregate_id))]
            }
            EventData::ContactUndone { .. } => {
                vec![(Action::ContactUpdate, Resource::Contact(self.aggregate_id))]
            }
            // Transaction events
            EventData::TransactionCreated { contact_id, .. } => {
                if let Ok(cid) = Uuid::parse_str(contact_id) {
                    vec![(Action::TransactionCreate, Resource::Contact(cid))]
                } else {
                    vec![]
                }
            }
            EventData::TransactionUpdated { .. } => {
                vec![(
                    Action::TransactionUpdate,
                    Resource::Transaction(self.aggregate_id),
                )]
            }
            EventData::TransactionDeleted { .. } => {
                vec![(
                    Action::TransactionDelete,
                    Resource::Transaction(self.aggregate_id),
                )]
            }
            EventData::TransactionUndone { .. } => {
                vec![(
                    Action::TransactionUpdate,
                    Resource::Transaction(self.aggregate_id),
                )]
            }
            // Permission events
            EventData::WalletUserAdded { .. } => {
                vec![(Action::WalletUpdate, Resource::Wallet(self.wallet_id))]
            }
            EventData::WalletUserRemoved { .. } => {
                vec![(Action::WalletUpdate, Resource::Wallet(self.wallet_id))]
            }
            EventData::WalletUserRoleChanged { .. } => {
                vec![(Action::WalletUpdate, Resource::Wallet(self.wallet_id))]
            }
            EventData::UserGroupCreated { .. } => {
                vec![(Action::UserGroupCreate, Resource::Wallet(self.wallet_id))]
            }
            EventData::UserGroupUpdated { .. } => {
                vec![(Action::UserGroupUpdate, Resource::Wallet(self.wallet_id))]
            }
            EventData::UserGroupDeleted { .. } => {
                vec![(Action::WalletUpdate, Resource::Wallet(self.wallet_id))]
            }
            EventData::UserGroupMemberAdded { .. } => {
                vec![(Action::UserGroupUpdate, Resource::Wallet(self.wallet_id))]
            }
            EventData::UserGroupMemberRemoved { .. } => {
                vec![(Action::UserGroupUpdate, Resource::Wallet(self.wallet_id))]
            }
            EventData::ContactGroupCreated { .. } => {
                vec![(Action::ContactGroupCreate, Resource::Wallet(self.wallet_id))]
            }
            EventData::ContactGroupUpdated { .. } => {
                vec![(Action::ContactGroupUpdate, Resource::Wallet(self.wallet_id))]
            }
            EventData::ContactGroupDeleted { .. } => {
                vec![(Action::WalletUpdate, Resource::Wallet(self.wallet_id))]
            }
            EventData::ContactGroupMemberAdded { .. } => {
                vec![(Action::ContactGroupUpdate, Resource::Wallet(self.wallet_id))]
            }
            EventData::ContactGroupMemberRemoved { .. } => {
                vec![(Action::ContactGroupUpdate, Resource::Wallet(self.wallet_id))]
            }
            EventData::PermissionMatrixSet { .. } => {
                vec![(Action::UserGroupUpdate, Resource::Wallet(self.wallet_id))]
            }
        }
    }
}

// ============ HTTP REQUEST TYPES ============

/// Custom deserializer for UUID strings - validates format
fn deserialize_uuid_string<'de, D>(deserializer: D) -> Result<String, D::Error>
where
    D: Deserializer<'de>,
{
    let s = String::deserialize(deserializer)?;
    Uuid::parse_str(&s).map_err(serde::de::Error::custom)?;
    Ok(s)
}

/// Custom deserializer for aggregate_type - validates against allowed values
fn deserialize_aggregate_type<'de, D>(deserializer: D) -> Result<String, D::Error>
where
    D: Deserializer<'de>,
{
    let s = String::deserialize(deserializer)?;
    match s.as_str() {
        "contact" | "transaction" | "permission" => Ok(s),
        _ => Err(serde::de::Error::custom(format!(
            "Invalid aggregate_type '{}'. Must be one of: contact, transaction, permission",
            s
        ))),
    }
}

/// Custom deserializer for event_type - validates against allowed values
fn deserialize_event_type<'de, D>(deserializer: D) -> Result<String, D::Error>
where
    D: Deserializer<'de>,
{
    let s = String::deserialize(deserializer)?;
    match s.as_str() {
        "CREATED" | "UPDATED" | "DELETED" | "UNDO" => Ok(s),
        "WALLET_USER_ADDED" | "WALLET_USER_ROLE_CHANGED" | "WALLET_USER_REMOVED"
        | "USER_GROUP_CREATED" | "USER_GROUP_UPDATED" | "USER_GROUP_DELETED"
        | "USER_GROUP_MEMBER_ADDED" | "USER_GROUP_MEMBER_REMOVED"
        | "CONTACT_GROUP_CREATED" | "CONTACT_GROUP_UPDATED" | "CONTACT_GROUP_DELETED"
        | "CONTACT_GROUP_MEMBER_ADDED" | "CONTACT_GROUP_MEMBER_REMOVED"
        | "PERMISSION_MATRIX_SET" => Ok(s),
        _ => Err(serde::de::Error::custom(format!(
            "Invalid event_type '{}'. Must be a valid event type",
            s
        ))),
    }
}

/// Custom deserializer for RFC3339 timestamp string - validates format
fn deserialize_timestamp<'de, D>(deserializer: D) -> Result<String, D::Error>
where
    D: Deserializer<'de>,
{
    let s = String::deserialize(deserializer)?;
    DateTime::parse_from_rfc3339(&s)
        .map_err(|_| serde::de::Error::custom("Invalid RFC3339 timestamp format"))?;
    Ok(s)
}

/// Custom deserializer for DateTime<Utc> from RFC3339 string
fn deserialize_datetime_utc<'de, D>(deserializer: D) -> Result<DateTime<Utc>, D::Error>
where
    D: Deserializer<'de>,
{
    let s = String::deserialize(deserializer)?;
    DateTime::parse_from_rfc3339(&s)
        .map(|dt| dt.with_timezone(&Utc))
        .map_err(|_| serde::de::Error::custom("Invalid RFC3339 timestamp format"))
}

/// Sync event request with validation at deserialization boundary.
#[derive(Debug, Clone, Deserialize)]
pub struct SyncEventRequest {
    #[serde(deserialize_with = "deserialize_uuid_string")]
    pub id: String,
    #[serde(deserialize_with = "deserialize_aggregate_type")]
    pub aggregate_type: String,
    #[serde(deserialize_with = "deserialize_uuid_string")]
    pub aggregate_id: String,
    #[serde(deserialize_with = "deserialize_event_type")]
    pub event_type: String,
    pub event_data: serde_json::Value,
    #[serde(deserialize_with = "deserialize_timestamp")]
    pub timestamp: String,
    pub version: i32,
}

impl SyncEventRequest {
    /// Validate event data
    pub fn validate_data(&self) -> Option<String> {
        match (self.aggregate_type.as_str(), self.event_type.as_str()) {
            ("contact", "UNDO") | ("transaction", "UNDO") => {
                if self
                    .event_data
                    .get("undone_event_id")
                    .and_then(|v| v.as_str())
                    .is_none()
                {
                    return Some(
                        "UNDO events must have 'undone_event_id' in event_data".to_string(),
                    );
                }
                if let Some(undone_id) = self
                    .event_data
                    .get("undone_event_id")
                    .and_then(|v| v.as_str())
                {
                    if Uuid::parse_str(undone_id).is_err() {
                        return Some(
                            "UNDO event 'undone_event_id' must be a valid UUID".to_string(),
                        );
                    }
                }
            }
            ("contact", "CREATED") => {
                if self
                    .event_data
                    .get("name")
                    .and_then(|v| v.as_str())
                    .is_none()
                {
                    return Some(
                        "CREATED contact events must have 'name' in event_data".to_string(),
                    );
                }
            }
            ("transaction", "CREATED") => {
                if self
                    .event_data
                    .get("amount")
                    .and_then(|v| v.as_i64())
                    .is_none()
                {
                    return Some("CREATED transaction must have 'amount'".to_string());
                }
                if self
                    .event_data
                    .get("direction")
                    .and_then(|v| v.as_str())
                    .is_none()
                {
                    return Some("CREATED transaction must have 'direction'".to_string());
                }
                if self
                    .event_data
                    .get("contact_id")
                    .and_then(|v| v.as_str())
                    .is_none()
                {
                    return Some("CREATED transaction must have 'contact_id'".to_string());
                }
            }
            _ => {}
        }
        None
    }

    /// Get required permissions for this event
    pub fn required_permissions(
        &self,
    ) -> Vec<(crate::permissions::Action, crate::permissions::Resource)> {
        use crate::permissions::{Action, Resource};

        match (self.aggregate_type.as_str(), self.event_type.as_str()) {
            ("contact", "CREATED") => vec![(Action::ContactCreate, Resource::AllContacts)],
            ("contact", "UPDATED") => {
                if let Ok(id) = Uuid::parse_str(&self.aggregate_id) {
                    vec![(Action::ContactUpdate, Resource::Contact(id))]
                } else {
                    vec![]
                }
            }
            ("contact", "DELETED") => {
                if let Ok(id) = Uuid::parse_str(&self.aggregate_id) {
                    vec![(Action::ContactDelete, Resource::Contact(id))]
                } else {
                    vec![]
                }
            }
            ("contact", "UNDO") => {
                if let Ok(id) = Uuid::parse_str(&self.aggregate_id) {
                    vec![(Action::ContactUpdate, Resource::Contact(id))]
                } else {
                    vec![]
                }
            }
            ("transaction", "CREATED") => {
                vec![(Action::TransactionCreate, Resource::AllTransactions)]
            }
            ("transaction", "UPDATED") => {
                if let Ok(id) = Uuid::parse_str(&self.aggregate_id) {
                    vec![(Action::TransactionUpdate, Resource::Transaction(id))]
                } else {
                    vec![]
                }
            }
            ("transaction", "DELETED") => {
                if let Ok(id) = Uuid::parse_str(&self.aggregate_id) {
                    vec![(Action::TransactionDelete, Resource::Transaction(id))]
                } else {
                    vec![]
                }
            }
            ("transaction", "UNDO") => {
                if let Ok(id) = Uuid::parse_str(&self.aggregate_id) {
                    vec![(Action::TransactionUpdate, Resource::Transaction(id))]
                } else {
                    vec![]
                }
            }
            _ => vec![],
        }
    }

    /// Convert SyncEventRequest to strongly-typed DomainEvent
    pub fn to_domain_event(
        &self,
        wallet_id: Uuid,
        user_id: Uuid,
        created_at: DateTime<Utc>,
    ) -> Result<DomainEvent, String> {
        let id = Uuid::parse_str(&self.id).map_err(|_| "Invalid event ID UUID".to_string())?;
        let aggregate_id = Uuid::parse_str(&self.aggregate_id)
            .map_err(|_| "Invalid aggregate ID UUID".to_string())?;

        let event_data = match (self.aggregate_type.as_str(), self.event_type.as_str()) {
            ("contact", "CREATED") => {
                let name = self
                    .event_data
                    .get("name")
                    .and_then(|v| v.as_str())
                    .ok_or_else(|| "CREATED contact requires 'name'".to_string())?
                    .to_string();

                EventData::ContactCreated {
                    name,
                    username: self
                        .event_data
                        .get("username")
                        .and_then(|v| v.as_str())
                        .map(|s| s.to_string()),
                    phone: self
                        .event_data
                        .get("phone")
                        .and_then(|v| v.as_str())
                        .map(|s| s.to_string()),
                    email: self
                        .event_data
                        .get("email")
                        .and_then(|v| v.as_str())
                        .map(|s| s.to_string()),
                    notes: self
                        .event_data
                        .get("notes")
                        .and_then(|v| v.as_str())
                        .map(|s| s.to_string()),
                }
            }
            ("contact", "UPDATED") => EventData::ContactUpdated {
                name: self
                    .event_data
                    .get("name")
                    .and_then(|v| v.as_str())
                    .map(|s| s.to_string()),
                username: self
                    .event_data
                    .get("username")
                    .and_then(|v| v.as_str())
                    .map(|s| s.to_string()),
                phone: self
                    .event_data
                    .get("phone")
                    .and_then(|v| v.as_str())
                    .map(|s| s.to_string()),
                email: self
                    .event_data
                    .get("email")
                    .and_then(|v| v.as_str())
                    .map(|s| s.to_string()),
                notes: self
                    .event_data
                    .get("notes")
                    .and_then(|v| v.as_str())
                    .map(|s| s.to_string()),
            },
            ("contact", "DELETED") => EventData::ContactDeleted {
                comment: self
                    .event_data
                    .get("comment")
                    .and_then(|v| v.as_str())
                    .map(|s| s.to_string()),
            },
            ("contact", "UNDO") => {
                let undone_event_id = self
                    .event_data
                    .get("undone_event_id")
                    .and_then(|v| v.as_str())
                    .ok_or_else(|| "UNDO event requires 'undone_event_id'".to_string())?;
                // Validate UUID format
                Uuid::parse_str(undone_event_id)
                    .map_err(|_| "UNDO event 'undone_event_id' must be a valid UUID".to_string())?;
                EventData::ContactUndone { undone_event_id: undone_event_id.to_string() }
            }
            ("transaction", "CREATED") => {
                let contact_id = self
                    .event_data
                    .get("contact_id")
                    .and_then(|v| v.as_str())
                    .ok_or_else(|| "CREATED transaction requires 'contact_id'".to_string())?
                    .to_string();
                let amount = self
                    .event_data
                    .get("amount")
                    .and_then(|v| v.as_i64())
                    .ok_or_else(|| "CREATED transaction requires 'amount'".to_string())?;
                let direction = self
                    .event_data
                    .get("direction")
                    .and_then(|v| v.as_str())
                    .ok_or_else(|| "CREATED transaction requires 'direction'".to_string())?
                    .to_string();

                EventData::TransactionCreated {
                    contact_id,
                    amount,
                    direction,
                    transaction_type: self
                        .event_data
                        .get("transaction_type")
                        .and_then(|v| v.as_str())
                        .map(|s| s.to_string()),
                    currency: self
                        .event_data
                        .get("currency")
                        .and_then(|v| v.as_str())
                        .map(|s| s.to_string()),
                    description: self
                        .event_data
                        .get("description")
                        .and_then(|v| v.as_str())
                        .map(|s| s.to_string()),
                    transaction_date: self
                        .event_data
                        .get("transaction_date")
                        .and_then(|v| v.as_str())
                        .map(|s| s.to_string()),
                    due_date: self
                        .event_data
                        .get("due_date")
                        .and_then(|v| v.as_str())
                        .map(|s| s.to_string()),
                }
            }
            ("transaction", "UPDATED") => EventData::TransactionUpdated {
                contact_id: self
                    .event_data
                    .get("contact_id")
                    .and_then(|v| v.as_str())
                    .map(|s| s.to_string()),
                amount: self.event_data.get("amount").and_then(|v| v.as_i64()),
                direction: self
                    .event_data
                    .get("direction")
                    .and_then(|v| v.as_str())
                    .map(|s| s.to_string()),
                transaction_type: self
                    .event_data
                    .get("transaction_type")
                    .and_then(|v| v.as_str())
                    .map(|s| s.to_string()),
                currency: self
                    .event_data
                    .get("currency")
                    .and_then(|v| v.as_str())
                    .map(|s| s.to_string()),
                description: self
                    .event_data
                    .get("description")
                    .and_then(|v| v.as_str())
                    .map(|s| s.to_string()),
                transaction_date: self
                    .event_data
                    .get("transaction_date")
                    .and_then(|v| v.as_str())
                    .map(|s| s.to_string()),
                due_date: self
                    .event_data
                    .get("due_date")
                    .and_then(|v| v.as_str())
                    .map(|s| s.to_string()),
            },
            ("transaction", "DELETED") => EventData::TransactionDeleted {
                comment: self
                    .event_data
                    .get("comment")
                    .and_then(|v| v.as_str())
                    .map(|s| s.to_string()),
            },
            ("transaction", "UNDO") => {
                let undone_event_id = self
                    .event_data
                    .get("undone_event_id")
                    .and_then(|v| v.as_str())
                    .ok_or_else(|| "UNDO event requires 'undone_event_id'".to_string())?;
                // Validate UUID format
                Uuid::parse_str(undone_event_id)
                    .map_err(|_| "UNDO event 'undone_event_id' must be a valid UUID".to_string())?;
                EventData::TransactionUndone { undone_event_id: undone_event_id.to_string() }
            }
            ("permission", "WALLET_USER_ADDED") => EventData::WalletUserAdded {
                data: self.event_data.clone(),
            },
            ("permission", "WALLET_USER_ROLE_CHANGED") => EventData::WalletUserRoleChanged {
                data: self.event_data.clone(),
            },
            ("permission", "WALLET_USER_REMOVED") => EventData::WalletUserRemoved {
                data: self.event_data.clone(),
            },
            ("permission", "USER_GROUP_CREATED") => EventData::UserGroupCreated {
                data: self.event_data.clone(),
            },
            ("permission", "USER_GROUP_UPDATED") => EventData::UserGroupUpdated {
                data: self.event_data.clone(),
            },
            ("permission", "USER_GROUP_DELETED") => EventData::UserGroupDeleted {
                data: self.event_data.clone(),
            },
            ("permission", "USER_GROUP_MEMBER_ADDED") => EventData::UserGroupMemberAdded {
                data: self.event_data.clone(),
            },
            ("permission", "USER_GROUP_MEMBER_REMOVED") => EventData::UserGroupMemberRemoved {
                data: self.event_data.clone(),
            },
            ("permission", "CONTACT_GROUP_CREATED") => EventData::ContactGroupCreated {
                data: self.event_data.clone(),
            },
            ("permission", "CONTACT_GROUP_UPDATED") => EventData::ContactGroupUpdated {
                data: self.event_data.clone(),
            },
            ("permission", "CONTACT_GROUP_DELETED") => EventData::ContactGroupDeleted {
                data: self.event_data.clone(),
            },
            ("permission", "CONTACT_GROUP_MEMBER_ADDED") => EventData::ContactGroupMemberAdded {
                data: self.event_data.clone(),
            },
            ("permission", "CONTACT_GROUP_MEMBER_REMOVED") => EventData::ContactGroupMemberRemoved {
                data: self.event_data.clone(),
            },
            ("permission", "PERMISSION_MATRIX_SET") => EventData::PermissionMatrixSet {
                data: self.event_data.clone(),
            },
            _ => {
                return Err(format!(
                    "Unknown event type: {}/{}",
                    self.aggregate_type, self.event_type
                ))
            }
        };

        Ok(DomainEvent {
            id,
            aggregate_id,
            wallet_id,
            user_id,
            created_at,
            version: self.version,
            idempotency_key: self
                .event_data
                .get("idempotency_key")
                .and_then(|v| v.as_str())
                .map(|s| s.to_string()),
            event_data,
        })
    }
}
