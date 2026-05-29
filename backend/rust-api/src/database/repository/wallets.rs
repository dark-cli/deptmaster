use uuid::Uuid;
use chrono::Utc;
use sqlx::Row;
use crate::database::models::*;
use crate::database::error::DbError;
use crate::database::repository::Database;

impl Database {
    pub async fn get_wallet_impl(&self, wallet_id: Uuid) -> Result<Option<Wallet>, DbError> {
        let wallet = sqlx::query_as::<_, Wallet>(
            r#"
            SELECT id, name, description, created_by, is_active, created_at, updated_at
            FROM wallets
            WHERE id = $1
            "#
        )
        .bind(wallet_id)
        .fetch_optional(&self.pool)
        .await?;

        Ok(wallet)
    }

    pub async fn create_wallet_impl(
        &self,
        id: Uuid,
        name: String,
        description: Option<String>,
        created_by: Option<Uuid>,
    ) -> Result<(), DbError> {
        sqlx::query(
            r#"
            INSERT INTO wallets (id, name, description, created_by, created_at, updated_at, is_active)
            VALUES ($1, $2, $3, $4, NOW(), NOW(), true)
            ON CONFLICT (id) DO NOTHING
            "#
        )
        .bind(id)
        .bind(&name)
        .bind(&description)
        .bind(created_by)
        .execute(&self.pool)
        .await?;

        Ok(())
    }

    pub async fn get_user_wallets_impl(&self, user_id: Uuid) -> Result<Vec<Wallet>, DbError> {
        let wallets = sqlx::query_as::<_, Wallet>(
            r#"
            SELECT w.id, w.name, w.description, w.created_by, w.is_active, w.created_at, w.updated_at
            FROM wallets w
            INNER JOIN wallet_users wu ON w.id = wu.wallet_id
            WHERE wu.user_id = $1 AND w.is_active = true
            ORDER BY COALESCE(wu.subscribed_at, wu.created_at) DESC
            "#
        )
        .bind(user_id)
        .fetch_all(&self.pool)
        .await?;

        Ok(wallets)
    }

    pub async fn list_wallet_users_impl(&self, wallet_id: Uuid) -> Result<Vec<WalletUser>, DbError> {
        let users = sqlx::query_as::<_, WalletUser>(
            r#"
            SELECT id, wallet_id, user_id, role, created_at
            FROM wallet_users
            WHERE wallet_id = $1
            ORDER BY created_at ASC
            "#
        )
        .bind(wallet_id)
        .fetch_all(&self.pool)
        .await?;

        Ok(users)
    }

    pub async fn add_wallet_user_impl(
        &self,
        wallet_id: Uuid,
        user_id: Uuid,
        role: String,
    ) -> Result<(), DbError> {
        sqlx::query(
            r#"
            INSERT INTO wallet_users (wallet_id, user_id, role, subscribed_at)
            VALUES ($1, $2, $3, NOW())
            ON CONFLICT (wallet_id, user_id) DO NOTHING
            "#
        )
        .bind(wallet_id)
        .bind(user_id)
        .bind(&role)
        .execute(&self.pool)
        .await?;

        Ok(())
    }

    pub async fn update_wallet_user_role_impl(
        &self,
        wallet_id: Uuid,
        user_id: Uuid,
        role: String,
    ) -> Result<bool, DbError> {
        let result = sqlx::query("UPDATE wallet_users SET role = $1 WHERE wallet_id = $2 AND user_id = $3")
            .bind(&role)
            .bind(wallet_id)
            .bind(user_id)
            .execute(&self.pool)
            .await?;

        Ok(result.rows_affected() > 0)
    }

    pub async fn get_wallet_user_role_impl(
        &self,
        wallet_id: Uuid,
        user_id: Uuid,
    ) -> Result<Option<String>, DbError> {
        let role = sqlx::query_scalar::<_, String>(
            r#"
            SELECT role
            FROM wallet_users
            WHERE wallet_id = $1 AND user_id = $2
            "#
        )
        .bind(wallet_id)
        .bind(user_id)
        .fetch_optional(&self.pool)
        .await?;

        Ok(role)
    }

    pub async fn get_all_active_wallets_impl(&self) -> Result<Vec<Wallet>, DbError> {
        let wallets = sqlx::query_as::<_, Wallet>(
            r#"
            SELECT id, name, description, created_by, is_active, created_at, updated_at
            FROM wallets
            WHERE is_active = true
            ORDER BY created_at DESC
            "#
        )
        .fetch_all(&self.pool)
        .await?;

        Ok(wallets)
    }

    pub async fn wallet_exists_impl(&self, wallet_id: Uuid) -> Result<bool, DbError> {
        let exists = sqlx::query_scalar::<_, bool>(
            "SELECT EXISTS(SELECT 1 FROM wallets WHERE id = $1 AND is_active = true)"
        )
        .bind(wallet_id)
        .fetch_one(&self.pool)
        .await?;

        Ok(exists)
    }

    pub async fn delete_wallet_impl(&self, wallet_id: Uuid) -> Result<bool, DbError> {
        let result = sqlx::query(
            "UPDATE wallets SET is_active = false, updated_at = NOW() WHERE id = $1"
        )
        .bind(wallet_id)
        .execute(&self.pool)
        .await?;

        Ok(result.rows_affected() > 0)
    }

    pub async fn update_wallet_impl(
        &self,
        wallet_id: Uuid,
        name: Option<&str>,
        description: Option<&str>,
        is_active: Option<bool>,
    ) -> Result<bool, DbError> {
        let mut updates = Vec::new();
        let mut bind_index = 1;

        if name.is_some() {
            updates.push(format!("name = ${}", bind_index));
            bind_index += 1;
        }
        if description.is_some() {
            updates.push(format!("description = ${}", bind_index));
            bind_index += 1;
        }
        if is_active.is_some() {
            updates.push(format!("is_active = ${}", bind_index));
            bind_index += 1;
        }

        if updates.is_empty() {
            return Ok(false);
        }

        updates.push(format!("updated_at = ${}", bind_index));

        let query = format!(
            "UPDATE wallets SET {} WHERE id = ${}",
            updates.join(", "),
            bind_index + 1
        );

        let mut query_builder = sqlx::query(&query);

        if let Some(n) = name {
            query_builder = query_builder.bind(n);
        }
        if let Some(d) = description {
            query_builder = query_builder.bind(d);
        }
        if let Some(a) = is_active {
            query_builder = query_builder.bind(a);
        }
        query_builder = query_builder.bind(Utc::now());
        query_builder = query_builder.bind(wallet_id);

        let result = query_builder.execute(&self.pool).await?;

        Ok(result.rows_affected() > 0)
    }

    pub async fn list_wallet_users_with_username_impl(
        &self,
        wallet_id: Uuid,
    ) -> Result<Vec<WalletUserWithUsername>, DbError> {
        let rows = sqlx::query(
            r#"
            SELECT wu.id, wu.wallet_id, wu.user_id, u.username, wu.role, wu.created_at
            FROM wallet_users wu
            LEFT JOIN users_projection u ON u.id = wu.user_id
            WHERE wu.wallet_id = $1
            ORDER BY wu.created_at DESC
            "#
        )
        .bind(wallet_id)
        .fetch_all(&self.pool)
        .await?;

        let users = rows
            .into_iter()
            .map(|row| WalletUserWithUsername {
                id: row.get("id"),
                wallet_id: row.get("wallet_id"),
                user_id: row.get("user_id"),
                username: row.try_get("username").ok(),
                role: row.get("role"),
                created_at: row.get("created_at"),
            })
            .collect();

        Ok(users)
    }

    pub async fn count_wallet_owners_impl(&self, wallet_id: Uuid) -> Result<i64, DbError> {
        let count: i64 = sqlx::query_scalar(
            "SELECT COUNT(*) FROM wallet_users WHERE wallet_id = $1 AND role = 'owner'"
        )
        .bind(wallet_id)
        .fetch_one(&self.pool)
        .await?;

        Ok(count)
    }

    pub async fn get_wallet_user_settings_impl(
        &self,
        wallet_id: Uuid,
        user_id: Uuid,
    ) -> Result<Option<(Vec<Uuid>, Vec<Uuid>)>, DbError> {
        let row = sqlx::query(
            "SELECT default_contact_group_ids, default_transaction_group_ids FROM user_wallet_settings WHERE wallet_id = $1 AND user_id = $2"
        )
        .bind(wallet_id)
        .bind(user_id)
        .fetch_optional(&self.pool)
        .await?;

        Ok(row.map(|r| {
            let contact_ids: Vec<Uuid> = r.get("default_contact_group_ids");
            let transaction_ids: Vec<Uuid> = r.get("default_transaction_group_ids");
            (contact_ids, transaction_ids)
        }))
    }

    pub async fn upsert_wallet_user_settings_impl(
        &self,
        wallet_id: Uuid,
        user_id: Uuid,
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
            "#,
        )
        .bind(wallet_id)
        .bind(user_id)
        .bind(contact_group_ids)
        .bind(transaction_group_ids)
        .execute(&self.pool)
        .await?;

        Ok(())
    }

    pub async fn upsert_invite_code_impl(&self, wallet_id: Uuid, code: &str, created_by: Uuid) -> Result<(), DbError> {
        sqlx::query(
            r#"
            INSERT INTO wallet_invite_codes (wallet_id, code, created_by, created_at)
            VALUES ($1, $2, $3, NOW())
            ON CONFLICT (wallet_id) DO UPDATE
            SET code = EXCLUDED.code,
                created_at = NOW(),
                created_by = EXCLUDED.created_by
            "#
        )
        .bind(wallet_id)
        .bind(code)
        .bind(created_by)
        .execute(&self.pool)
        .await?;

        Ok(())
    }

    pub async fn get_wallet_by_invite_code_impl(&self, code: &str) -> Result<Option<Uuid>, DbError> {
        let row: Option<(Uuid,)> = sqlx::query_as(
            r#"
            SELECT wallet_id
            FROM wallet_invite_codes
            WHERE code = $1
              AND created_at > NOW() - INTERVAL '5 minutes'
            "#
        )
        .bind(code)
        .fetch_optional(&self.pool)
        .await?;

        Ok(row.map(|(wallet_id,)| wallet_id))
    }

    pub async fn delete_invite_code_impl(&self, wallet_id: Uuid, code: &str) -> Result<(), DbError> {
        sqlx::query("DELETE FROM wallet_invite_codes WHERE wallet_id = $1 AND code = $2")
            .bind(wallet_id)
            .bind(code)
            .execute(&self.pool)
            .await?;

        Ok(())
    }

    pub async fn wallet_user_exists_impl(&self, wallet_id: Uuid, user_id: Uuid) -> Result<bool, DbError> {
        let exists: bool = sqlx::query_scalar(
            "SELECT EXISTS(SELECT 1 FROM wallet_users WHERE wallet_id = $1 AND user_id = $2)"
        )
        .bind(wallet_id)
        .bind(user_id)
        .fetch_one(&self.pool)
        .await?;

        Ok(exists)
    }
}

