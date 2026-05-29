use uuid::Uuid;
use serde_json::Value;
use sqlx::Row;
use chrono::NaiveDateTime;
use crate::database::error::DbError;
use crate::database::repository::Database;

#[derive(Debug, Clone)]
pub struct TransactionWithoutEvent {
    pub id: Uuid,
    pub user_id: Uuid,
    pub contact_id: Uuid,
    pub txn_type: String,
    pub direction: String,
    pub amount: i64,
    pub currency: Option<String>,
    pub description: Option<String>,
    pub transaction_date: chrono::NaiveDate,
    pub due_date: Option<chrono::NaiveDate>,
    pub created_at: NaiveDateTime,
}

impl Database {
    pub async fn get_all_contacts_group_impl(&self, wallet_id: Uuid) -> Result<Option<Uuid>, DbError> {
        let group_id = sqlx::query_scalar::<_, Uuid>(
            r#"
            SELECT id FROM contact_groups
            WHERE wallet_id = $1 AND name = 'all_contacts'
            LIMIT 1
            "#
        )
        .bind(wallet_id)
        .fetch_optional(&self.pool)
        .await?;

        Ok(group_id)
    }

    pub async fn count_events_impl(&self, wallet_id: Uuid) -> Result<i64, DbError> {
        let count = sqlx::query_scalar::<_, i64>(
            "SELECT COUNT(*) FROM events WHERE wallet_id = $1"
        )
        .bind(wallet_id)
        .fetch_one(&self.pool)
        .await?;

        Ok(count)
    }

    pub async fn clear_projections_impl(&self, wallet_id: Uuid) -> Result<(), DbError> {
        sqlx::query("DELETE FROM contacts_projection WHERE wallet_id = $1")
            .bind(wallet_id)
            .execute(&self.pool)
            .await?;

        sqlx::query("DELETE FROM transactions_projection WHERE wallet_id = $1")
            .bind(wallet_id)
            .execute(&self.pool)
            .await?;

        Ok(())
    }

    pub async fn get_first_user_id_impl(&self) -> Result<Option<Uuid>, DbError> {
        let id = sqlx::query_scalar::<_, Uuid>(
            "SELECT id FROM users_projection LIMIT 1"
        )
        .fetch_optional(&self.pool)
        .await?;

        Ok(id)
    }

    pub async fn get_transactions_without_events_impl(&self) -> Result<Vec<TransactionWithoutEvent>, DbError> {
        let rows = sqlx::query(
            r#"
            SELECT t.id, t.user_id, t.contact_id, t.type, t.direction, t.amount,
                   t.currency, t.description, t.transaction_date, t.due_date, t.created_at
            FROM transactions_projection t
            WHERE t.is_deleted = false
            AND NOT EXISTS (
                SELECT 1 FROM events e
                WHERE e.aggregate_type = 'transaction'
                AND e.aggregate_id = t.id
                AND e.event_type = 'TRANSACTION_CREATED'
            )
            ORDER BY t.created_at
            "#
        )
        .fetch_all(&self.pool)
        .await?;

        let transactions = rows.iter().map(|row| {
            TransactionWithoutEvent {
                id: row.get("id"),
                user_id: row.get("user_id"),
                contact_id: row.get("contact_id"),
                txn_type: row.get("type"),
                direction: row.get("direction"),
                amount: row.get("amount"),
                currency: row.get("currency"),
                description: row.get("description"),
                transaction_date: row.get("transaction_date"),
                due_date: row.get("due_date"),
                created_at: row.get("created_at"),
            }
        }).collect();

        Ok(transactions)
    }

    pub async fn insert_backfill_event_impl(
        &self,
        user_id: Uuid,
        transaction_id: Uuid,
        event_data: Value,
        created_at: NaiveDateTime,
    ) -> Result<i64, DbError> {
        let event_id = sqlx::query_scalar::<_, i64>(
            r#"
            INSERT INTO events (user_id, aggregate_type, aggregate_id, event_type, event_version, event_data, created_at)
            VALUES ($1, 'transaction', $2, 'TRANSACTION_CREATED', 1, $3, $4)
            RETURNING id
            "#
        )
        .bind(user_id)
        .bind(transaction_id)
        .bind(&event_data)
        .bind(created_at)
        .fetch_one(&self.pool)
        .await?;

        Ok(event_id)
    }

    pub async fn update_transaction_last_event_id_impl(&self, transaction_id: Uuid, event_id: i64) -> Result<(), DbError> {
        sqlx::query(
            r#"
            UPDATE transactions_projection
            SET last_event_id = $1
            WHERE id = $2
            "#
        )
        .bind(event_id)
        .bind(transaction_id)
        .execute(&self.pool)
        .await?;

        Ok(())
    }

    pub async fn get_total_debt_for_wallet_impl(&self, wallet_id: Uuid) -> Result<i64, DbError> {
        let result: Option<String> = sqlx::query_scalar(
            r#"
            SELECT event_data->>'total_debt'
            FROM events
            WHERE event_data->>'total_debt' IS NOT NULL
              AND wallet_id = $1
            ORDER BY created_at DESC, id DESC
            LIMIT 1
            "#
        )
        .bind(wallet_id)
        .fetch_optional(&self.pool)
        .await?;

        if let Some(debt_str) = result {
            Ok(debt_str.parse::<i64>().unwrap_or_else(|_| {
                serde_json::from_str::<i64>(&debt_str).unwrap_or(0)
            }))
        } else {
            let total = sqlx::query_scalar::<_, i64>(
                r#"
                SELECT COALESCE(SUM(
                    CASE
                        WHEN t.direction = 'lent' THEN t.amount
                        WHEN t.direction = 'owed' THEN -t.amount
                        ELSE 0
                    END
                )::BIGINT, 0)
                FROM contacts_projection c
                LEFT JOIN transactions_projection t ON t.contact_id = c.id AND t.is_deleted = false AND t.wallet_id = c.wallet_id
                WHERE c.is_deleted = false AND c.wallet_id = $1
                "#
            )
            .bind(wallet_id)
            .fetch_one(&self.pool)
            .await?;
            Ok(total)
        }
    }

    pub async fn get_total_debt_all_wallets_impl(&self) -> Result<i64, DbError> {
        let total = sqlx::query_scalar::<_, i64>(
            r#"
            SELECT COALESCE(SUM(
                CASE
                    WHEN t.direction = 'lent' THEN t.amount
                    WHEN t.direction = 'owed' THEN -t.amount
                    ELSE 0
                END
            )::BIGINT, 0)
            FROM contacts_projection c
            LEFT JOIN transactions_projection t ON t.contact_id = c.id AND t.is_deleted = false AND t.wallet_id = c.wallet_id
            WHERE c.is_deleted = false
            "#
        )
        .fetch_one(&self.pool)
        .await?;

        Ok(total)
    }
}

