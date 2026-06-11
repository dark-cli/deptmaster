//! SDK-side implementation of [`resolver::PermissionStore`].
//!
//! Wraps the SDK's process-wide SQLite connection. Each trait method maps
//! to one or two rusqlite queries against the permission tables added in
//! Phase 0.2 step 2. The resolution rules themselves live in
//! `resolver::resolve_actions` / `resolver::permitted_contacts_for_action`;
//! this impl only answers the low-level "what's in the database right
//! now" questions.

use async_trait::async_trait;
use rusqlite::params;
use std::collections::HashSet;
use uuid::Uuid;

use resolver::{MatrixRow, PermissionStore};

use crate::storage::with_db;

pub struct SdkPermissionStore;

impl SdkPermissionStore {
    pub fn new() -> Self {
        Self
    }
}

impl Default for SdkPermissionStore {
    fn default() -> Self {
        Self::new()
    }
}

#[async_trait]
impl PermissionStore for SdkPermissionStore {
    type Error = String;

    async fn is_wallet_owner(
        &self,
        wallet_id: Uuid,
        user_id: Uuid,
    ) -> Result<bool, Self::Error> {
        // SDK doesn't have a wallet_owners table — ownership is carried in
        // wallet_users.role. "owner" role on this row is the signal.
        let wid = wallet_id.to_string();
        let uid = user_id.to_string();
        with_db(|conn| {
            let role: Option<String> = conn
                .query_row(
                    "SELECT role FROM wallet_users WHERE wallet_id = ?1 AND user_id = ?2",
                    params![wid, uid],
                    |r| r.get(0),
                )
                .ok();
            Ok(role.as_deref() == Some("owner"))
        })
    }

    async fn user_group_ids_for_user(
        &self,
        wallet_id: Uuid,
        user_id: Uuid,
    ) -> Result<Vec<Uuid>, Self::Error> {
        let wid = wallet_id.to_string();
        let uid = user_id.to_string();
        with_db(|conn| {
            let mut stmt = conn.prepare(
                r#"
                SELECT ug.id
                  FROM user_groups ug
                 WHERE ug.wallet_id = ?1
                   AND (
                     ug.name = 'all_users'
                     OR EXISTS (
                       SELECT 1 FROM user_group_members ugm
                        WHERE ugm.user_group_id = ug.id AND ugm.user_id = ?2
                     )
                   )
                "#,
            )?;
            let rows = stmt.query_map(params![wid, uid], |r| r.get::<_, String>(0))?;
            let mut ids = Vec::new();
            for row in rows {
                if let Ok(s) = row {
                    if let Ok(u) = Uuid::parse_str(&s) {
                        ids.push(u);
                    }
                }
            }
            Ok(ids)
        })
    }

    async fn matrix_rows_for_user_groups(
        &self,
        wallet_id: Uuid,
        user_group_ids: &[Uuid],
    ) -> Result<Vec<MatrixRow>, Self::Error> {
        if user_group_ids.is_empty() {
            return Ok(Vec::new());
        }
        let wid = wallet_id.to_string();
        // SQLite has no `= ANY($1::uuid[])`. Build an IN (?, ?, ...) list.
        // The list is small (typical wallet has 2-4 user_groups per user).
        let placeholders: Vec<String> =
            (0..user_group_ids.len()).map(|i| format!("?{}", i + 2)).collect();
        let sql = format!(
            r#"
            SELECT m.contact_group_id, cg.name, m.action, m.is_deny
              FROM group_permission_matrix m
              JOIN contact_groups cg ON cg.id = m.contact_group_id AND cg.wallet_id = ?1
             WHERE m.user_group_id IN ({})
            "#,
            placeholders.join(", ")
        );
        let ug_strings: Vec<String> = user_group_ids.iter().map(|u| u.to_string()).collect();
        with_db(|conn| {
            let mut stmt = conn.prepare(&sql)?;
            let mut binds: Vec<&dyn rusqlite::ToSql> = vec![&wid];
            for s in &ug_strings {
                binds.push(s);
            }
            let rows = stmt.query_map(binds.as_slice(), |r| {
                Ok((
                    r.get::<_, String>(0)?,
                    r.get::<_, String>(1)?,
                    r.get::<_, String>(2)?,
                    r.get::<_, i64>(3)? != 0,
                ))
            })?;
            let mut out = Vec::new();
            for row in rows {
                let (cg_id_str, cg_name, action, is_deny) = row?;
                if let Ok(cg_id) = Uuid::parse_str(&cg_id_str) {
                    out.push(MatrixRow {
                        contact_group_id: cg_id,
                        contact_group_name: cg_name,
                        action,
                        is_deny,
                    });
                }
            }
            Ok(out)
        })
    }

    async fn contact_group_ids_for_contact(
        &self,
        contact_id: Uuid,
    ) -> Result<HashSet<Uuid>, Self::Error> {
        let cid = contact_id.to_string();
        with_db(|conn| {
            let mut stmt = conn.prepare(
                "SELECT contact_group_id FROM contact_group_members WHERE contact_id = ?1",
            )?;
            let rows = stmt.query_map(params![cid], |r| r.get::<_, String>(0))?;
            let mut set = HashSet::new();
            for row in rows {
                if let Ok(s) = row {
                    if let Ok(u) = Uuid::parse_str(&s) {
                        set.insert(u);
                    }
                }
            }
            Ok(set)
        })
    }

    async fn all_contact_ids_in_wallet(
        &self,
        wallet_id: Uuid,
    ) -> Result<HashSet<Uuid>, Self::Error> {
        let wid = wallet_id.to_string();
        with_db(|conn| {
            let mut stmt = conn.prepare(
                "SELECT id FROM contacts WHERE wallet_id = ?1 AND is_deleted = 0",
            )?;
            let rows = stmt.query_map(params![wid], |r| r.get::<_, String>(0))?;
            let mut set = HashSet::new();
            for row in rows {
                if let Ok(s) = row {
                    if let Ok(u) = Uuid::parse_str(&s) {
                        set.insert(u);
                    }
                }
            }
            Ok(set)
        })
    }

    async fn contact_ids_in_group(
        &self,
        contact_group_id: Uuid,
    ) -> Result<HashSet<Uuid>, Self::Error> {
        let gid = contact_group_id.to_string();
        with_db(|conn| {
            let mut stmt = conn.prepare(
                "SELECT contact_id FROM contact_group_members WHERE contact_group_id = ?1",
            )?;
            let rows = stmt.query_map(params![gid], |r| r.get::<_, String>(0))?;
            let mut set = HashSet::new();
            for row in rows {
                if let Ok(s) = row {
                    if let Ok(u) = Uuid::parse_str(&s) {
                        set.insert(u);
                    }
                }
            }
            Ok(set)
        })
    }
}
