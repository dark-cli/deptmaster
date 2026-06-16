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

use applier::{ContactPatch, Projection, TransactionPatch};
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
        system_group: domain::SystemGroup,
    ) -> Result<(), Self::Error> {
        if let Some(group_id) = sqlx::query_scalar::<_, Uuid>(
            "SELECT id FROM contact_groups WHERE wallet_id = $1 AND name = $2 LIMIT 1",
        )
        .bind(wallet_id)
        .bind(system_group.as_str())
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

    // ---------- Transaction CRUD ----------

    async fn contact_is_active(
        &self,
        contact_id: Uuid,
        wallet_id: Uuid,
    ) -> Result<bool, Self::Error> {
        sqlx::query_scalar(
            r#"
            SELECT EXISTS(
              SELECT 1 FROM contacts_projection
               WHERE id = $1 AND wallet_id = $2 AND is_deleted = false
            )
            "#,
        )
        .bind(contact_id)
        .bind(wallet_id)
        .fetch_one(self.pool)
        .await
    }

    async fn upsert_transaction_row(
        &mut self,
        id: Uuid,
        wallet_id: Uuid,
        user_id: Uuid,
        contact_id: Uuid,
        amount: i64,
        direction: domain::TransactionDirection,
        transaction_type: Option<domain::TransactionType>,
        currency: Option<domain::Currency>,
        description: Option<&str>,
        transaction_date: Option<&str>,
        due_date: Option<&str>,
    ) -> Result<(), Self::Error> {
        let c = self.ctx();
        let tx_type = transaction_type.unwrap_or(domain::TransactionType::Money);
        let currency = currency.unwrap_or(domain::Currency::USD);

        // Parse dates from "%Y-%m-%d" strings. transaction_date defaults to
        // the event's created_at date if not provided; due_date is optional.
        // If transaction_date is provided but unparseable, the historical
        // behavior was to silently skip the whole event — preserved.
        let txn_date = match transaction_date {
            Some(d) => match chrono::NaiveDate::parse_from_str(d, "%Y-%m-%d") {
                Ok(parsed) => parsed,
                Err(_) => return Ok(()), // unparseable date → skip event
            },
            None => c.created_at.date(),
        };
        let parsed_due_date = due_date
            .and_then(|d| chrono::NaiveDate::parse_from_str(d, "%Y-%m-%d").ok());

        sqlx::query(
            r#"
            INSERT INTO transactions_projection
            (id, user_id, wallet_id, contact_id, type, direction, amount, currency, description,
             transaction_date, due_date, is_deleted, created_at, updated_at, last_event_id)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, false, $12, $12, $13)
            ON CONFLICT (id) DO UPDATE SET
                contact_id       = EXCLUDED.contact_id,
                type             = EXCLUDED.type,
                direction        = EXCLUDED.direction,
                amount           = EXCLUDED.amount,
                currency         = EXCLUDED.currency,
                description      = EXCLUDED.description,
                transaction_date = EXCLUDED.transaction_date,
                due_date         = EXCLUDED.due_date,
                updated_at       = EXCLUDED.updated_at,
                last_event_id    = EXCLUDED.last_event_id
            "#,
        )
        .bind(id)
        .bind(user_id)
        .bind(wallet_id)
        .bind(contact_id)
        .bind(tx_type.as_str())
        .bind(direction.as_str())
        .bind(amount)
        .bind(currency.as_str())
        .bind(description)
        .bind(txn_date)
        .bind(parsed_due_date)
        .bind(c.created_at)
        .bind(c.event_db_id)
        .execute(self.pool)
        .await?;
        Ok(())
    }

    async fn update_transaction_row(
        &mut self,
        id: Uuid,
        wallet_id: Uuid,
        patch: TransactionPatch,
    ) -> Result<(), Self::Error> {
        let c = self.ctx();

        // Parse incoming date strings; unparseable → treat as None (keep
        // existing) rather than skipping the whole event. Matches the
        // prior apply_transaction_event_typed behavior for updates.
        let new_transaction_date = patch
            .transaction_date
            .as_deref()
            .and_then(|d| chrono::NaiveDate::parse_from_str(d, "%Y-%m-%d").ok());
        let new_due_date = patch
            .due_date
            .as_deref()
            .and_then(|d| chrono::NaiveDate::parse_from_str(d, "%Y-%m-%d").ok());

        sqlx::query(
            r#"
            UPDATE transactions_projection SET
                contact_id       = COALESCE($2, contact_id),
                type             = COALESCE($3, type),
                direction        = COALESCE($4, direction),
                amount           = COALESCE($5, amount),
                currency         = COALESCE($6, currency),
                description      = COALESCE($7, description),
                transaction_date = COALESCE($8, transaction_date),
                due_date         = COALESCE($9, due_date),
                updated_at       = $10,
                last_event_id    = $12
            WHERE id = $1 AND wallet_id = $11
            "#,
        )
        .bind(id)
        .bind(patch.contact_id)
        .bind(patch.transaction_type.map(|t| t.as_str()))
        .bind(patch.direction.map(|d| d.as_str()))
        .bind(patch.amount)
        .bind(patch.currency.map(|c| c.as_str()))
        .bind(patch.description)
        .bind(new_transaction_date)
        .bind(new_due_date)
        .bind(c.created_at)
        .bind(wallet_id)
        .bind(c.event_db_id)
        .execute(self.pool)
        .await?;
        Ok(())
    }

    async fn soft_delete_transaction_row(
        &mut self,
        id: Uuid,
        wallet_id: Uuid,
    ) -> Result<(), Self::Error> {
        let c = self.ctx();
        sqlx::query(
            r#"
            UPDATE transactions_projection
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

    // ---------- Wallet membership ----------

    async fn upsert_wallet_user(
        &mut self,
        wallet_id: Uuid,
        user_id: Uuid,
        role: domain::WalletRole,
    ) -> Result<(), Self::Error> {
        let c = self.ctx();
        sqlx::query(
            r#"
            INSERT INTO wallet_users (wallet_id, user_id, role, subscribed_at)
            VALUES ($1, $2, $3, $4)
            ON CONFLICT (wallet_id, user_id) DO UPDATE SET role = $3, subscribed_at = $4
            "#,
        )
        .bind(wallet_id)
        .bind(user_id)
        .bind(role.as_str())
        .bind(c.created_at)
        .execute(self.pool)
        .await?;
        Ok(())
    }

    async fn update_wallet_user_role(
        &mut self,
        wallet_id: Uuid,
        user_id: Uuid,
        role: domain::WalletRole,
    ) -> Result<(), Self::Error> {
        sqlx::query("UPDATE wallet_users SET role = $1 WHERE wallet_id = $2 AND user_id = $3")
            .bind(role.as_str())
            .bind(wallet_id)
            .bind(user_id)
            .execute(self.pool)
            .await?;
        Ok(())
    }

    async fn remove_wallet_user(
        &mut self,
        wallet_id: Uuid,
        user_id: Uuid,
    ) -> Result<(), Self::Error> {
        sqlx::query("DELETE FROM wallet_users WHERE wallet_id = $1 AND user_id = $2")
            .bind(wallet_id)
            .bind(user_id)
            .execute(self.pool)
            .await?;
        Ok(())
    }

    async fn add_user_to_system_group(
        &mut self,
        wallet_id: Uuid,
        user_id: Uuid,
        system_group: domain::SystemGroup,
    ) -> Result<(), Self::Error> {
        sqlx::query(
            r#"
            INSERT INTO user_group_members (user_id, user_group_id)
            SELECT $2, ug.id
              FROM user_groups ug
             WHERE ug.wallet_id = $1 AND ug.name = $3
            ON CONFLICT (user_id, user_group_id) DO NOTHING
            "#,
        )
        .bind(wallet_id)
        .bind(user_id)
        .bind(system_group.as_str())
        .execute(self.pool)
        .await?;
        Ok(())
    }

    // ---------- User groups ----------

    async fn upsert_user_group(
        &mut self,
        id: Uuid,
        wallet_id: Uuid,
        name: &str,
    ) -> Result<(), Self::Error> {
        sqlx::query(
            r#"
            INSERT INTO user_groups (id, wallet_id, name, is_system)
            VALUES ($1, $2, $3, false)
            ON CONFLICT (id) DO UPDATE SET name = $3
            "#,
        )
        .bind(id)
        .bind(wallet_id)
        .bind(name)
        .execute(self.pool)
        .await?;
        Ok(())
    }

    async fn rename_user_group(
        &mut self,
        id: Uuid,
        wallet_id: Uuid,
        name: &str,
    ) -> Result<(), Self::Error> {
        sqlx::query(
            "UPDATE user_groups SET name = $1 WHERE id = $2 AND wallet_id = $3 AND is_system = false",
        )
        .bind(name)
        .bind(id)
        .bind(wallet_id)
        .execute(self.pool)
        .await?;
        Ok(())
    }

    async fn delete_user_group(
        &mut self,
        id: Uuid,
        wallet_id: Uuid,
    ) -> Result<(), Self::Error> {
        sqlx::query(
            "DELETE FROM user_groups WHERE id = $1 AND wallet_id = $2 AND is_system = false",
        )
        .bind(id)
        .bind(wallet_id)
        .execute(self.pool)
        .await?;
        Ok(())
    }

    async fn add_user_group_member(
        &mut self,
        user_group_id: Uuid,
        user_id: Uuid,
    ) -> Result<(), Self::Error> {
        sqlx::query(
            r#"
            INSERT INTO user_group_members (user_id, user_group_id)
            VALUES ($1, $2)
            ON CONFLICT (user_id, user_group_id) DO NOTHING
            "#,
        )
        .bind(user_id)
        .bind(user_group_id)
        .execute(self.pool)
        .await?;
        Ok(())
    }

    async fn remove_user_group_member(
        &mut self,
        user_group_id: Uuid,
        user_id: Uuid,
    ) -> Result<(), Self::Error> {
        sqlx::query(
            "DELETE FROM user_group_members WHERE user_id = $1 AND user_group_id = $2",
        )
        .bind(user_id)
        .bind(user_group_id)
        .execute(self.pool)
        .await?;
        Ok(())
    }

    // ---------- Contact groups ----------

    async fn upsert_contact_group(
        &mut self,
        id: Uuid,
        wallet_id: Uuid,
        name: &str,
    ) -> Result<(), Self::Error> {
        sqlx::query(
            r#"
            INSERT INTO contact_groups (id, wallet_id, name, is_system)
            VALUES ($1, $2, $3, false)
            ON CONFLICT (id) DO UPDATE SET name = $3
            "#,
        )
        .bind(id)
        .bind(wallet_id)
        .bind(name)
        .execute(self.pool)
        .await?;
        Ok(())
    }

    async fn rename_contact_group(
        &mut self,
        id: Uuid,
        wallet_id: Uuid,
        name: &str,
    ) -> Result<(), Self::Error> {
        sqlx::query(
            "UPDATE contact_groups SET name = $1 WHERE id = $2 AND wallet_id = $3 AND is_system = false",
        )
        .bind(name)
        .bind(id)
        .bind(wallet_id)
        .execute(self.pool)
        .await?;
        Ok(())
    }

    async fn delete_contact_group(
        &mut self,
        id: Uuid,
        wallet_id: Uuid,
    ) -> Result<(), Self::Error> {
        sqlx::query(
            "DELETE FROM contact_groups WHERE id = $1 AND wallet_id = $2 AND is_system = false",
        )
        .bind(id)
        .bind(wallet_id)
        .execute(self.pool)
        .await?;
        Ok(())
    }

    async fn add_contact_group_member(
        &mut self,
        contact_group_id: Uuid,
        contact_id: Uuid,
    ) -> Result<(), Self::Error> {
        sqlx::query(
            r#"
            INSERT INTO contact_group_members (contact_id, contact_group_id)
            VALUES ($1, $2)
            ON CONFLICT (contact_id, contact_group_id) DO NOTHING
            "#,
        )
        .bind(contact_id)
        .bind(contact_group_id)
        .execute(self.pool)
        .await?;
        Ok(())
    }

    async fn remove_contact_group_member(
        &mut self,
        contact_group_id: Uuid,
        contact_id: Uuid,
    ) -> Result<(), Self::Error> {
        sqlx::query(
            "DELETE FROM contact_group_members WHERE contact_id = $1 AND contact_group_id = $2",
        )
        .bind(contact_id)
        .bind(contact_group_id)
        .execute(self.pool)
        .await?;
        Ok(())
    }

    async fn set_permission_matrix_entries(
        &mut self,
        user_group_id: Uuid,
        contact_group_id: Uuid,
        allowed: &[domain::Action],
        denied: &[domain::Action],
    ) -> Result<(), Self::Error> {
        // Resolve `Action` → `permission_actions.id`. The HTTP handler
        // already rejected unknown action names at entry; during replay
        // unknown actions are silently skipped (same defensive posture as
        // the rest of the applier — an old event from a future-version
        // server shouldn't abort replay).
        let mut tx = self.pool.begin().await?;
        sqlx::query(
            "DELETE FROM group_permission_matrix WHERE user_group_id = $1 AND contact_group_id = $2",
        )
        .bind(user_group_id)
        .bind(contact_group_id)
        .execute(&mut *tx)
        .await?;
        for action in allowed {
            let aid: Option<i16> =
                sqlx::query_scalar("SELECT id FROM permission_actions WHERE name = $1")
                    .bind(action.as_str())
                    .fetch_optional(&mut *tx)
                    .await?;
            if let Some(aid) = aid {
                sqlx::query(
                    "INSERT INTO group_permission_matrix (user_group_id, contact_group_id, permission_action_id, is_deny) VALUES ($1, $2, $3, false)"
                )
                .bind(user_group_id)
                .bind(contact_group_id)
                .bind(aid)
                .execute(&mut *tx)
                .await?;
            }
        }
        for action in denied {
            let aid: Option<i16> =
                sqlx::query_scalar("SELECT id FROM permission_actions WHERE name = $1")
                    .bind(action.as_str())
                    .fetch_optional(&mut *tx)
                    .await?;
            if let Some(aid) = aid {
                sqlx::query(
                    "INSERT INTO group_permission_matrix (user_group_id, contact_group_id, permission_action_id, is_deny) VALUES ($1, $2, $3, true)"
                )
                .bind(user_group_id)
                .bind(contact_group_id)
                .bind(aid)
                .execute(&mut *tx)
                .await?;
            }
        }
        tx.commit().await?;
        Ok(())
    }
}
