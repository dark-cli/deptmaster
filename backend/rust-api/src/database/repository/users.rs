use uuid::Uuid;
use crate::database::models::*;
use crate::database::error::DbError;
use crate::database::repository::Database;

impl Database {
    pub async fn get_user_by_email_impl(&self, email: &str) -> Result<Option<User>, DbError> {
        let user = sqlx::query_as::<_, User>(
            r#"
            SELECT id, email, username, password_hash, is_admin, created_at, updated_at
            FROM users_projection
            WHERE email = $1
            LIMIT 1
            "#
        )
        .bind(email)
        .fetch_optional(&self.pool)
        .await?;

        Ok(user)
    }

    pub async fn get_user_by_id_impl(&self, user_id: Uuid) -> Result<Option<User>, DbError> {
        let user = sqlx::query_as::<_, User>(
            r#"
            SELECT id, email, username, password_hash, is_admin, created_at, updated_at
            FROM users_projection
            WHERE id = $1
            "#
        )
        .bind(user_id)
        .fetch_optional(&self.pool)
        .await?;

        Ok(user)
    }

    pub async fn create_user_impl(
        &self,
        id: Uuid,
        email: String,
        password_hash: String,
    ) -> Result<(), DbError> {
        sqlx::query(
            r#"
            INSERT INTO users_projection (id, email, password_hash, is_admin, created_at, updated_at)
            VALUES ($1, $2, $3, false, NOW(), NOW())
            ON CONFLICT (id) DO NOTHING
            "#
        )
        .bind(id)
        .bind(&email)
        .bind(&password_hash)
        .execute(&self.pool)
        .await?;

        Ok(())
    }

    pub async fn update_user_password_impl(&self, user_id: Uuid, password_hash: String) -> Result<bool, DbError> {
        let result = sqlx::query("UPDATE users_projection SET password_hash = $1, updated_at = NOW() WHERE id = $2")
            .bind(&password_hash)
            .bind(user_id)
            .execute(&self.pool)
            .await?;

        Ok(result.rows_affected() > 0)
    }

    pub async fn get_user_settings_impl(
        &self,
        user_id: Uuid,
        wallet_id: Uuid,
    ) -> Result<Option<UserSettings>, DbError> {
        let settings = sqlx::query_as::<_, UserSettings>(
            r#"
            SELECT id, user_id, wallet_id, default_contact_group_id, default_transaction_group_id, created_at, updated_at
            FROM user_wallet_settings
            WHERE user_id = $1 AND wallet_id = $2
            "#
        )
        .bind(user_id)
        .bind(wallet_id)
        .fetch_optional(&self.pool)
        .await?;

        Ok(settings)
    }

    pub async fn set_default_groups_impl(
        &self,
        user_id: Uuid,
        wallet_id: Uuid,
        contact_group_id: Option<Uuid>,
        transaction_group_id: Option<Uuid>,
    ) -> Result<(), DbError> {
        sqlx::query(
            r#"
            INSERT INTO user_wallet_settings (user_id, wallet_id, default_contact_group_id, default_transaction_group_id, created_at, updated_at)
            VALUES ($1, $2, $3, $4, NOW(), NOW())
            ON CONFLICT (user_id, wallet_id) DO UPDATE SET
                default_contact_group_id = $3,
                default_transaction_group_id = $4,
                updated_at = NOW()
            "#
        )
        .bind(user_id)
        .bind(wallet_id)
        .bind(contact_group_id)
        .bind(transaction_group_id)
        .execute(&self.pool)
        .await?;

        Ok(())
    }
}

