use uuid::Uuid;
use crate::database::models::*;
use crate::database::error::DbError;
use crate::database::repository::Database;

impl Database {
    pub async fn get_wallet_impl(&self, wallet_id: Uuid) -> Result<Option<Wallet>, DbError> {
        let wallet = sqlx::query_as::<_, Wallet>(
            r#"
            SELECT id, name, created_at, updated_at
            FROM wallets
            WHERE id = $1
            "#
        )
        .bind(wallet_id)
        .fetch_optional(&self.pool)
        .await?;

        Ok(wallet)
    }

    pub async fn create_wallet_impl(&self, id: Uuid, name: String) -> Result<(), DbError> {
        sqlx::query(
            r#"
            INSERT INTO wallets (id, name, created_at, updated_at)
            VALUES ($1, $2, NOW(), NOW())
            ON CONFLICT (id) DO NOTHING
            "#
        )
        .bind(id)
        .bind(&name)
        .execute(&self.pool)
        .await?;

        Ok(())
    }

    pub async fn get_user_wallets_impl(&self, user_id: Uuid) -> Result<Vec<Wallet>, DbError> {
        let wallets = sqlx::query_as::<_, Wallet>(
            r#"
            SELECT w.id, w.name, w.created_at, w.updated_at
            FROM wallets w
            INNER JOIN wallet_users wu ON w.id = wu.wallet_id
            WHERE wu.user_id = $1
            ORDER BY w.created_at ASC
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
            INSERT INTO wallet_users (wallet_id, user_id, role, created_at)
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
}

