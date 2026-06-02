use crate::database::error::DbError;
use sqlx::PgPool;
use uuid::Uuid;

/// Manages user event hashes for efficient sync operations
/// Public API: get_hash (fetch stored hash)
/// Private API: calculate_and_store (update hash when readable events change)
pub struct UserEventHash;

impl UserEventHash {
    /// PUBLIC: Get stored hash from database
    /// Called by sync handlers to retrieve pre-calculated hash
    pub async fn get_hash(
        pool: &PgPool,
        wallet_id: Uuid,
        user_id: Uuid,
    ) -> Result<String, DbError> {
        let hash: String = sqlx::query_scalar(
            "SELECT COALESCE(hash, '') FROM user_event_hashes WHERE wallet_id = $1 AND user_id = $2",
        )
        .bind(wallet_id)
        .bind(user_id)
        .fetch_optional(pool)
        .await?
        .flatten()
        .unwrap_or_default();

        Ok(hash)
    }

    /// PRIVATE: Calculate incremental hash and store in database
    /// Called internally when readable events table changes
    /// Hash calculation: MD5(previous_hash + new_event_id)
    pub(crate) async fn calculate_and_store(
        pool: &PgPool,
        wallet_id: Uuid,
        user_id: Uuid,
        event_id: Uuid,
    ) -> Result<String, DbError> {
        // Get current hash for this user
        let current_hash: Option<String> = sqlx::query_scalar(
            "SELECT hash FROM user_event_hashes WHERE wallet_id = $1 AND user_id = $2",
        )
        .bind(wallet_id)
        .bind(user_id)
        .fetch_optional(pool)
        .await?
        .flatten();

        // Calculate new hash: MD5(current_hash + event_id)
        let current = current_hash.unwrap_or_default();
        let hash_input = format!("{}{}", current, event_id);
        let new_hash: String =
            sqlx::query_scalar("SELECT md5($1::text)").bind(&hash_input).fetch_one(pool).await?;

        // Update or insert hash record
        sqlx::query(
            r#"
            INSERT INTO user_event_hashes (wallet_id, user_id, last_event_id, hash, updated_at)
            VALUES ($1, $2, $3, $4, NOW())
            ON CONFLICT (wallet_id, user_id) DO UPDATE SET
                hash = EXCLUDED.hash,
                last_event_id = EXCLUDED.last_event_id,
                updated_at = NOW()
            "#,
        )
        .bind(wallet_id)
        .bind(user_id)
        .bind(event_id)
        .bind(&new_hash)
        .execute(pool)
        .await?;

        Ok(new_hash)
    }

    /// PRIVATE: Reset hash when cache is cleared (permission rebuild)
    pub(crate) async fn reset(
        pool: &PgPool,
        wallet_id: Uuid,
        user_id: Uuid,
    ) -> Result<(), DbError> {
        sqlx::query(
            r#"
            INSERT INTO user_event_hashes (wallet_id, user_id, hash, updated_at)
            VALUES ($1, $2, '', NOW())
            ON CONFLICT (wallet_id, user_id) DO UPDATE SET
                hash = '',
                last_event_id = NULL,
                updated_at = NOW()
            "#,
        )
        .bind(wallet_id)
        .bind(user_id)
        .execute(pool)
        .await?;

        Ok(())
    }
}
