use crate::database::error::DbError;
use crate::database::models::*;
use crate::database::repository::Database;
use chrono::NaiveDate;
use sqlx::Row;
use std::collections::HashMap;
use uuid::Uuid;

impl Database {
    pub async fn get_transactions_for_wallet_impl(
        &self,
        wallet_id: Uuid,
    ) -> Result<Vec<Transaction>, DbError> {
        let transactions = sqlx::query_as::<_, Transaction>(
            r#"
            SELECT id, from_contact_id, to_contact_id, amount, description, wallet_id, due_date, created_at, updated_at, version
            FROM transactions_projection
            WHERE wallet_id = $1 AND is_deleted = false
            ORDER BY created_at ASC
            "#
        )
        .bind(wallet_id)
        .fetch_all(&self.pool)
        .await?;

        Ok(transactions)
    }

    pub async fn get_transaction_impl(
        &self,
        transaction_id: Uuid,
        wallet_id: Uuid,
    ) -> Result<Option<Transaction>, DbError> {
        let transaction = sqlx::query_as::<_, Transaction>(
            r#"
            SELECT id, from_contact_id, to_contact_id, amount, description, wallet_id, due_date, created_at, updated_at, version
            FROM transactions_projection
            WHERE id = $1 AND wallet_id = $2 AND is_deleted = false
            "#
        )
        .bind(transaction_id)
        .bind(wallet_id)
        .fetch_optional(&self.pool)
        .await?;

        Ok(transaction)
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
        sqlx::query(
            r#"
            INSERT INTO transactions_projection (id, from_contact_id, to_contact_id, amount, description, wallet_id, due_date, is_deleted, created_at, updated_at, version)
            VALUES ($1, $2, $3, $4, $5, $6, $7, false, NOW(), NOW(), 1)
            ON CONFLICT (id) DO NOTHING
            "#
        )
        .bind(id)
        .bind(from_contact_id)
        .bind(to_contact_id)
        .bind(amount)
        .bind(&description)
        .bind(wallet_id)
        .bind(due_date)
        .execute(&self.pool)
        .await?;

        Ok(())
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
        if from_contact_id.is_none()
            && to_contact_id.is_none()
            && amount.is_none()
            && description.is_none()
            && due_date.is_none()
        {
            return Ok(false);
        }

        let result = sqlx::query(
            r#"
            UPDATE transactions_projection
            SET
                from_contact_id = COALESCE($1, from_contact_id),
                to_contact_id = COALESCE($2, to_contact_id),
                amount = COALESCE($3, amount),
                description = COALESCE($4, description),
                due_date = COALESCE($5, due_date),
                updated_at = NOW(),
                version = version + 1
            WHERE id = $6 AND wallet_id = $7 AND is_deleted = false
            "#,
        )
        .bind(from_contact_id)
        .bind(to_contact_id)
        .bind(amount)
        .bind(&description)
        .bind(due_date)
        .bind(transaction_id)
        .bind(wallet_id)
        .execute(&self.pool)
        .await?;

        Ok(result.rows_affected() > 0)
    }

    pub async fn delete_transaction_impl(
        &self,
        transaction_id: Uuid,
        wallet_id: Uuid,
    ) -> Result<bool, DbError> {
        let result = sqlx::query("UPDATE transactions_projection SET is_deleted = true, updated_at = NOW(), version = version + 1 WHERE id = $1 AND wallet_id = $2")
            .bind(transaction_id)
            .bind(wallet_id)
            .execute(&self.pool)
            .await?;

        Ok(result.rows_affected() > 0)
    }

    pub async fn get_transaction_projection_impl(
        &self,
        transaction_id: Uuid,
        wallet_id: Uuid,
    ) -> Result<Option<TransactionProjection>, DbError> {
        let projection = sqlx::query_as::<_, TransactionProjection>(
            r#"
            SELECT id, from_contact_id, to_contact_id, amount, description, wallet_id, due_date, created_at, updated_at, version
            FROM transactions_projection
            WHERE id = $1 AND wallet_id = $2 AND is_deleted = false
            "#
        )
        .bind(transaction_id)
        .bind(wallet_id)
        .fetch_optional(&self.pool)
        .await?;

        Ok(projection)
    }

    pub async fn calculate_total_debt_impl(&self, wallet_id: Uuid) -> Result<i64, DbError> {
        // Signed sum by direction: 'owed' (contact owes the user) is +,
        // 'lent' (user owes the contact) is -. A wallet with one
        // give-1000 and one receive-1000 nets to 0. Same convention is
        // used in the SDK's per-contact balance + total_debt (see
        // client/src/storage.rs and client/src/crud.rs).
        let debt = sqlx::query_scalar::<_, i64>(
            r#"
            SELECT COALESCE(SUM(
                CASE direction
                    WHEN 'owed' THEN  amount
                    WHEN 'lent' THEN -amount
                    ELSE              amount
                END
            ), 0)
            FROM transactions_projection
            WHERE wallet_id = $1 AND is_deleted = false
            "#,
        )
        .bind(wallet_id)
        .fetch_one(&self.pool)
        .await?;

        Ok(debt)
    }

    pub async fn get_transaction_contact_ids_impl(
        &self,
        wallet_id: Uuid,
        transaction_ids: &[Uuid],
    ) -> Result<HashMap<Uuid, Uuid>, DbError> {
        if transaction_ids.is_empty() {
            return Ok(HashMap::new());
        }

        let rows = sqlx::query(
            "SELECT id, from_contact_id FROM transactions_projection WHERE wallet_id = $1 AND id = ANY($2)"
        )
        .bind(wallet_id)
        .bind(transaction_ids)
        .fetch_all(&self.pool)
        .await?;

        let map = rows
            .iter()
            .map(|r| {
                let id: Uuid = r.get("id");
                let contact_id: Uuid = r.get("from_contact_id");
                (id, contact_id)
            })
            .collect();

        Ok(map)
    }
}
