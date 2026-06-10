//! Server-side implementation of [`applier::Projection`].
//!
//! Wraps a `&PgPool` together with the per-event metadata the server needs
//! (event_db_id BIGSERIAL, created_at) for `last_event_id` bookkeeping on
//! projection rows. The applier sets this context via
//! [`applier::Projection::set_event_context`] before each event, then
//! invokes the trait methods to run the actual SQL.
//!
//! Today this only covers Contact events (Phase 0.2 step 3a). Transaction
//! and Permission methods will be added in 3b/3c; until then,
//! `apply_event_batch_typed` dispatches Contact events through this impl
//! and routes Transaction/Permission events through the legacy
//! `apply_*_typed` methods on `Database`.

use applier::{ContactPatch, Projection};
use async_trait::async_trait;
use chrono::NaiveDateTime;
use domain::DomainEvent;
use sqlx::PgPool;
use uuid::Uuid;

/// Per-event context the server's apply needs. Set once before the event's
/// applier::apply call; consumed by the trait methods below.
struct EventContext {
    event_db_id: i64,
    created_at: NaiveDateTime,
}

pub struct ServerProjection<'a> {
    pool: &'a PgPool,
    // Set when set_event_context fires; None before the first event.
    ctx: Option<EventContext>,
}

impl<'a> ServerProjection<'a> {
    /// Build with the BIGSERIAL `event_db_id` for the event being applied.
    /// `event_db_id` comes from the row in `events` we just read; can't be
    /// derived from `DomainEvent` alone, so the caller (apply_event_batch_typed)
    /// supplies it.
    pub fn new(pool: &'a PgPool, event_db_id: i64, created_at: NaiveDateTime) -> Self {
        Self {
            pool,
            ctx: Some(EventContext {
                event_db_id,
                created_at,
            }),
        }
    }

    fn ctx(&self) -> &EventContext {
        self.ctx
            .as_ref()
            .expect("ServerProjection: set_event_context not called before apply")
    }
}

#[async_trait]
impl<'a> Projection for ServerProjection<'a> {
    type Error = sqlx::Error;

    // The applier calls this before each event. We were constructed with the
    // first event's context; later events would require a fresh ServerProjection.
    // For now (one-event-per-instance pattern in apply_event_batch_typed),
    // this is effectively a no-op — the ctx is already set.
    async fn set_event_context(&mut self, _event: &DomainEvent) -> Result<(), Self::Error> {
        Ok(())
    }

    // ---------- Contact CRUD ----------

    async fn upsert_contact_row(
        &mut self,
        id: Uuid,
        wallet_id: Uuid,
        user_id: Uuid,
        name: &str,
        username: Option<&str>,
        phone: Option<&str>,
        email: Option<&str>,
        notes: Option<&str>,
    ) -> Result<(), Self::Error> {
        let c = self.ctx();
        sqlx::query(
            r#"
            INSERT INTO contacts_projection
            (id, user_id, wallet_id, name, username, phone, email, notes, is_deleted, created_at, updated_at, last_event_id)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, false, $9, $9, $10)
            ON CONFLICT (id) DO UPDATE SET
                name = EXCLUDED.name,
                username = EXCLUDED.username,
                phone = EXCLUDED.phone,
                email = EXCLUDED.email,
                notes = EXCLUDED.notes,
                updated_at = EXCLUDED.updated_at,
                last_event_id = EXCLUDED.last_event_id
            "#,
        )
        .bind(id)
        .bind(user_id)
        .bind(wallet_id)
        .bind(name)
        .bind(username)
        .bind(phone)
        .bind(email)
        .bind(notes)
        .bind(c.created_at)
        .bind(c.event_db_id)
        .execute(self.pool)
        .await?;
        Ok(())
    }

    async fn update_contact_row(
        &mut self,
        id: Uuid,
        wallet_id: Uuid,
        patch: ContactPatch,
    ) -> Result<(), Self::Error> {
        let c = self.ctx();
        // COALESCE pattern: $N is NULL when patch field is None, in which
        // case we keep the existing column value.
        sqlx::query(
            r#"
            UPDATE contacts_projection SET
                name          = COALESCE($2, name),
                username      = COALESCE($3, username),
                phone         = COALESCE($4, phone),
                email         = COALESCE($5, email),
                notes         = COALESCE($6, notes),
                updated_at    = $7,
                last_event_id = $9
            WHERE id = $1 AND wallet_id = $8
            "#,
        )
        .bind(id)
        .bind(patch.name)
        .bind(patch.username)
        .bind(patch.phone)
        .bind(patch.email)
        .bind(patch.notes)
        .bind(c.created_at)
        .bind(wallet_id)
        .bind(c.event_db_id)
        .execute(self.pool)
        .await?;
        Ok(())
    }

    async fn soft_delete_contact_row(
        &mut self,
        id: Uuid,
        wallet_id: Uuid,
    ) -> Result<(), Self::Error> {
        let c = self.ctx();
        sqlx::query(
            r#"
            UPDATE contacts_projection
               SET is_deleted = true, updated_at = $2, last_event_id = $4
             WHERE id = $1 AND wallet_id = $3
            "#,
        )
        .bind(id)
        .bind(c.created_at)
        .bind(wallet_id)
        .bind(c.event_db_id)
        .execute(self.pool)
        .await?;
        Ok(())
    }

    async fn soft_delete_transactions_for_contact(
        &mut self,
        contact_id: Uuid,
        wallet_id: Uuid,
    ) -> Result<(), Self::Error> {
        let c = self.ctx();
        let result = sqlx::query(
            r#"
            UPDATE transactions_projection
               SET is_deleted = true, updated_at = $1, last_event_id = $4
             WHERE contact_id = $2 AND wallet_id = $3 AND is_deleted = false
            "#,
        )
        .bind(c.created_at)
        .bind(contact_id)
        .bind(wallet_id)
        .bind(c.event_db_id)
        .execute(self.pool)
        .await?;

        if result.rows_affected() > 0 {
            tracing::info!(
                "Cascade soft-deleted {} transaction(s) for contact {}",
                result.rows_affected(),
                contact_id
            );
        }
        Ok(())
    }

    // ---------- Contact group memberships ----------

    async fn add_contact_to_system_group(
        &mut self,
        contact_id: Uuid,
        wallet_id: Uuid,
        system_group_name: &str,
    ) -> Result<(), Self::Error> {
        if let Some(group_id) = sqlx::query_scalar::<_, Uuid>(
            "SELECT id FROM contact_groups WHERE wallet_id = $1 AND name = $2 LIMIT 1",
        )
        .bind(wallet_id)
        .bind(system_group_name)
        .fetch_optional(self.pool)
        .await?
        {
            sqlx::query(
                r#"
                INSERT INTO contact_group_members (contact_id, contact_group_id)
                VALUES ($1, $2)
                ON CONFLICT DO NOTHING
                "#,
            )
            .bind(contact_id)
            .bind(group_id)
            .execute(self.pool)
            .await?;
        }
        Ok(())
    }

    async fn add_contact_to_groups(
        &mut self,
        contact_id: Uuid,
        wallet_id: Uuid,
        group_ids: &[Uuid],
    ) -> Result<(), Self::Error> {
        for &group_id in group_ids {
            let in_wallet: bool = sqlx::query_scalar(
                "SELECT EXISTS(SELECT 1 FROM contact_groups WHERE id = $1 AND wallet_id = $2)",
            )
            .bind(group_id)
            .bind(wallet_id)
            .fetch_one(self.pool)
            .await
            .unwrap_or(false);
            if in_wallet {
                sqlx::query(
                    r#"
                    INSERT INTO contact_group_members (contact_id, contact_group_id)
                    VALUES ($1, $2)
                    ON CONFLICT DO NOTHING
                    "#,
                )
                .bind(contact_id)
                .bind(group_id)
                .execute(self.pool)
                .await?;
            }
        }
        Ok(())
    }

    async fn replace_contact_group_memberships(
        &mut self,
        contact_id: Uuid,
        wallet_id: Uuid,
        group_ids: &[Uuid],
    ) -> Result<(), Self::Error> {
        // Replace = wipe existing non-`all_contacts` memberships, then add the new set.
        // `all_contacts` is the system group; every contact stays in it by invariant.
        sqlx::query(
            r#"
            DELETE FROM contact_group_members
             WHERE contact_id = $1
               AND contact_group_id IN (
                 SELECT id FROM contact_groups
                  WHERE wallet_id = $2 AND name <> 'all_contacts'
               )
            "#,
        )
        .bind(contact_id)
        .bind(wallet_id)
        .execute(self.pool)
        .await?;

        self.add_contact_to_groups(contact_id, wallet_id, group_ids)
            .await
    }
}
