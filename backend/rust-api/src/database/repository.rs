use async_trait::async_trait;
use sqlx::PgPool;
use uuid::Uuid;
use chrono::{DateTime, Utc};
use serde_json::{json, Value};
use crate::database::models::*;
use crate::database::error::DbError;

#[async_trait]
pub trait DatabaseRepository: Send + Sync {
    // ============ EVENTS ============
    async fn get_events_since(
        &self,
        wallet_id: Uuid,
        since_timestamp: DateTime<Utc>,
    ) -> Result<Vec<EventRow>, DbError>;

    async fn get_event_by_id(&self, event_id: Uuid) -> Result<Option<EventRow>, DbError>;

    async fn insert_event(
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
    ) -> Result<i64, DbError>;

    async fn delete_event(&self, event_id: Uuid) -> Result<bool, DbError>;

    async fn get_hash_for_sync(&self, wallet_id: Uuid) -> Result<(String, i64), DbError>;

    // ============ CONTACTS ============
    async fn get_contacts_for_wallet(&self, wallet_id: Uuid) -> Result<Vec<Contact>, DbError>;

    async fn get_contact(&self, contact_id: Uuid, wallet_id: Uuid) -> Result<Option<Contact>, DbError>;

    async fn insert_contact(
        &self,
        id: Uuid,
        name: String,
        phone: Option<String>,
        wallet_id: Uuid,
    ) -> Result<(), DbError>;

    async fn update_contact(
        &self,
        contact_id: Uuid,
        wallet_id: Uuid,
        name: Option<String>,
        phone: Option<String>,
    ) -> Result<bool, DbError>;

    async fn delete_contact(&self, contact_id: Uuid, wallet_id: Uuid) -> Result<bool, DbError>;

    async fn get_contact_projection(
        &self,
        contact_id: Uuid,
        wallet_id: Uuid,
    ) -> Result<Option<ContactProjection>, DbError>;

    // ============ TRANSACTIONS ============
    async fn get_transactions_for_wallet(&self, wallet_id: Uuid) -> Result<Vec<Transaction>, DbError>;

    async fn get_transaction(
        &self,
        transaction_id: Uuid,
        wallet_id: Uuid,
    ) -> Result<Option<Transaction>, DbError>;

    async fn insert_transaction(
        &self,
        id: Uuid,
        from_contact_id: Uuid,
        to_contact_id: Uuid,
        amount: i64,
        description: Option<String>,
        wallet_id: Uuid,
        due_date: Option<chrono::NaiveDate>,
    ) -> Result<(), DbError>;

    async fn update_transaction(
        &self,
        transaction_id: Uuid,
        wallet_id: Uuid,
        from_contact_id: Option<Uuid>,
        to_contact_id: Option<Uuid>,
        amount: Option<i64>,
        description: Option<String>,
        due_date: Option<chrono::NaiveDate>,
    ) -> Result<bool, DbError>;

    async fn delete_transaction(&self, transaction_id: Uuid, wallet_id: Uuid) -> Result<bool, DbError>;

    async fn get_transaction_projection(
        &self,
        transaction_id: Uuid,
        wallet_id: Uuid,
    ) -> Result<Option<TransactionProjection>, DbError>;

    async fn calculate_total_debt(&self, wallet_id: Uuid) -> Result<i64, DbError>;

    async fn get_transaction_contact_ids(
        &self,
        wallet_id: Uuid,
        transaction_ids: &[Uuid],
    ) -> Result<std::collections::HashMap<Uuid, Uuid>, DbError>;

    // ============ WALLETS ============
    async fn get_wallet(&self, wallet_id: Uuid) -> Result<Option<Wallet>, DbError>;

    async fn create_wallet(&self, id: Uuid, name: String) -> Result<(), DbError>;

    async fn get_user_wallets(&self, user_id: Uuid) -> Result<Vec<Wallet>, DbError>;

    async fn list_wallet_users(&self, wallet_id: Uuid) -> Result<Vec<WalletUser>, DbError>;

    async fn add_wallet_user(
        &self,
        wallet_id: Uuid,
        user_id: Uuid,
        role: String,
    ) -> Result<(), DbError>;

    async fn update_wallet_user_role(
        &self,
        wallet_id: Uuid,
        user_id: Uuid,
        role: String,
    ) -> Result<bool, DbError>;

    // ============ PERMISSIONS ============
    async fn get_user_groups(&self, wallet_id: Uuid) -> Result<Vec<UserGroup>, DbError>;

    async fn get_contact_groups(&self, wallet_id: Uuid) -> Result<Vec<ContactGroup>, DbError>;

    async fn get_user_group_ids(&self, wallet_id: Uuid, user_id: Uuid) -> Result<Vec<Uuid>, DbError>;

    async fn get_contact_group_ids(&self, wallet_id: Uuid, contact_id: Uuid) -> Result<Vec<Uuid>, DbError>;

    async fn get_group_permission_matrix(
        &self,
        wallet_id: Uuid,
        user_group_id: Uuid,
        contact_group_id: Uuid,
    ) -> Result<Vec<String>, DbError>;

    async fn sync_contact_group_members(
        &self,
        wallet_id: Uuid,
        contact_id: Uuid,
        group_ids: Vec<Uuid>,
    ) -> Result<(), DbError>;

    // ============ USERS ============
    async fn get_user_by_email(&self, email: &str) -> Result<Option<User>, DbError>;

    async fn get_user_by_id(&self, user_id: Uuid) -> Result<Option<User>, DbError>;

    async fn create_user(
        &self,
        id: Uuid,
        email: String,
        password_hash: String,
    ) -> Result<(), DbError>;

    async fn update_user_password(&self, user_id: Uuid, password_hash: String) -> Result<bool, DbError>;

    async fn get_user_settings(
        &self,
        user_id: Uuid,
        wallet_id: Uuid,
    ) -> Result<Option<UserSettings>, DbError>;

    async fn set_default_groups(
        &self,
        user_id: Uuid,
        wallet_id: Uuid,
        contact_group_id: Option<Uuid>,
        transaction_group_id: Option<Uuid>,
    ) -> Result<(), DbError>;

    // ============ SNAPSHOTS ============
    async fn create_projection_snapshot(
        &self,
        wallet_id: Uuid,
        contacts_data: Value,
        transactions_data: Value,
    ) -> Result<(), DbError>;

    async fn get_latest_snapshot(
        &self,
        wallet_id: Uuid,
    ) -> Result<Option<(Value, Value, DateTime<Utc>)>, DbError>;

    async fn delete_old_snapshots(&self, wallet_id: Uuid, keep_count: i64) -> Result<(), DbError>;

    // ============ UTILITY ============
    async fn get_all_contacts_group(&self, wallet_id: Uuid) -> Result<Option<Uuid>, DbError>;

    async fn count_events(&self, wallet_id: Uuid) -> Result<i64, DbError>;

    async fn clear_projections(&self, wallet_id: Uuid) -> Result<(), DbError>;
}

pub struct Database {
    pool: PgPool,
}

impl Database {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }
}

#[async_trait]
impl DatabaseRepository for Database {
    // TODO: Implement all trait methods in Phase 3-4
    // Start with queries extracted from handlers

    async fn get_events_since(
        &self,
        wallet_id: Uuid,
        since_timestamp: DateTime<Utc>,
    ) -> Result<Vec<EventRow>, DbError> {
        todo!()
    }

    async fn get_event_by_id(&self, event_id: Uuid) -> Result<Option<EventRow>, DbError> {
        todo!()
    }

    async fn insert_event(
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
        todo!()
    }

    async fn delete_event(&self, event_id: Uuid) -> Result<bool, DbError> {
        todo!()
    }

    async fn get_hash_for_sync(&self, wallet_id: Uuid) -> Result<(String, i64), DbError> {
        todo!()
    }

    async fn get_contacts_for_wallet(&self, wallet_id: Uuid) -> Result<Vec<Contact>, DbError> {
        todo!()
    }

    async fn get_contact(&self, contact_id: Uuid, wallet_id: Uuid) -> Result<Option<Contact>, DbError> {
        todo!()
    }

    async fn insert_contact(
        &self,
        id: Uuid,
        name: String,
        phone: Option<String>,
        wallet_id: Uuid,
    ) -> Result<(), DbError> {
        todo!()
    }

    async fn update_contact(
        &self,
        contact_id: Uuid,
        wallet_id: Uuid,
        name: Option<String>,
        phone: Option<String>,
    ) -> Result<bool, DbError> {
        todo!()
    }

    async fn delete_contact(&self, contact_id: Uuid, wallet_id: Uuid) -> Result<bool, DbError> {
        todo!()
    }

    async fn get_contact_projection(
        &self,
        contact_id: Uuid,
        wallet_id: Uuid,
    ) -> Result<Option<ContactProjection>, DbError> {
        todo!()
    }

    async fn get_transactions_for_wallet(&self, wallet_id: Uuid) -> Result<Vec<Transaction>, DbError> {
        todo!()
    }

    async fn get_transaction(
        &self,
        transaction_id: Uuid,
        wallet_id: Uuid,
    ) -> Result<Option<Transaction>, DbError> {
        todo!()
    }

    async fn insert_transaction(
        &self,
        id: Uuid,
        from_contact_id: Uuid,
        to_contact_id: Uuid,
        amount: i64,
        description: Option<String>,
        wallet_id: Uuid,
        due_date: Option<chrono::NaiveDate>,
    ) -> Result<(), DbError> {
        todo!()
    }

    async fn update_transaction(
        &self,
        transaction_id: Uuid,
        wallet_id: Uuid,
        from_contact_id: Option<Uuid>,
        to_contact_id: Option<Uuid>,
        amount: Option<i64>,
        description: Option<String>,
        due_date: Option<chrono::NaiveDate>,
    ) -> Result<bool, DbError> {
        todo!()
    }

    async fn delete_transaction(&self, transaction_id: Uuid, wallet_id: Uuid) -> Result<bool, DbError> {
        todo!()
    }

    async fn get_transaction_projection(
        &self,
        transaction_id: Uuid,
        wallet_id: Uuid,
    ) -> Result<Option<TransactionProjection>, DbError> {
        todo!()
    }

    async fn calculate_total_debt(&self, wallet_id: Uuid) -> Result<i64, DbError> {
        todo!()
    }

    async fn get_transaction_contact_ids(
        &self,
        wallet_id: Uuid,
        transaction_ids: &[Uuid],
    ) -> Result<std::collections::HashMap<Uuid, Uuid>, DbError> {
        todo!()
    }

    async fn get_wallet(&self, wallet_id: Uuid) -> Result<Option<Wallet>, DbError> {
        todo!()
    }

    async fn create_wallet(&self, id: Uuid, name: String) -> Result<(), DbError> {
        todo!()
    }

    async fn get_user_wallets(&self, user_id: Uuid) -> Result<Vec<Wallet>, DbError> {
        todo!()
    }

    async fn list_wallet_users(&self, wallet_id: Uuid) -> Result<Vec<WalletUser>, DbError> {
        todo!()
    }

    async fn add_wallet_user(
        &self,
        wallet_id: Uuid,
        user_id: Uuid,
        role: String,
    ) -> Result<(), DbError> {
        todo!()
    }

    async fn update_wallet_user_role(
        &self,
        wallet_id: Uuid,
        user_id: Uuid,
        role: String,
    ) -> Result<bool, DbError> {
        todo!()
    }

    async fn get_user_groups(&self, wallet_id: Uuid) -> Result<Vec<UserGroup>, DbError> {
        todo!()
    }

    async fn get_contact_groups(&self, wallet_id: Uuid) -> Result<Vec<ContactGroup>, DbError> {
        todo!()
    }

    async fn get_user_group_ids(&self, wallet_id: Uuid, user_id: Uuid) -> Result<Vec<Uuid>, DbError> {
        todo!()
    }

    async fn get_contact_group_ids(&self, wallet_id: Uuid, contact_id: Uuid) -> Result<Vec<Uuid>, DbError> {
        todo!()
    }

    async fn get_group_permission_matrix(
        &self,
        wallet_id: Uuid,
        user_group_id: Uuid,
        contact_group_id: Uuid,
    ) -> Result<Vec<String>, DbError> {
        todo!()
    }

    async fn sync_contact_group_members(
        &self,
        wallet_id: Uuid,
        contact_id: Uuid,
        group_ids: Vec<Uuid>,
    ) -> Result<(), DbError> {
        todo!()
    }

    async fn get_user_by_email(&self, email: &str) -> Result<Option<User>, DbError> {
        todo!()
    }

    async fn get_user_by_id(&self, user_id: Uuid) -> Result<Option<User>, DbError> {
        todo!()
    }

    async fn create_user(
        &self,
        id: Uuid,
        email: String,
        password_hash: String,
    ) -> Result<(), DbError> {
        todo!()
    }

    async fn update_user_password(&self, user_id: Uuid, password_hash: String) -> Result<bool, DbError> {
        todo!()
    }

    async fn get_user_settings(
        &self,
        user_id: Uuid,
        wallet_id: Uuid,
    ) -> Result<Option<UserSettings>, DbError> {
        todo!()
    }

    async fn set_default_groups(
        &self,
        user_id: Uuid,
        wallet_id: Uuid,
        contact_group_id: Option<Uuid>,
        transaction_group_id: Option<Uuid>,
    ) -> Result<(), DbError> {
        todo!()
    }

    async fn create_projection_snapshot(
        &self,
        wallet_id: Uuid,
        contacts_data: Value,
        transactions_data: Value,
    ) -> Result<(), DbError> {
        todo!()
    }

    async fn get_latest_snapshot(
        &self,
        wallet_id: Uuid,
    ) -> Result<Option<(Value, Value, DateTime<Utc>)>, DbError> {
        todo!()
    }

    async fn delete_old_snapshots(&self, wallet_id: Uuid, keep_count: i64) -> Result<(), DbError> {
        todo!()
    }

    async fn get_all_contacts_group(&self, wallet_id: Uuid) -> Result<Option<Uuid>, DbError> {
        todo!()
    }

    async fn count_events(&self, wallet_id: Uuid) -> Result<i64, DbError> {
        todo!()
    }

    async fn clear_projections(&self, wallet_id: Uuid) -> Result<(), DbError> {
        todo!()
    }
}
