//! SDK-side implementation of [`applier::Projection`].
//!
//! Covers contact, transaction, and permission events. The SDK keeps
//! its own SQLite mirror of the server's projection tables so that
//! reads (get_contacts / get_transactions / can_perform) can answer
//! locally without round-tripping. The server stays authoritative for
//! enforcement on push.
//!
//! All trait methods are async (the trait is async — server needs it).
//! Each method body wraps a sync `rusqlite` call in `async {}`. No real
//! await is happening; the SDK's storage is process-wide-mutex sync.

use applier::{ContactPatch, Projection, TransactionPatch};
use async_trait::async_trait;
use domain::DomainEvent;
use rusqlite::params;
use uuid::Uuid;

use crate::database::storage::with_db;

#[flutter_rust_bridge::frb(opaque)]
pub struct SdkProjection;

impl SdkProjection {
    pub fn new() -> Self {
        Self
    }
}

impl Default for SdkProjection {
    fn default() -> Self {
        Self::new()
    }
}

#[async_trait]
impl Projection for SdkProjection {
    type Error = String;

    async fn set_event_context(&mut self, _event: &DomainEvent) -> Result<(), Self::Error> {
        Ok(())
    }

    // ---------- Contact / Transaction CRUD ----------
    //
    // Writes to the `contacts` / `transactions` SQLite tables. Mirrors
    // the server: soft delete via `is_deleted` flag, not row removal.

    async fn upsert_contact_row(
        &mut self,
        id: Uuid,
        wallet_id: Uuid,
        _user_id: Uuid,
        name: &str,
        username: Option<&str>,
        phone: Option<&str>,
        email: Option<&str>,
        notes: Option<&str>,
    ) -> Result<(), Self::Error> {
        let now = chrono::Utc::now().to_rfc3339();
        let id_s = id.to_string();
        let wallet_s = wallet_id.to_string();
        let name_s = name.to_string();
        let username = username.map(String::from);
        let phone = phone.map(String::from);
        let email = email.map(String::from);
        let notes = notes.map(String::from);
        with_db(|conn| {
            conn.execute(
                r#"
                INSERT INTO contacts (id, wallet_id, name, username, phone, email, notes,
                                      created_at, updated_at, is_synced)
                VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?8, 1)
                ON CONFLICT(id) DO UPDATE SET
                    name       = excluded.name,
                    username   = excluded.username,
                    phone      = excluded.phone,
                    email      = excluded.email,
                    notes      = excluded.notes,
                    updated_at = excluded.updated_at
                "#,
                params![id_s, wallet_s, name_s, username, phone, email, notes, now],
            )?;
            Ok(())
        })
    }

    async fn update_contact_row(
        &mut self,
        id: Uuid,
        wallet_id: Uuid,
        patch: ContactPatch,
    ) -> Result<(), Self::Error> {
        // SQLite's COALESCE behaves the same as Postgres for our patch
        // semantics: Some(v) overrides, None preserves.
        let now = chrono::Utc::now().to_rfc3339();
        let id_s = id.to_string();
        let wallet_s = wallet_id.to_string();
        with_db(|conn| {
            conn.execute(
                r#"
                UPDATE contacts SET
                    name       = COALESCE(?3, name),
                    username   = COALESCE(?4, username),
                    phone      = COALESCE(?5, phone),
                    email      = COALESCE(?6, email),
                    notes      = COALESCE(?7, notes),
                    updated_at = ?8
                WHERE id = ?1 AND wallet_id = ?2
                "#,
                params![
                    id_s,
                    wallet_s,
                    patch.name,
                    patch.username,
                    patch.phone,
                    patch.email,
                    patch.notes,
                    now
                ],
            )?;
            Ok(())
        })
    }

    async fn soft_delete_contact_row(
        &mut self,
        id: Uuid,
        wallet_id: Uuid,
    ) -> Result<(), Self::Error> {
        let id_s = id.to_string();
        let wallet_s = wallet_id.to_string();
        let now = chrono::Utc::now().to_rfc3339();
        with_db(|conn| {
            conn.execute(
                "UPDATE contacts SET is_deleted = 1, updated_at = ?3 WHERE id = ?1 AND wallet_id = ?2",
                params![id_s, wallet_s, now],
            )?;
            Ok(())
        })
    }

    async fn soft_delete_transactions_for_contact(
        &mut self,
        contact_id: Uuid,
        wallet_id: Uuid,
    ) -> Result<(), Self::Error> {
        let cid = contact_id.to_string();
        let wallet_s = wallet_id.to_string();
        let now = chrono::Utc::now().to_rfc3339();
        with_db(|conn| {
            conn.execute(
                "UPDATE transactions SET is_deleted = 1, updated_at = ?3 WHERE contact_id = ?1 AND wallet_id = ?2 AND is_deleted = 0",
                params![cid, wallet_s, now],
            )?;
            Ok(())
        })
    }

    async fn add_contact_to_system_group(
        &mut self,
        contact_id: Uuid,
        wallet_id: Uuid,
        system_group: domain::SystemGroup,
    ) -> Result<(), Self::Error> {
        // Permission-table touch even on contact creation: the contact
        // needs to be in `all_contacts` for the local permission resolver
        // to find it. (System groups in SDK are seeded by the
        // ContactGroupCreated event for 'all_contacts' on wallet setup —
        // if the group isn't there yet, this no-ops cleanly.)
        let cid = contact_id.to_string();
        let wid = wallet_id.to_string();
        let name = system_group.as_str();
        with_db(|conn| {
            conn.execute(
                r#"
                INSERT OR IGNORE INTO contact_group_members (contact_id, contact_group_id)
                SELECT ?1, cg.id FROM contact_groups cg
                 WHERE cg.wallet_id = ?2 AND cg.name = ?3
                "#,
                params![cid, wid, name],
            )?;
            Ok(())
        })
    }

    async fn add_contact_to_groups(
        &mut self,
        contact_id: Uuid,
        wallet_id: Uuid,
        group_ids: &[Uuid],
    ) -> Result<(), Self::Error> {
        let cid = contact_id.to_string();
        let wid = wallet_id.to_string();
        let gids: Vec<String> = group_ids.iter().map(|g| g.to_string()).collect();
        with_db(|conn| {
            for gid in &gids {
                // Validate the group belongs to this wallet (defensive,
                // matches server). Silent skip otherwise.
                let in_wallet: bool = conn
                    .query_row(
                        "SELECT EXISTS(SELECT 1 FROM contact_groups WHERE id = ?1 AND wallet_id = ?2)",
                        params![gid, wid],
                        |r| r.get::<_, i64>(0).map(|n| n != 0),
                    )
                    .unwrap_or(false);
                if in_wallet {
                    conn.execute(
                        "INSERT OR IGNORE INTO contact_group_members (contact_id, contact_group_id) VALUES (?1, ?2)",
                        params![cid, gid],
                    )?;
                }
            }
            Ok(())
        })
    }

    async fn replace_contact_group_memberships(
        &mut self,
        contact_id: Uuid,
        wallet_id: Uuid,
        group_ids: &[Uuid],
    ) -> Result<(), Self::Error> {
        let cid = contact_id.to_string();
        let wid = wallet_id.to_string();
        with_db(|conn| {
            // Wipe non-all_contacts memberships first; system membership stays.
            conn.execute(
                r#"
                DELETE FROM contact_group_members
                 WHERE contact_id = ?1
                   AND contact_group_id IN (
                     SELECT id FROM contact_groups
                      WHERE wallet_id = ?2 AND name <> 'all_contacts'
                   )
                "#,
                params![cid, wid],
            )?;
            Ok(())
        })?;
        // Then add the new set (validates each id against wallet).
        self.add_contact_to_groups(contact_id, wallet_id, group_ids)
            .await
    }

    async fn contact_is_active(
        &self,
        contact_id: Uuid,
        wallet_id: Uuid,
    ) -> Result<bool, Self::Error> {
        let cid = contact_id.to_string();
        let wallet_s = wallet_id.to_string();
        with_db(|conn| {
            let exists: bool = conn
                .query_row(
                    "SELECT EXISTS(SELECT 1 FROM contacts WHERE id = ?1 AND wallet_id = ?2 AND is_deleted = 0)",
                    params![cid, wallet_s],
                    |r| r.get::<_, i64>(0).map(|n| n != 0),
                )
                .unwrap_or(false);
            Ok(exists)
        })
    }

    async fn upsert_transaction_row(
        &mut self,
        id: Uuid,
        wallet_id: Uuid,
        _user_id: Uuid,
        contact_id: Uuid,
        amount: i64,
        direction: domain::TransactionDirection,
        transaction_type: Option<domain::TransactionType>,
        currency: Option<domain::Currency>,
        description: Option<&str>,
        transaction_date: Option<&str>,
        due_date: Option<&str>,
    ) -> Result<(), Self::Error> {
        let now = chrono::Utc::now().to_rfc3339();
        let id_s = id.to_string();
        let wallet_s = wallet_id.to_string();
        let cid = contact_id.to_string();
        let direction = direction.as_str();
        let tx_type = transaction_type
            .unwrap_or(domain::TransactionType::Money)
            .as_str();
        let currency = currency.unwrap_or(domain::Currency::IQD).as_str();
        let description = description.map(String::from);
        // SDK stores dates as the raw "%Y-%m-%d" strings the wire format
        // carries. Today's date is the fallback when not supplied.
        let txn_date = transaction_date.map(String::from).unwrap_or_else(|| {
            chrono::Utc::now()
                .date_naive()
                .format("%Y-%m-%d")
                .to_string()
        });
        let due_date = due_date.map(String::from);
        with_db(|conn| {
            conn.execute(
                r#"
                INSERT INTO transactions (id, wallet_id, contact_id, type, direction, amount,
                                          currency, description, transaction_date, due_date,
                                          created_at, updated_at, is_synced)
                VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?11, 1)
                ON CONFLICT(id) DO UPDATE SET
                    contact_id       = excluded.contact_id,
                    type             = excluded.type,
                    direction        = excluded.direction,
                    amount           = excluded.amount,
                    currency         = excluded.currency,
                    description      = excluded.description,
                    transaction_date = excluded.transaction_date,
                    due_date         = excluded.due_date,
                    updated_at       = excluded.updated_at
                "#,
                params![
                    id_s,
                    wallet_s,
                    cid,
                    tx_type,
                    direction,
                    amount,
                    currency,
                    description,
                    txn_date,
                    due_date,
                    now
                ],
            )?;
            Ok(())
        })
    }

    async fn update_transaction_row(
        &mut self,
        id: Uuid,
        wallet_id: Uuid,
        patch: TransactionPatch,
    ) -> Result<(), Self::Error> {
        let now = chrono::Utc::now().to_rfc3339();
        let id_s = id.to_string();
        let wallet_s = wallet_id.to_string();
        let contact_id_s = patch.contact_id.map(|u| u.to_string());
        with_db(|conn| {
            conn.execute(
                r#"
                UPDATE transactions SET
                    contact_id       = COALESCE(?3, contact_id),
                    type             = COALESCE(?4, type),
                    direction        = COALESCE(?5, direction),
                    amount           = COALESCE(?6, amount),
                    currency         = COALESCE(?7, currency),
                    description      = COALESCE(?8, description),
                    transaction_date = COALESCE(?9, transaction_date),
                    due_date         = COALESCE(?10, due_date),
                    updated_at       = ?11
                WHERE id = ?1 AND wallet_id = ?2
                "#,
                params![
                    id_s,
                    wallet_s,
                    contact_id_s,
                    patch.transaction_type.map(|t| t.as_str()),
                    patch.direction.map(|d| d.as_str()),
                    patch.amount,
                    patch.currency.map(|c| c.as_str()),
                    patch.description,
                    patch.transaction_date,
                    patch.due_date,
                    now
                ],
            )?;
            Ok(())
        })
    }

    async fn soft_delete_transaction_row(
        &mut self,
        id: Uuid,
        wallet_id: Uuid,
    ) -> Result<(), Self::Error> {
        let id_s = id.to_string();
        let wallet_s = wallet_id.to_string();
        let now = chrono::Utc::now().to_rfc3339();
        with_db(|conn| {
            conn.execute(
                "UPDATE transactions SET is_deleted = 1, updated_at = ?3 WHERE id = ?1 AND wallet_id = ?2",
                params![id_s, wallet_s, now],
            )?;
            Ok(())
        })
    }

    // ---------- Wallet membership ----------

    async fn upsert_wallet_user(
        &mut self,
        wallet_id: Uuid,
        user_id: Uuid,
        role: domain::WalletRole,
    ) -> Result<(), Self::Error> {
        let wid = wallet_id.to_string();
        let uid = user_id.to_string();
        let role_str = role.as_str();
        let is_owner = role.is_owner();
        with_db(|conn| {
            conn.execute(
                r#"
                INSERT INTO wallet_users (wallet_id, user_id, role)
                VALUES (?1, ?2, ?3)
                ON CONFLICT(wallet_id, user_id) DO UPDATE SET role = ?3
                "#,
                params![wid, uid, role_str],
            )?;
            // Mirror role='owner' into wallet_owners. Server tracks
            // ownership in a dedicated table; SDK mirrors so
            // is_wallet_owner can issue the same SQL on both sides.
            if is_owner {
                conn.execute(
                    "INSERT OR IGNORE INTO wallet_owners (wallet_id, user_id) VALUES (?1, ?2)",
                    params![wid, uid],
                )?;
            } else {
                conn.execute(
                    "DELETE FROM wallet_owners WHERE wallet_id = ?1 AND user_id = ?2",
                    params![wid, uid],
                )?;
            }
            Ok(())
        })
    }

    async fn update_wallet_user_role(
        &mut self,
        wallet_id: Uuid,
        user_id: Uuid,
        role: domain::WalletRole,
    ) -> Result<(), Self::Error> {
        let wid = wallet_id.to_string();
        let uid = user_id.to_string();
        let role_str = role.as_str();
        let is_owner = role.is_owner();
        with_db(|conn| {
            conn.execute(
                "UPDATE wallet_users SET role = ?1 WHERE wallet_id = ?2 AND user_id = ?3",
                params![role_str, wid, uid],
            )?;
            if is_owner {
                conn.execute(
                    "INSERT OR IGNORE INTO wallet_owners (wallet_id, user_id) VALUES (?1, ?2)",
                    params![wid, uid],
                )?;
            } else {
                conn.execute(
                    "DELETE FROM wallet_owners WHERE wallet_id = ?1 AND user_id = ?2",
                    params![wid, uid],
                )?;
            }
            Ok(())
        })
    }

    async fn remove_wallet_user(
        &mut self,
        wallet_id: Uuid,
        user_id: Uuid,
    ) -> Result<(), Self::Error> {
        let wid = wallet_id.to_string();
        let uid = user_id.to_string();
        with_db(|conn| {
            conn.execute(
                "DELETE FROM wallet_users WHERE wallet_id = ?1 AND user_id = ?2",
                params![wid, uid],
            )?;
            conn.execute(
                "DELETE FROM wallet_owners WHERE wallet_id = ?1 AND user_id = ?2",
                params![wid, uid],
            )?;
            Ok(())
        })
    }

    async fn add_user_to_system_group(
        &mut self,
        wallet_id: Uuid,
        user_id: Uuid,
        system_group: domain::SystemGroup,
    ) -> Result<(), Self::Error> {
        let wid = wallet_id.to_string();
        let uid = user_id.to_string();
        let name = system_group.as_str();
        with_db(|conn| {
            conn.execute(
                r#"
                INSERT OR IGNORE INTO user_group_members (user_id, user_group_id)
                SELECT ?2, ug.id FROM user_groups ug
                 WHERE ug.wallet_id = ?1 AND ug.name = ?3
                "#,
                params![wid, uid, name],
            )?;
            Ok(())
        })
    }

    // ---------- User groups ----------

    async fn upsert_user_group(
        &mut self,
        id: Uuid,
        wallet_id: Uuid,
        name: &str,
    ) -> Result<(), Self::Error> {
        let id = id.to_string();
        let wid = wallet_id.to_string();
        let name = name.to_string();
        with_db(|conn| {
            conn.execute(
                r#"
                INSERT INTO user_groups (id, wallet_id, name, is_system)
                VALUES (?1, ?2, ?3, 0)
                ON CONFLICT(id) DO UPDATE SET name = ?3
                "#,
                params![id, wid, name],
            )?;
            Ok(())
        })
    }

    async fn rename_user_group(
        &mut self,
        id: Uuid,
        wallet_id: Uuid,
        name: &str,
    ) -> Result<(), Self::Error> {
        let id = id.to_string();
        let wid = wallet_id.to_string();
        let name = name.to_string();
        with_db(|conn| {
            conn.execute(
                "UPDATE user_groups SET name = ?1 WHERE id = ?2 AND wallet_id = ?3 AND is_system = 0",
                params![name, id, wid],
            )?;
            Ok(())
        })
    }

    async fn delete_user_group(&mut self, id: Uuid, wallet_id: Uuid) -> Result<(), Self::Error> {
        let id = id.to_string();
        let wid = wallet_id.to_string();
        with_db(|conn| {
            conn.execute(
                "DELETE FROM user_groups WHERE id = ?1 AND wallet_id = ?2 AND is_system = 0",
                params![id, wid],
            )?;
            Ok(())
        })
    }

    async fn add_user_group_member(
        &mut self,
        user_group_id: Uuid,
        user_id: Uuid,
    ) -> Result<(), Self::Error> {
        let gid = user_group_id.to_string();
        let uid = user_id.to_string();
        with_db(|conn| {
            conn.execute(
                "INSERT OR IGNORE INTO user_group_members (user_id, user_group_id) VALUES (?1, ?2)",
                params![uid, gid],
            )?;
            Ok(())
        })
    }

    async fn remove_user_group_member(
        &mut self,
        user_group_id: Uuid,
        user_id: Uuid,
    ) -> Result<(), Self::Error> {
        let gid = user_group_id.to_string();
        let uid = user_id.to_string();
        with_db(|conn| {
            conn.execute(
                "DELETE FROM user_group_members WHERE user_id = ?1 AND user_group_id = ?2",
                params![uid, gid],
            )?;
            Ok(())
        })
    }

    // ---------- Contact groups ----------

    async fn upsert_contact_group(
        &mut self,
        id: Uuid,
        wallet_id: Uuid,
        name: &str,
    ) -> Result<(), Self::Error> {
        let id = id.to_string();
        let wid = wallet_id.to_string();
        let name = name.to_string();
        with_db(|conn| {
            conn.execute(
                r#"
                INSERT INTO contact_groups (id, wallet_id, name, is_system)
                VALUES (?1, ?2, ?3, 0)
                ON CONFLICT(id) DO UPDATE SET name = ?3
                "#,
                params![id, wid, name],
            )?;
            Ok(())
        })
    }

    async fn rename_contact_group(
        &mut self,
        id: Uuid,
        wallet_id: Uuid,
        name: &str,
    ) -> Result<(), Self::Error> {
        let id = id.to_string();
        let wid = wallet_id.to_string();
        let name = name.to_string();
        with_db(|conn| {
            conn.execute(
                "UPDATE contact_groups SET name = ?1 WHERE id = ?2 AND wallet_id = ?3 AND is_system = 0",
                params![name, id, wid],
            )?;
            Ok(())
        })
    }

    async fn delete_contact_group(&mut self, id: Uuid, wallet_id: Uuid) -> Result<(), Self::Error> {
        let id = id.to_string();
        let wid = wallet_id.to_string();
        with_db(|conn| {
            conn.execute(
                "DELETE FROM contact_groups WHERE id = ?1 AND wallet_id = ?2 AND is_system = 0",
                params![id, wid],
            )?;
            Ok(())
        })
    }

    async fn add_contact_group_member(
        &mut self,
        contact_group_id: Uuid,
        contact_id: Uuid,
    ) -> Result<(), Self::Error> {
        let gid = contact_group_id.to_string();
        let cid = contact_id.to_string();
        with_db(|conn| {
            conn.execute(
                "INSERT OR IGNORE INTO contact_group_members (contact_id, contact_group_id) VALUES (?1, ?2)",
                params![cid, gid],
            )?;
            Ok(())
        })
    }

    async fn remove_contact_group_member(
        &mut self,
        contact_group_id: Uuid,
        contact_id: Uuid,
    ) -> Result<(), Self::Error> {
        let gid = contact_group_id.to_string();
        let cid = contact_id.to_string();
        with_db(|conn| {
            conn.execute(
                "DELETE FROM contact_group_members WHERE contact_id = ?1 AND contact_group_id = ?2",
                params![cid, gid],
            )?;
            Ok(())
        })
    }

    async fn set_permission_matrix_entries(
        &mut self,
        user_group_id: Uuid,
        contact_group_id: Uuid,
        allowed: &[domain::Action],
        denied: &[domain::Action],
    ) -> Result<(), Self::Error> {
        // `with_db` hands out `&Connection`, not `&mut`, so the typed
        // `Connection::transaction()` API isn't available here. The shared
        // STORAGE mutex already serializes writers; we use SAVEPOINT for the
        // intra-statement atomicity so a mid-loop rusqlite error rolls back
        // the partial DELETE+INSERT rather than leaving the pair half-empty.
        // Actions stay typed up to the SQL bind, where `as_str()` lands the
        // canonical wire name into the `action` TEXT column.
        let ug = user_group_id.to_string();
        let cg = contact_group_id.to_string();
        let allowed: Vec<&'static str> = allowed.iter().map(|a| a.as_str()).collect();
        let denied: Vec<&'static str> = denied.iter().map(|a| a.as_str()).collect();
        with_db(move |conn| {
            conn.execute("SAVEPOINT set_matrix", [])?;
            let result: rusqlite::Result<()> = (|| {
                conn.execute(
                    "DELETE FROM group_permission_matrix WHERE user_group_id = ?1 AND contact_group_id = ?2",
                    params![ug, cg],
                )?;
                for name in &allowed {
                    conn.execute(
                        "INSERT INTO group_permission_matrix (user_group_id, contact_group_id, action, is_deny) VALUES (?1, ?2, ?3, 0)",
                        params![ug, cg, name],
                    )?;
                }
                for name in &denied {
                    conn.execute(
                        "INSERT INTO group_permission_matrix (user_group_id, contact_group_id, action, is_deny) VALUES (?1, ?2, ?3, 1)",
                        params![ug, cg, name],
                    )?;
                }
                Ok(())
            })();
            match result {
                Ok(()) => {
                    conn.execute("RELEASE set_matrix", [])?;
                    Ok(())
                }
                Err(e) => {
                    let _ = conn.execute("ROLLBACK TO set_matrix", []);
                    let _ = conn.execute("RELEASE set_matrix", []);
                    Err(e)
                }
            }
        })
    }
}
