//! Refresh-token repository: mint, redeem, rotate, revoke.
//!
//! Storage rule: never store the raw token. The DB only sees a SHA-256
//! hash (`token_hash`). On lookup we hash the incoming token and match
//! by hash. Leaking the DB does not leak active sessions.
//!
//! Rotation rule: every successful refresh issues a new token AND
//! revokes the redeemed one (marks `revoked_at`, links to the new row
//! via `replaced_by_id`). Re-redeeming a revoked token whose
//! `replaced_by_id` already exists is a strong signal of token theft —
//! a stolen copy was redeemed before the legitimate client got to it.
//! On that signal we revoke every refresh token for the user, forcing
//! a re-login on every device.

use super::Database;
use crate::database::repository::DbError;
use chrono::{NaiveDateTime, Utc};
use sha2::{Digest, Sha256};
use uuid::Uuid;

/// A freshly minted refresh token: the raw string the client must
/// store (we'll never see it again) and the DB row id (handy for
/// `replaced_by_id` linking on rotation).
#[allow(dead_code)]
pub struct MintedRefreshToken {
    pub raw: String,
    pub id: Uuid,
}

/// A row from `refresh_tokens` that's still potentially valid (the
/// caller still needs to check `is_redeemable`).
pub struct StoredRefreshToken {
    pub id: Uuid,
    pub user_id: Uuid,
    pub expires_at: NaiveDateTime,
    pub revoked_at: Option<NaiveDateTime>,
    pub replaced_by_id: Option<Uuid>,
}

impl StoredRefreshToken {
    /// True if this token is still valid for a single redemption:
    /// not revoked, not expired. After a successful redemption the
    /// caller must set `revoked_at` and `replaced_by_id` so the same
    /// token cannot be reused (rotation rule above).
    pub fn is_redeemable(&self) -> bool {
        self.revoked_at.is_none() && self.expires_at > Utc::now().naive_utc()
    }

    /// True if this token has been revoked but still has time left on
    /// the clock — the "someone tried to redeem an already-rotated
    /// token" signal that triggers full-account revocation.
    pub fn was_already_redeemed(&self) -> bool {
        self.revoked_at.is_some() && self.replaced_by_id.is_some()
    }
}

/// SHA-256 of the raw token, lowercase hex. Used as the index key.
pub fn hash_token(raw: &str) -> String {
    let digest = Sha256::digest(raw.as_bytes());
    format!("{:x}", digest)
}

/// Generate the raw token to hand the client. 128 bits of UUID entropy
/// plus a "rt_" prefix so logs / DB dumps make its purpose obvious.
fn fresh_raw_token() -> String {
    format!("rt_{}", Uuid::new_v4())
}

impl Database {
    /// Issue a brand-new refresh token for `user_id`. Returns the raw
    /// token (so the caller can put it in the HTTP response) and the
    /// new row id (so a future rotation can link to it). The raw
    /// token never lives at rest beyond this function — only its
    /// hash does.
    pub async fn mint_refresh_token(
        &self,
        user_id: Uuid,
        lifetime_secs: u64,
    ) -> Result<MintedRefreshToken, DbError> {
        let raw = fresh_raw_token();
        let token_hash = hash_token(&raw);
        let expires_at =
            (Utc::now() + chrono::Duration::seconds(lifetime_secs as i64)).naive_utc();
        let id: Uuid = sqlx::query_scalar(
            r#"
            INSERT INTO refresh_tokens (user_id, token_hash, expires_at)
            VALUES ($1, $2, $3)
            RETURNING id
            "#,
        )
        .bind(user_id)
        .bind(&token_hash)
        .bind(expires_at)
        .fetch_one(&self.pool)
        .await?;
        Ok(MintedRefreshToken { raw, id })
    }

    /// Look up a refresh token by its raw value (hashed internally).
    /// Returns the row regardless of revoked/expired state — caller
    /// decides what to do via `StoredRefreshToken::is_redeemable` /
    /// `was_already_redeemed`. Returns `None` if no row matches the
    /// hash (token never existed, or was wiped by user delete cascade).
    pub async fn find_refresh_token_by_raw(
        &self,
        raw: &str,
    ) -> Result<Option<StoredRefreshToken>, DbError> {
        let hash = hash_token(raw);
        let row: Option<(Uuid, Uuid, NaiveDateTime, Option<NaiveDateTime>, Option<Uuid>)> =
            sqlx::query_as(
                r#"
                SELECT id, user_id, expires_at, revoked_at, replaced_by_id
                FROM refresh_tokens
                WHERE token_hash = $1
                "#,
            )
            .bind(&hash)
            .fetch_optional(&self.pool)
            .await?;
        Ok(row.map(
            |(id, user_id, expires_at, revoked_at, replaced_by_id)| StoredRefreshToken {
                id,
                user_id,
                expires_at,
                revoked_at,
                replaced_by_id,
            },
        ))
    }

    /// Atomic rotation: mark the old token revoked, link it to a fresh
    /// new token, return the new raw token to give to the client. Runs
    /// in one transaction so a failure leaves the old token still
    /// redeemable rather than wedging the user out mid-rotation.
    pub async fn rotate_refresh_token(
        &self,
        old_id: Uuid,
        user_id: Uuid,
        lifetime_secs: u64,
    ) -> Result<MintedRefreshToken, DbError> {
        let raw = fresh_raw_token();
        let token_hash = hash_token(&raw);
        let now = Utc::now().naive_utc();
        let expires_at = (Utc::now() + chrono::Duration::seconds(lifetime_secs as i64))
            .naive_utc();

        let mut tx = self.pool.begin().await?;
        let new_id: Uuid = sqlx::query_scalar(
            r#"
            INSERT INTO refresh_tokens (user_id, token_hash, expires_at)
            VALUES ($1, $2, $3)
            RETURNING id
            "#,
        )
        .bind(user_id)
        .bind(&token_hash)
        .bind(expires_at)
        .fetch_one(&mut *tx)
        .await?;
        sqlx::query(
            r#"
            UPDATE refresh_tokens
               SET revoked_at = $1, replaced_by_id = $2
             WHERE id = $3
            "#,
        )
        .bind(now)
        .bind(new_id)
        .bind(old_id)
        .execute(&mut *tx)
        .await?;
        tx.commit().await?;
        Ok(MintedRefreshToken { raw, id: new_id })
    }

    /// Revoke a single refresh token row by id. Idempotent — re-revoking
    /// a row that's already revoked is a no-op. Used by per-device logout
    /// where we want to kill *this* session's refresh chain without
    /// touching the user's other devices.
    pub async fn revoke_refresh_token(&self, id: Uuid) -> Result<(), DbError> {
        sqlx::query(
            r#"
            UPDATE refresh_tokens
               SET revoked_at = COALESCE(revoked_at, NOW())
             WHERE id = $1
            "#,
        )
        .bind(id)
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    /// Mark every refresh token for `user_id` revoked. Called on
    /// detection of token-theft (an already-redeemed token was
    /// presented again) and on explicit "log me out of all devices."
    pub async fn revoke_all_refresh_tokens_for_user(
        &self,
        user_id: Uuid,
    ) -> Result<(), DbError> {
        sqlx::query(
            r#"
            UPDATE refresh_tokens
               SET revoked_at = COALESCE(revoked_at, NOW())
             WHERE user_id = $1
            "#,
        )
        .bind(user_id)
        .execute(&self.pool)
        .await?;
        Ok(())
    }
}
