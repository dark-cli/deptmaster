//! Server-side implementation of [`resolver::PermissionStore`].
//!
//! Each trait method maps to one or two sqlx queries against the server's
//! permission projection tables. The resolution rules themselves live in
//! `resolver::resolve_actions` / `resolver::permitted_contacts_for_action`
//! (pure Rust); this impl just answers the low-level "what's in the
//! database right now" questions the rules ask.

use async_trait::async_trait;
use sqlx::PgPool;
use std::collections::HashSet;
use uuid::Uuid;

use resolver::{MatrixRow, PermissionStore};

use crate::database::error::DbError;

pub struct ServerPermissionStore<'a> {
    pub pool: &'a PgPool,
}

impl<'a> ServerPermissionStore<'a> {
    pub fn new(pool: &'a PgPool) -> Self {
        Self { pool }
    }
}

#[async_trait]
impl<'a> PermissionStore for ServerPermissionStore<'a> {
    type Error = DbError;

    async fn is_wallet_owner(
        &self,
        wallet_id: Uuid,
        user_id: Uuid,
    ) -> Result<bool, Self::Error> {
        let is_owner: bool = sqlx::query_scalar(
            "SELECT EXISTS(SELECT 1 FROM wallet_owners WHERE wallet_id = $1 AND user_id = $2)",
        )
        .bind(wallet_id)
        .bind(user_id)
        .fetch_one(self.pool)
        .await
        .map_err(|e| DbError::PermissionResolution(e.to_string()))?;
        Ok(is_owner)
    }

    async fn user_group_ids_for_user(
        &self,
        wallet_id: Uuid,
        user_id: Uuid,
    ) -> Result<Vec<Uuid>, Self::Error> {
        // Every wallet member is implicitly in `all_users`; explicit
        // memberships come from user_group_members.
        let ids: Vec<Uuid> = sqlx::query_scalar(
            r#"
            SELECT ug.id
              FROM user_groups ug
             WHERE ug.wallet_id = $1
               AND (
                 ug.name = 'all_users'
                 OR EXISTS (
                   SELECT 1 FROM user_group_members ugm
                    WHERE ugm.user_group_id = ug.id AND ugm.user_id = $2
                 )
               )
            "#,
        )
        .bind(wallet_id)
        .bind(user_id)
        .fetch_all(self.pool)
        .await
        .map_err(|e| DbError::PermissionResolution(e.to_string()))?;
        Ok(ids)
    }

    async fn matrix_rows_for_user_groups(
        &self,
        wallet_id: Uuid,
        user_group_ids: &[Uuid],
    ) -> Result<Vec<MatrixRow>, Self::Error> {
        if user_group_ids.is_empty() {
            return Ok(Vec::new());
        }
        let rows: Vec<(Uuid, String, String, bool)> = sqlx::query_as(
            r#"
            SELECT m.contact_group_id, cg.name, pa.name, m.is_deny
              FROM group_permission_matrix m
              JOIN contact_groups cg ON cg.id = m.contact_group_id AND cg.wallet_id = $1
              JOIN permission_actions pa ON pa.id = m.permission_action_id
             WHERE m.user_group_id = ANY($2::uuid[])
            "#,
        )
        .bind(wallet_id)
        .bind(user_group_ids)
        .fetch_all(self.pool)
        .await
        .map_err(|e| DbError::PermissionResolution(e.to_string()))?;
        Ok(rows
            .into_iter()
            .map(|(cg_id, cg_name, action, is_deny)| MatrixRow {
                contact_group_id: cg_id,
                contact_group_name: cg_name,
                action,
                is_deny,
            })
            .collect())
    }

    async fn contact_group_ids_for_contact(
        &self,
        contact_id: Uuid,
    ) -> Result<HashSet<Uuid>, Self::Error> {
        let ids: Vec<Uuid> = sqlx::query_scalar(
            "SELECT contact_group_id FROM contact_group_members WHERE contact_id = $1",
        )
        .bind(contact_id)
        .fetch_all(self.pool)
        .await
        .map_err(|e| DbError::PermissionResolution(e.to_string()))?;
        Ok(ids.into_iter().collect())
    }

    async fn all_contact_ids_in_wallet(
        &self,
        wallet_id: Uuid,
    ) -> Result<HashSet<Uuid>, Self::Error> {
        let ids: Vec<Uuid> =
            sqlx::query_scalar("SELECT id FROM contacts_projection WHERE wallet_id = $1")
                .bind(wallet_id)
                .fetch_all(self.pool)
                .await
                .map_err(|e| DbError::PermissionResolution(e.to_string()))?;
        Ok(ids.into_iter().collect())
    }

    async fn contact_ids_in_group(
        &self,
        contact_group_id: Uuid,
    ) -> Result<HashSet<Uuid>, Self::Error> {
        let ids: Vec<Uuid> = sqlx::query_scalar(
            "SELECT contact_id FROM contact_group_members WHERE contact_group_id = $1",
        )
        .bind(contact_group_id)
        .fetch_all(self.pool)
        .await
        .map_err(|e| DbError::PermissionResolution(e.to_string()))?;
        Ok(ids.into_iter().collect())
    }
}
