use uuid::Uuid;
use chrono::NaiveDateTime;
use crate::database::models::*;
use crate::database::error::DbError;
use crate::database::repository::Database;

impl Database {
    pub async fn get_user_by_email_impl(&self, email: &str) -> Result<Option<User>, DbError> {
        let user = sqlx::query_as::<_, User>(
            r#"
            SELECT id, email, username, password_hash, created_at
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
            SELECT id, email, username, password_hash, created_at
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
        username: String,
        password_hash: String,
    ) -> Result<(), DbError> {
        sqlx::query(
            r#"
            INSERT INTO users_projection (id, username, email, password_hash, created_at)
            VALUES ($1, $2, $3, $4, NOW())
            ON CONFLICT (id) DO NOTHING
            "#
        )
        .bind(id)
        .bind(&username)
        .bind(&username)
        .bind(&password_hash)
        .execute(&self.pool)
        .await?;

        Ok(())
    }

    pub async fn update_user_password_impl(&self, user_id: Uuid, password_hash: String) -> Result<bool, DbError> {
        let result = sqlx::query("UPDATE users_projection SET password_hash = $1 WHERE id = $2")
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
            SELECT wallet_id, user_id, default_contact_group_ids, default_transaction_group_ids
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
        contact_group_ids: &[Uuid],
        transaction_group_ids: &[Uuid],
    ) -> Result<(), DbError> {
        sqlx::query(
            r#"
            INSERT INTO user_wallet_settings (wallet_id, user_id, default_contact_group_ids, default_transaction_group_ids)
            VALUES ($1, $2, $3, $4)
            ON CONFLICT (wallet_id, user_id) DO UPDATE SET
                default_contact_group_ids = $3,
                default_transaction_group_ids = $4
            "#
        )
        .bind(wallet_id)
        .bind(user_id)
        .bind(contact_group_ids)
        .bind(transaction_group_ids)
        .execute(&self.pool)
        .await?;

        Ok(())
    }

    pub async fn get_user_by_username_impl(&self, username: &str) -> Result<Option<User>, DbError> {
        let user = sqlx::query_as::<_, User>(
            r#"
            SELECT id, email, username, password_hash, created_at
            FROM users_projection
            WHERE username = $1
            LIMIT 1
            "#
        )
        .bind(username)
        .fetch_optional(&self.pool)
        .await?;

        Ok(user)
    }

    pub async fn insert_login_log_impl(
        &self,
        user_id: Option<Uuid>,
        ip_address: &str,
        user_agent: &str,
        success: bool,
        failure_reason: Option<&str>,
    ) -> Result<(), DbError> {
        sqlx::query(
            r#"
            INSERT INTO login_logs (user_id, login_at, ip_address, user_agent, success, failure_reason)
            VALUES ($1, NOW(), $2, $3, $4, $5)
            "#
        )
        .bind(user_id)
        .bind(ip_address)
        .bind(user_agent)
        .bind(success)
        .bind(failure_reason)
        .execute(&self.pool)
        .await?;

        Ok(())
    }

    pub async fn get_all_users_impl(&self) -> Result<Vec<(Uuid, Option<String>, NaiveDateTime)>, DbError> {
        let rows = sqlx::query_as::<_, (Uuid, Option<String>, NaiveDateTime)>(
            r#"
            SELECT id, username, created_at
            FROM users_projection
            ORDER BY created_at DESC
            "#
        )
        .fetch_all(&self.pool)
        .await?;

        Ok(rows)
    }

    pub async fn delete_user_impl(&self, user_id: Uuid) -> Result<bool, DbError> {
        let result = sqlx::query("DELETE FROM users_projection WHERE id = $1")
            .bind(user_id)
            .execute(&self.pool)
            .await?;

        Ok(result.rows_affected() > 0)
    }

    pub async fn get_login_logs_impl(
        &self,
        user_id: Uuid,
        limit: i64,
    ) -> Result<Vec<(i64, Uuid, NaiveDateTime, Option<String>, Option<String>, bool, Option<String>)>, DbError> {
        let rows = sqlx::query_as::<_, (i64, Uuid, NaiveDateTime, Option<String>, Option<String>, bool, Option<String>)>(
            r#"
            SELECT id, user_id, login_at, ip_address, user_agent, success, failure_reason
            FROM login_logs
            WHERE user_id = $1
            ORDER BY login_at DESC
            LIMIT $2
            "#
        )
        .bind(user_id)
        .bind(limit)
        .fetch_all(&self.pool)
        .await?;

        Ok(rows)
    }

    pub async fn get_user_settings_all_impl(
        &self,
        user_id: Uuid,
    ) -> Result<Vec<(String, Option<String>)>, DbError> {
        let rows = sqlx::query_as::<_, (String, Option<String>)>(
            r#"
            SELECT setting_key, setting_value
            FROM user_settings
            WHERE user_id = $1
            "#
        )
        .bind(user_id)
        .fetch_all(&self.pool)
        .await?;

        Ok(rows)
    }

    pub async fn upsert_user_setting_impl(
        &self,
        user_id: Uuid,
        setting_key: &str,
        setting_value: &str,
    ) -> Result<(), DbError> {
        sqlx::query(
            r#"
            INSERT INTO user_settings (user_id, setting_key, setting_value, updated_at)
            VALUES ($1, $2, $3, NOW())
            ON CONFLICT (user_id, setting_key)
            DO UPDATE SET setting_value = $3, updated_at = NOW()
            "#
        )
        .bind(user_id)
        .bind(setting_key)
        .bind(setting_value)
        .execute(&self.pool)
        .await?;

        Ok(())
    }

    pub async fn get_admin_by_username_impl(&self, username: &str) -> Result<Option<(Uuid, String, String, bool)>, DbError> {
        let row = sqlx::query_as::<_, (Uuid, String, String, bool)>(
            r#"
            SELECT id, username, password_hash, is_active
            FROM admin_users
            WHERE username = $1
            LIMIT 1
            "#
        )
        .bind(username)
        .fetch_optional(&self.pool)
        .await?;

        Ok(row)
    }

    pub async fn update_admin_last_login_impl(&self, admin_id: Uuid) -> Result<(), DbError> {
        sqlx::query("UPDATE admin_users SET last_login_at = NOW() WHERE id = $1")
            .bind(admin_id)
            .execute(&self.pool)
            .await?;

        Ok(())
    }

    pub async fn search_users_impl(&self, pattern: &str, limit: i64) -> Result<Vec<(Uuid, String)>, DbError> {
        let rows = sqlx::query_as::<_, (Uuid, String)>(
            "SELECT id, username FROM users_projection WHERE LOWER(username) LIKE LOWER($1) ORDER BY username LIMIT $2"
        )
        .bind(pattern)
        .bind(limit)
        .fetch_all(&self.pool)
        .await?;

        Ok(rows)
    }
}

