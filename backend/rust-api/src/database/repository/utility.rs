use uuid::Uuid;
use crate::database::error::DbError;
use crate::database::repository::Database;

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
        // Delete all projection data for a wallet
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
}

