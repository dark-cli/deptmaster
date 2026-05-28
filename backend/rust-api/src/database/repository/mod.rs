pub mod events;
pub mod contacts;
pub mod transactions;
pub mod wallets;
pub mod permissions;
pub mod users;
pub mod snapshots;
pub mod utility;

use async_trait::async_trait;
use uuid::Uuid;
use chrono::{DateTime, Utc, NaiveDate};
use serde_json::Value;
use crate::database::models::*;
use crate::database::error::DbError;
use sqlx::PgPool;

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
        due_date: Option<NaiveDate>,
    ) -> Result<(), DbError>;

    async fn update_transaction(
        &self,
        transaction_id: Uuid,
        wallet_id: Uuid,
        from_contact_id: Option<Uuid>,
        to_contact_id: Option<Uuid>,
        amount: Option<i64>,
        description: Option<String>,
        due_date: Option<NaiveDate>,
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

    pub fn pool(&self) -> &PgPool {
        &self.pool
    }
}

#[async_trait]
impl DatabaseRepository for Database {
    async fn get_events_since(&self, wallet_id: Uuid, since_timestamp: DateTime<Utc>) -> Result<Vec<EventRow>, DbError> {
        self.get_events_since_impl(wallet_id, since_timestamp).await
    }

    async fn get_event_by_id(&self, event_id: Uuid) -> Result<Option<EventRow>, DbError> {
        self.get_event_by_id_impl(event_id).await
    }

    async fn insert_event(&self, event_id: Uuid, aggregate_id: Uuid, aggregate_type: String, event_type: String, data: Value, wallet_id: Uuid, user_id: Uuid, version: i32, idempotency_key: Option<String>) -> Result<i64, DbError> {
        self.insert_event_impl(event_id, aggregate_id, aggregate_type, event_type, data, wallet_id, user_id, version, idempotency_key).await
    }

    async fn delete_event(&self, event_id: Uuid) -> Result<bool, DbError> {
        self.delete_event_impl(event_id).await
    }

    async fn get_hash_for_sync(&self, wallet_id: Uuid) -> Result<(String, i64), DbError> {
        self.get_hash_for_sync_impl(wallet_id).await
    }

    async fn get_contacts_for_wallet(&self, wallet_id: Uuid) -> Result<Vec<Contact>, DbError> {
        self.get_contacts_for_wallet_impl(wallet_id).await
    }

    async fn get_contact(&self, contact_id: Uuid, wallet_id: Uuid) -> Result<Option<Contact>, DbError> {
        self.get_contact_impl(contact_id, wallet_id).await
    }

    async fn insert_contact(&self, id: Uuid, name: String, phone: Option<String>, wallet_id: Uuid) -> Result<(), DbError> {
        self.insert_contact_impl(id, name, phone, wallet_id).await
    }

    async fn update_contact(&self, contact_id: Uuid, wallet_id: Uuid, name: Option<String>, phone: Option<String>) -> Result<bool, DbError> {
        self.update_contact_impl(contact_id, wallet_id, name, phone).await
    }

    async fn delete_contact(&self, contact_id: Uuid, wallet_id: Uuid) -> Result<bool, DbError> {
        self.delete_contact_impl(contact_id, wallet_id).await
    }

    async fn get_contact_projection(&self, contact_id: Uuid, wallet_id: Uuid) -> Result<Option<ContactProjection>, DbError> {
        self.get_contact_projection_impl(contact_id, wallet_id).await
    }

    async fn get_transactions_for_wallet(&self, wallet_id: Uuid) -> Result<Vec<Transaction>, DbError> {
        self.get_transactions_for_wallet_impl(wallet_id).await
    }

    async fn get_transaction(&self, transaction_id: Uuid, wallet_id: Uuid) -> Result<Option<Transaction>, DbError> {
        self.get_transaction_impl(transaction_id, wallet_id).await
    }

    async fn insert_transaction(&self, id: Uuid, from_contact_id: Uuid, to_contact_id: Uuid, amount: i64, description: Option<String>, wallet_id: Uuid, due_date: Option<NaiveDate>) -> Result<(), DbError> {
        self.insert_transaction_impl(id, from_contact_id, to_contact_id, amount, description, wallet_id, due_date).await
    }

    async fn update_transaction(&self, transaction_id: Uuid, wallet_id: Uuid, from_contact_id: Option<Uuid>, to_contact_id: Option<Uuid>, amount: Option<i64>, description: Option<String>, due_date: Option<NaiveDate>) -> Result<bool, DbError> {
        self.update_transaction_impl(transaction_id, wallet_id, from_contact_id, to_contact_id, amount, description, due_date).await
    }

    async fn delete_transaction(&self, transaction_id: Uuid, wallet_id: Uuid) -> Result<bool, DbError> {
        self.delete_transaction_impl(transaction_id, wallet_id).await
    }

    async fn get_transaction_projection(&self, transaction_id: Uuid, wallet_id: Uuid) -> Result<Option<TransactionProjection>, DbError> {
        self.get_transaction_projection_impl(transaction_id, wallet_id).await
    }

    async fn calculate_total_debt(&self, wallet_id: Uuid) -> Result<i64, DbError> {
        self.calculate_total_debt_impl(wallet_id).await
    }

    async fn get_transaction_contact_ids(&self, wallet_id: Uuid, transaction_ids: &[Uuid]) -> Result<std::collections::HashMap<Uuid, Uuid>, DbError> {
        self.get_transaction_contact_ids_impl(wallet_id, transaction_ids).await
    }

    async fn get_wallet(&self, wallet_id: Uuid) -> Result<Option<Wallet>, DbError> {
        self.get_wallet_impl(wallet_id).await
    }

    async fn create_wallet(&self, id: Uuid, name: String) -> Result<(), DbError> {
        self.create_wallet_impl(id, name).await
    }

    async fn get_user_wallets(&self, user_id: Uuid) -> Result<Vec<Wallet>, DbError> {
        self.get_user_wallets_impl(user_id).await
    }

    async fn list_wallet_users(&self, wallet_id: Uuid) -> Result<Vec<WalletUser>, DbError> {
        self.list_wallet_users_impl(wallet_id).await
    }

    async fn add_wallet_user(&self, wallet_id: Uuid, user_id: Uuid, role: String) -> Result<(), DbError> {
        self.add_wallet_user_impl(wallet_id, user_id, role).await
    }

    async fn update_wallet_user_role(&self, wallet_id: Uuid, user_id: Uuid, role: String) -> Result<bool, DbError> {
        self.update_wallet_user_role_impl(wallet_id, user_id, role).await
    }

    async fn get_user_groups(&self, wallet_id: Uuid) -> Result<Vec<UserGroup>, DbError> {
        self.get_user_groups_impl(wallet_id).await
    }

    async fn get_contact_groups(&self, wallet_id: Uuid) -> Result<Vec<ContactGroup>, DbError> {
        self.get_contact_groups_impl(wallet_id).await
    }

    async fn get_user_group_ids(&self, wallet_id: Uuid, user_id: Uuid) -> Result<Vec<Uuid>, DbError> {
        self.get_user_group_ids_impl(wallet_id, user_id).await
    }

    async fn get_contact_group_ids(&self, wallet_id: Uuid, contact_id: Uuid) -> Result<Vec<Uuid>, DbError> {
        self.get_contact_group_ids_impl(wallet_id, contact_id).await
    }

    async fn get_group_permission_matrix(&self, wallet_id: Uuid, user_group_id: Uuid, contact_group_id: Uuid) -> Result<Vec<String>, DbError> {
        self.get_group_permission_matrix_impl(wallet_id, user_group_id, contact_group_id).await
    }

    async fn sync_contact_group_members(&self, wallet_id: Uuid, contact_id: Uuid, group_ids: Vec<Uuid>) -> Result<(), DbError> {
        self.sync_contact_group_members_impl(wallet_id, contact_id, group_ids).await
    }

    async fn get_user_by_email(&self, email: &str) -> Result<Option<User>, DbError> {
        self.get_user_by_email_impl(email).await
    }

    async fn get_user_by_id(&self, user_id: Uuid) -> Result<Option<User>, DbError> {
        self.get_user_by_id_impl(user_id).await
    }

    async fn create_user(&self, id: Uuid, email: String, password_hash: String) -> Result<(), DbError> {
        self.create_user_impl(id, email, password_hash).await
    }

    async fn update_user_password(&self, user_id: Uuid, password_hash: String) -> Result<bool, DbError> {
        self.update_user_password_impl(user_id, password_hash).await
    }

    async fn get_user_settings(&self, user_id: Uuid, wallet_id: Uuid) -> Result<Option<UserSettings>, DbError> {
        self.get_user_settings_impl(user_id, wallet_id).await
    }

    async fn set_default_groups(&self, user_id: Uuid, wallet_id: Uuid, contact_group_id: Option<Uuid>, transaction_group_id: Option<Uuid>) -> Result<(), DbError> {
        self.set_default_groups_impl(user_id, wallet_id, contact_group_id, transaction_group_id).await
    }

    async fn create_projection_snapshot(&self, wallet_id: Uuid, contacts_data: Value, transactions_data: Value) -> Result<(), DbError> {
        self.create_projection_snapshot_impl(wallet_id, contacts_data, transactions_data).await
    }

    async fn get_latest_snapshot(&self, wallet_id: Uuid) -> Result<Option<(Value, Value, DateTime<Utc>)>, DbError> {
        self.get_latest_snapshot_impl(wallet_id).await
    }

    async fn delete_old_snapshots(&self, wallet_id: Uuid, keep_count: i64) -> Result<(), DbError> {
        self.delete_old_snapshots_impl(wallet_id, keep_count).await
    }

    async fn get_all_contacts_group(&self, wallet_id: Uuid) -> Result<Option<Uuid>, DbError> {
        self.get_all_contacts_group_impl(wallet_id).await
    }

    async fn count_events(&self, wallet_id: Uuid) -> Result<i64, DbError> {
        self.count_events_impl(wallet_id).await
    }

    async fn clear_projections(&self, wallet_id: Uuid) -> Result<(), DbError> {
        self.clear_projections_impl(wallet_id).await
    }
}
