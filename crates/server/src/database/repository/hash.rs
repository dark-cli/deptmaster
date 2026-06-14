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

    /// PRIVATE: Calculate incremental hash and store in database.
    /// Called internally when readable events table changes.
    /// Hash calculation: MD5(previous_hash + new_event_id).
    ///
    /// CRITICAL — must be a single SQL statement: an earlier version
    /// did SELECT-then-md5-then-UPDATE in three separate statements,
    /// which is a textbook lost-update race when two concurrent calls
    /// fold different events into the same (wallet, user) row. Both
    /// reads observed the pre-write hash; both writes targeted that
    /// hash + their own event; the second write clobbered the first;
    /// one event's fold was permanently lost from the hash chain
    /// while the event itself still landed in user_readable_events.
    /// Every client whose previous_hash already incorporated the
    /// lost event would then diverge on the next pull — exactly the
    /// "hash diverged" loop reported in production where the
    /// server's returned hash equalled the client's starting_hash
    /// (server's chain didn't actually advance for the new event).
    ///
    /// The single INSERT ... ON CONFLICT DO UPDATE below reads the
    /// existing row inside the same statement via
    /// `user_event_hashes.hash`. Postgres takes a row lock on the
    /// conflicting row, so concurrent statements serialize cleanly:
    /// each fold sees the prior fold's result. The returned hash is
    /// the post-fold value, RETURNING-ed atomically.
    // pub (not pub(crate)) so the concurrency regression test in
    // crates/server/tests/hash_calculate_and_store_concurrent_test.rs
    // can call it directly without setting up the surrounding FK
    // plumbing (events row, user_readable_events row, etc.).
    pub async fn calculate_and_store(
        pool: &PgPool,
        wallet_id: Uuid,
        user_id: Uuid,
        event_id: Uuid,
    ) -> Result<String, DbError> {
        let new_hash: String = sqlx::query_scalar(
            r#"
            INSERT INTO user_event_hashes (wallet_id, user_id, last_event_id, hash, updated_at)
            VALUES ($1, $2, $3, md5($3::text), NOW())
            ON CONFLICT (wallet_id, user_id) DO UPDATE SET
                hash          = md5(user_event_hashes.hash || $3::text),
                last_event_id = EXCLUDED.last_event_id,
                updated_at    = NOW()
            RETURNING hash
            "#,
        )
        .bind(wallet_id)
        .bind(user_id)
        .bind(event_id)
        .fetch_one(pool)
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
