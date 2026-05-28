use uuid::Uuid;
use chrono::NaiveDate;
use std::collections::HashMap;
use crate::database::models::*;
use crate::database::error::DbError;
use crate::database::repository::Database;

impl Database {
    pub async fn get_transactions_for_wallet_impl(&self, wallet_id: Uuid) -> Result<Vec<Transaction>, DbError> {
        todo!("Extract from handlers")
    }

    pub async fn get_transaction_impl(&self, transaction_id: Uuid, wallet_id: Uuid) -> Result<Option<Transaction>, DbError> {
        todo!("Extract from handlers")
    }

    pub async fn insert_transaction_impl(
        &self,
        id: Uuid,
        from_contact_id: Uuid,
        to_contact_id: Uuid,
        amount: i64,
        description: Option<String>,
        wallet_id: Uuid,
        due_date: Option<NaiveDate>,
    ) -> Result<(), DbError> {
        todo!("Extract from sync.rs")
    }

    pub async fn update_transaction_impl(
        &self,
        transaction_id: Uuid,
        wallet_id: Uuid,
        from_contact_id: Option<Uuid>,
        to_contact_id: Option<Uuid>,
        amount: Option<i64>,
        description: Option<String>,
        due_date: Option<NaiveDate>,
    ) -> Result<bool, DbError> {
        todo!("Extract from sync.rs")
    }

    pub async fn delete_transaction_impl(&self, transaction_id: Uuid, wallet_id: Uuid) -> Result<bool, DbError> {
        todo!("Extract from sync.rs")
    }

    pub async fn get_transaction_projection_impl(
        &self,
        transaction_id: Uuid,
        wallet_id: Uuid,
    ) -> Result<Option<TransactionProjection>, DbError> {
        todo!("Extract from handlers")
    }

    pub async fn calculate_total_debt_impl(&self, wallet_id: Uuid) -> Result<i64, DbError> {
        todo!("Extract from sync.rs")
    }

    pub async fn get_transaction_contact_ids_impl(
        &self,
        wallet_id: Uuid,
        transaction_ids: &[Uuid],
    ) -> Result<HashMap<Uuid, Uuid>, DbError> {
        todo!("Extract from sync.rs")
    }
}

