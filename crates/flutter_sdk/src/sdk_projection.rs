//! SDK-side implementation of [`applier::Projection`].
//!
//! Today it covers ONLY permission events (wallet membership, user/contact
//! groups, group memberships). Contact and transaction events stay in
//! [`crate::state_builder`] for now — those still compute the
//! `Vec<Contact>` / `Vec<Transaction>` projection from the events table,
//! serialized into the `state` JSON blob. A future step will fold them
//! into this impl too and SDK will get proper contacts / transactions
//! tables in SQLite.
//!
//! Permission events DO need to land in real SQLite tables because the
//! SDK uses them to resolve permissions locally for UX feedback (greying
//! out buttons the user can't tap, etc.). The server stays authoritative
//! for enforcement on push.
//!
//! All trait methods are async (the trait is async — server needs it).
//! Each method body wraps a sync `rusqlite` call in `async {}`. No real
//! await is happening; the SDK's storage is process-wide-mutex sync.

use applier::{ContactPatch, Projection, TransactionPatch};
use async_trait::async_trait;
use domain::DomainEvent;
use rusqlite::params;
use uuid::Uuid;

use crate::storage::with_db;

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

    // ---------- Contact / Transaction CRUD: STUBS ----------
    //
    // state_builder.rs still owns these — when migrated, replace with
    // real SQLite calls into per-wallet contacts / transactions tables.

    async fn upsert_contact_row(
        &mut self,
        _id: Uuid,
        _wallet_id: Uuid,
        _user_id: Uuid,
        _name: &str,
        _username: Option<&str>,
        _phone: Option<&str>,
        _email: Option<&str>,
        _notes: Option<&str>,
    ) -> Result<(), Self::Error> {
        Ok(())
    }

    async fn update_contact_row(
        &mut self,
        _id: Uuid,
        _wallet_id: Uuid,
        _patch: ContactPatch,
    ) -> Result<(), Self::Error> {
        Ok(())
    }

    async fn soft_delete_contact_row(
        &mut self,
        _id: Uuid,
        _wallet_id: Uuid,
    ) -> Result<(), Self::Error> {
        Ok(())
    }

    async fn soft_delete_transactions_for_contact(
        &mut self,
        _contact_id: Uuid,
        _wallet_id: Uuid,
    ) -> Result<(), Self::Error> {
        Ok(())
    }

    async fn add_contact_to_system_group(
        &mut self,
        contact_id: Uuid,
        wallet_id: Uuid,
        system_group_name: &str,
    ) -> Result<(), Self::Error> {
        // Permission-table touch even on contact creation: the contact
        // needs to be in `all_contacts` for the local permission resolver
        // to find it. (System groups in SDK are seeded by the
        // ContactGroupCreated event for 'all_contacts' on wallet setup —
        // if the group isn't there yet, this no-ops cleanly.)
        let cid = contact_id.to_string();
        let wid = wallet_id.to_string();
        let name = system_group_name.to_string();
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
        _contact_id: Uuid,
        _wallet_id: Uuid,
    ) -> Result<bool, Self::Error> {
        // SDK doesn't track contact tombstones in SQLite yet. Treat all
        // contacts as active so TransactionCreated never silently skips
        // events — matches the pre-applier SDK behavior (state_builder
        // never had this check). Replace with a real query once
        // contacts move into a proper SQLite table.
        Ok(true)
    }

    async fn upsert_transaction_row(
        &mut self,
        _id: Uuid,
        _wallet_id: Uuid,
        _user_id: Uuid,
        _contact_id: Uuid,
        _amount: i64,
        _direction: &str,
        _transaction_type: Option<&str>,
        _currency: Option<&str>,
        _description: Option<&str>,
        _transaction_date: Option<&str>,
        _due_date: Option<&str>,
    ) -> Result<(), Self::Error> {
        Ok(())
    }

    async fn update_transaction_row(
        &mut self,
        _id: Uuid,
        _wallet_id: Uuid,
        _patch: TransactionPatch,
    ) -> Result<(), Self::Error> {
        Ok(())
    }

    async fn soft_delete_transaction_row(
        &mut self,
        _id: Uuid,
        _wallet_id: Uuid,
    ) -> Result<(), Self::Error> {
        Ok(())
    }

    // ---------- Wallet membership ----------

    async fn upsert_wallet_user(
        &mut self,
        wallet_id: Uuid,
        user_id: Uuid,
        role: &str,
    ) -> Result<(), Self::Error> {
        let wid = wallet_id.to_string();
        let uid = user_id.to_string();
        let role = role.to_string();
        with_db(|conn| {
            conn.execute(
                r#"
                INSERT INTO wallet_users (wallet_id, user_id, role)
                VALUES (?1, ?2, ?3)
                ON CONFLICT(wallet_id, user_id) DO UPDATE SET role = ?3
                "#,
                params![wid, uid, role],
            )?;
            Ok(())
        })
    }

    async fn update_wallet_user_role(
        &mut self,
        wallet_id: Uuid,
        user_id: Uuid,
        role: &str,
    ) -> Result<(), Self::Error> {
        let wid = wallet_id.to_string();
        let uid = user_id.to_string();
        let role = role.to_string();
        with_db(|conn| {
            conn.execute(
                "UPDATE wallet_users SET role = ?1 WHERE wallet_id = ?2 AND user_id = ?3",
                params![role, wid, uid],
            )?;
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
            Ok(())
        })
    }

    async fn add_user_to_system_group(
        &mut self,
        wallet_id: Uuid,
        user_id: Uuid,
        system_group_name: &str,
    ) -> Result<(), Self::Error> {
        let wid = wallet_id.to_string();
        let uid = user_id.to_string();
        let name = system_group_name.to_string();
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

    async fn delete_user_group(
        &mut self,
        id: Uuid,
        wallet_id: Uuid,
    ) -> Result<(), Self::Error> {
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

    async fn delete_contact_group(
        &mut self,
        id: Uuid,
        wallet_id: Uuid,
    ) -> Result<(), Self::Error> {
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
}
