use crate::database::error::DbError;
use crate::database::models::*;
use crate::database::repository::{Database, hash::UserEventHash};
use sqlx::Row;
use uuid::Uuid;

impl Database {
    pub async fn get_user_groups_impl(&self, wallet_id: Uuid) -> Result<Vec<UserGroup>, DbError> {
        let groups = sqlx::query_as::<_, UserGroup>(
            r#"
            SELECT id, wallet_id, name, created_at
            FROM user_groups
            WHERE wallet_id = $1
            ORDER BY created_at ASC
            "#,
        )
        .bind(wallet_id)
        .fetch_all(&self.pool)
        .await?;

        Ok(groups)
    }

    pub async fn get_contact_groups_impl(
        &self,
        wallet_id: Uuid,
    ) -> Result<Vec<ContactGroup>, DbError> {
        let groups = sqlx::query_as::<_, ContactGroup>(
            r#"
            SELECT id, wallet_id, name, created_at
            FROM contact_groups
            WHERE wallet_id = $1
            ORDER BY created_at ASC
            "#,
        )
        .bind(wallet_id)
        .fetch_all(&self.pool)
        .await?;

        Ok(groups)
    }

    pub async fn get_user_group_ids_impl(
        &self,
        wallet_id: Uuid,
        user_id: Uuid,
    ) -> Result<Vec<Uuid>, DbError> {
        let ids = sqlx::query_scalar::<_, Uuid>(
            r#"
            SELECT DISTINCT ugm.user_group_id
            FROM user_group_members ugm
            INNER JOIN user_groups ug ON ugm.user_group_id = ug.id
            WHERE ug.wallet_id = $1 AND ugm.user_id = $2
            "#,
        )
        .bind(wallet_id)
        .bind(user_id)
        .fetch_all(&self.pool)
        .await?;

        Ok(ids)
    }

    pub async fn get_contact_group_ids_impl(
        &self,
        wallet_id: Uuid,
        contact_id: Uuid,
    ) -> Result<Vec<Uuid>, DbError> {
        let ids = sqlx::query_scalar::<_, Uuid>(
            r#"
            SELECT DISTINCT cgm.contact_group_id
            FROM contact_group_members cgm
            INNER JOIN contact_groups cg ON cgm.contact_group_id = cg.id
            WHERE cg.wallet_id = $1 AND cgm.contact_id = $2
            "#,
        )
        .bind(wallet_id)
        .bind(contact_id)
        .fetch_all(&self.pool)
        .await?;

        Ok(ids)
    }

    pub async fn get_group_permission_matrix_impl(
        &self,
        wallet_id: Uuid,
        user_group_id: Uuid,
        contact_group_id: Uuid,
    ) -> Result<Vec<String>, DbError> {
        let actions = sqlx::query_scalar::<_, String>(
            r#"
            SELECT action
            FROM group_permission_matrix gpm
            INNER JOIN permission_actions pa ON gpm.permission_action_id = pa.id
            WHERE gpm.wallet_id = $1
              AND gpm.user_group_id = $2
              AND gpm.contact_group_id = $3
            ORDER BY pa.action ASC
            "#,
        )
        .bind(wallet_id)
        .bind(user_group_id)
        .bind(contact_group_id)
        .fetch_all(&self.pool)
        .await?;

        Ok(actions)
    }

    pub async fn sync_contact_group_members_impl(
        &self,
        wallet_id: Uuid,
        contact_id: Uuid,
        group_ids: Vec<Uuid>,
    ) -> Result<(), DbError> {
        // Delete all existing memberships for this contact in this wallet
        sqlx::query(
            r#"
            DELETE FROM contact_group_members
            WHERE contact_id = $1
              AND contact_group_id IN (
                SELECT id FROM contact_groups WHERE wallet_id = $2
              )
            "#,
        )
        .bind(contact_id)
        .bind(wallet_id)
        .execute(&self.pool)
        .await?;

        // Insert new memberships
        for group_id in group_ids {
            sqlx::query(
                r#"
                INSERT INTO contact_group_members (contact_id, contact_group_id)
                VALUES ($1, $2)
                ON CONFLICT (contact_id, contact_group_id) DO NOTHING
                "#,
            )
            .bind(contact_id)
            .bind(group_id)
            .execute(&self.pool)
            .await?;
        }

        Ok(())
    }

    // User group operations
    pub async fn create_user_group_impl(
        &self,
        wallet_id: Uuid,
        name: &str,
        is_system: bool,
    ) -> Result<Uuid, DbError> {
        let id = Uuid::new_v4();
        sqlx::query(
            r#"
            INSERT INTO user_groups (id, wallet_id, name, is_system)
            VALUES ($1, $2, $3, $4)
            ON CONFLICT (wallet_id, name) DO NOTHING
            "#,
        )
        .bind(id)
        .bind(wallet_id)
        .bind(name)
        .bind(is_system)
        .execute(&self.pool)
        .await?;
        Ok(id)
    }

    pub async fn get_user_group_impl(
        &self,
        group_id: Uuid,
        wallet_id: Uuid,
    ) -> Result<Option<(Uuid, String, bool)>, DbError> {
        let row = sqlx::query_as::<_, (Uuid, String, bool)>(
            "SELECT id, name, is_system FROM user_groups WHERE id = $1 AND wallet_id = $2",
        )
        .bind(group_id)
        .bind(wallet_id)
        .fetch_optional(&self.pool)
        .await?;
        Ok(row)
    }

    pub async fn get_user_group_by_name_impl(
        &self,
        wallet_id: Uuid,
        name: &str,
    ) -> Result<Option<Uuid>, DbError> {
        let id = sqlx::query_scalar::<_, Uuid>(
            "SELECT id FROM user_groups WHERE wallet_id = $1 AND name = $2 LIMIT 1",
        )
        .bind(wallet_id)
        .bind(name)
        .fetch_optional(&self.pool)
        .await?;
        Ok(id)
    }

    pub async fn list_user_groups_impl(
        &self,
        wallet_id: Uuid,
    ) -> Result<Vec<(Uuid, String, bool)>, DbError> {
        let groups = sqlx::query_as::<_, (Uuid, String, bool)>(
            "SELECT id, name, is_system FROM user_groups WHERE wallet_id = $1 ORDER BY is_system DESC, name"
        )
        .bind(wallet_id)
        .fetch_all(&self.pool)
        .await?;
        Ok(groups)
    }

    pub async fn delete_user_group_impl(
        &self,
        group_id: Uuid,
        wallet_id: Uuid,
    ) -> Result<bool, DbError> {
        let result = sqlx::query(
            "DELETE FROM user_groups WHERE id = $1 AND wallet_id = $2 AND is_system = false",
        )
        .bind(group_id)
        .bind(wallet_id)
        .execute(&self.pool)
        .await?;
        Ok(result.rows_affected() > 0)
    }

    pub async fn list_user_group_members_impl(
        &self,
        group_id: Uuid,
        wallet_id: Uuid,
    ) -> Result<Vec<(Uuid, Option<String>)>, DbError> {
        let members = sqlx::query_as::<_, (Uuid, Option<String>)>(
            r#"
            SELECT ugm.user_id, u.username
            FROM user_group_members ugm
            INNER JOIN user_groups ug ON ug.id = ugm.user_group_id
            LEFT JOIN users_projection u ON u.id = ugm.user_id
            WHERE ug.id = $1 AND ug.wallet_id = $2
            "#,
        )
        .bind(group_id)
        .bind(wallet_id)
        .fetch_all(&self.pool)
        .await?;
        Ok(members)
    }

    pub async fn add_user_group_member_impl(
        &self,
        group_id: Uuid,
        user_id: Uuid,
    ) -> Result<(), DbError> {
        sqlx::query(
            "INSERT INTO user_group_members (user_id, user_group_id) VALUES ($1, $2) ON CONFLICT DO NOTHING"
        )
        .bind(user_id)
        .bind(group_id)
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    pub async fn remove_user_group_member_impl(
        &self,
        group_id: Uuid,
        user_id: Uuid,
    ) -> Result<bool, DbError> {
        let result =
            sqlx::query("DELETE FROM user_group_members WHERE user_group_id = $1 AND user_id = $2")
                .bind(group_id)
                .bind(user_id)
                .execute(&self.pool)
                .await?;
        Ok(result.rows_affected() > 0)
    }

    // Contact group operations
    pub async fn create_contact_group_impl(
        &self,
        wallet_id: Uuid,
        name: &str,
        group_type: &str,
        is_system: bool,
    ) -> Result<Uuid, DbError> {
        let id = Uuid::new_v4();
        sqlx::query(
            r#"
            INSERT INTO contact_groups (id, wallet_id, name, type, is_system)
            VALUES ($1, $2, $3, $4, $5)
            ON CONFLICT (wallet_id, name) DO NOTHING
            "#,
        )
        .bind(id)
        .bind(wallet_id)
        .bind(name)
        .bind(group_type)
        .bind(is_system)
        .execute(&self.pool)
        .await?;
        Ok(id)
    }

    pub async fn get_contact_group_impl(
        &self,
        group_id: Uuid,
        wallet_id: Uuid,
    ) -> Result<Option<(Uuid, String, String, bool)>, DbError> {
        let row = sqlx::query_as::<_, (Uuid, String, String, bool)>(
            "SELECT id, name, type, is_system FROM contact_groups WHERE id = $1 AND wallet_id = $2",
        )
        .bind(group_id)
        .bind(wallet_id)
        .fetch_optional(&self.pool)
        .await?;
        Ok(row)
    }

    pub async fn get_contact_group_by_name_impl(
        &self,
        wallet_id: Uuid,
        name: &str,
    ) -> Result<Option<Uuid>, DbError> {
        let id = sqlx::query_scalar::<_, Uuid>(
            "SELECT id FROM contact_groups WHERE wallet_id = $1 AND name = $2 LIMIT 1",
        )
        .bind(wallet_id)
        .bind(name)
        .fetch_optional(&self.pool)
        .await?;
        Ok(id)
    }

    pub async fn list_contact_groups_impl(
        &self,
        wallet_id: Uuid,
    ) -> Result<Vec<(Uuid, String, String, bool)>, DbError> {
        let groups = sqlx::query_as::<_, (Uuid, String, String, bool)>(
            "SELECT id, name, type, is_system FROM contact_groups WHERE wallet_id = $1 ORDER BY is_system DESC, name"
        )
        .bind(wallet_id)
        .fetch_all(&self.pool)
        .await?;
        Ok(groups)
    }

    pub async fn delete_contact_group_impl(
        &self,
        group_id: Uuid,
        wallet_id: Uuid,
    ) -> Result<bool, DbError> {
        let result = sqlx::query(
            "DELETE FROM contact_groups WHERE id = $1 AND wallet_id = $2 AND is_system = false",
        )
        .bind(group_id)
        .bind(wallet_id)
        .execute(&self.pool)
        .await?;
        Ok(result.rows_affected() > 0)
    }

    pub async fn list_contact_group_members_impl(
        &self,
        group_id: Uuid,
        wallet_id: Uuid,
    ) -> Result<Vec<Uuid>, DbError> {
        let members = sqlx::query_scalar::<_, Uuid>(
            r#"
            SELECT cgm.contact_id
            FROM contact_group_members cgm
            INNER JOIN contact_groups cg ON cg.id = cgm.contact_group_id
            WHERE cg.id = $1 AND cg.wallet_id = $2
            "#,
        )
        .bind(group_id)
        .bind(wallet_id)
        .fetch_all(&self.pool)
        .await?;
        Ok(members)
    }

    // Permission actions and matrix
    pub async fn get_permission_action_id_impl(&self, name: &str) -> Result<Option<i16>, DbError> {
        let id = sqlx::query_scalar::<_, i16>("SELECT id FROM permission_actions WHERE name = $1")
            .bind(name)
            .fetch_optional(&self.pool)
            .await?;
        Ok(id)
    }

    pub async fn get_all_permission_actions_impl(
        &self,
    ) -> Result<Vec<(i16, String, String)>, DbError> {
        let actions = sqlx::query_as::<_, (i16, String, String)>(
            "SELECT id, name, resource FROM permission_actions ORDER BY resource, name",
        )
        .fetch_all(&self.pool)
        .await?;
        Ok(actions)
    }

    pub async fn grant_permission_impl(
        &self,
        user_group_id: Uuid,
        contact_group_id: Uuid,
        action_id: i16,
    ) -> Result<(), DbError> {
        sqlx::query(
            "INSERT INTO group_permission_matrix (user_group_id, contact_group_id, permission_action_id) VALUES ($1, $2, $3) ON CONFLICT DO NOTHING"
        )
        .bind(user_group_id)
        .bind(contact_group_id)
        .bind(action_id)
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    pub async fn revoke_permission_impl(
        &self,
        user_group_id: Uuid,
        contact_group_id: Uuid,
        action_id: i16,
    ) -> Result<bool, DbError> {
        let result = sqlx::query(
            "DELETE FROM group_permission_matrix WHERE user_group_id = $1 AND contact_group_id = $2 AND permission_action_id = $3"
        )
        .bind(user_group_id)
        .bind(contact_group_id)
        .bind(action_id)
        .execute(&self.pool)
        .await?;
        Ok(result.rows_affected() > 0)
    }

    // Utility checks
    pub async fn user_group_in_wallet_impl(
        &self,
        group_id: Uuid,
        wallet_id: Uuid,
    ) -> Result<bool, DbError> {
        let exists = sqlx::query_scalar::<_, bool>(
            "SELECT EXISTS(SELECT 1 FROM user_groups WHERE id = $1 AND wallet_id = $2)",
        )
        .bind(group_id)
        .bind(wallet_id)
        .fetch_one(&self.pool)
        .await?;
        Ok(exists)
    }

    pub async fn contact_group_in_wallet_impl(
        &self,
        group_id: Uuid,
        wallet_id: Uuid,
    ) -> Result<bool, DbError> {
        let exists = sqlx::query_scalar::<_, bool>(
            "SELECT EXISTS(SELECT 1 FROM contact_groups WHERE id = $1 AND wallet_id = $2)",
        )
        .bind(group_id)
        .bind(wallet_id)
        .fetch_one(&self.pool)
        .await?;
        Ok(exists)
    }

    pub async fn get_permission_matrix_impl(
        &self,
        wallet_id: Uuid,
    ) -> Result<Vec<(Uuid, Uuid, Vec<String>)>, DbError> {
        let rows = sqlx::query(
            r#"
            SELECT m.user_group_id, m.contact_group_id,
                   array_agg(pa.name ORDER BY pa.name) as action_names
            FROM group_permission_matrix m
            JOIN permission_actions pa ON pa.id = m.permission_action_id
            JOIN user_groups ug ON ug.id = m.user_group_id AND ug.wallet_id = $1
            JOIN contact_groups cg ON cg.id = m.contact_group_id AND cg.wallet_id = $1
            GROUP BY m.user_group_id, m.contact_group_id
            "#,
        )
        .bind(wallet_id)
        .fetch_all(&self.pool)
        .await?;

        let result = rows
            .into_iter()
            .map(|row| {
                let user_group_id: Uuid = row.get("user_group_id");
                let contact_group_id: Uuid = row.get("contact_group_id");
                let action_names: Vec<String> = row.get("action_names");
                (user_group_id, contact_group_id, action_names)
            })
            .collect();

        Ok(result)
    }

    // User readable events - denormalized cache for efficient sync hash/events queries
    // Also updates incremental hash via UserEventHash private API
    pub async fn add_readable_event_impl(
        &self,
        wallet_id: Uuid,
        user_id: Uuid,
        event_id: Uuid,
    ) -> Result<(), DbError> {
        sqlx::query(
            r#"
            INSERT INTO user_readable_events (wallet_id, user_id, event_id)
            VALUES ($1, $2, $3)
            ON CONFLICT (wallet_id, user_id, event_id) DO NOTHING
            "#,
        )
        .bind(wallet_id)
        .bind(user_id)
        .bind(event_id)
        .execute(&self.pool)
        .await?;

        // Update incremental hash (private API called on readable events change)
        let _ = UserEventHash::calculate_and_store(&self.pool, wallet_id, user_id, event_id).await;

        Ok(())
    }

    pub async fn delete_readable_events_for_user_impl(
        &self,
        wallet_id: Uuid,
        user_id: Uuid,
    ) -> Result<(), DbError> {
        sqlx::query(
            "DELETE FROM user_readable_events WHERE wallet_id = $1 AND user_id = $2",
        )
        .bind(wallet_id)
        .bind(user_id)
        .execute(&self.pool)
        .await?;

        // Reset hash when cache is cleared (private API)
        UserEventHash::reset(&self.pool, wallet_id, user_id).await?;

        Ok(())
    }

    pub async fn get_readable_event_ids_for_user_impl(
        &self,
        wallet_id: Uuid,
        user_id: Uuid,
    ) -> Result<Vec<Uuid>, DbError> {
        let ids = sqlx::query_scalar::<_, Uuid>(
            r#"
            SELECT event_id
            FROM user_readable_events
            WHERE wallet_id = $1 AND user_id = $2
            ORDER BY created_at ASC
            "#,
        )
        .bind(wallet_id)
        .bind(user_id)
        .fetch_all(&self.pool)
        .await?;
        Ok(ids)
    }

    pub async fn get_wallet_users_impl(
        &self,
        wallet_id: Uuid,
    ) -> Result<Vec<(Uuid, String)>, DbError> {
        let users = sqlx::query_as::<_, (Uuid, String)>(
            "SELECT user_id, role FROM wallet_users WHERE wallet_id = $1",
        )
        .bind(wallet_id)
        .fetch_all(&self.pool)
        .await?;
        Ok(users)
    }

    pub async fn get_sync_hash_data_impl(
        &self,
        wallet_id: Uuid,
        user_id: Uuid,
    ) -> Result<(String, i64, Option<chrono::NaiveDateTime>), DbError> {
        let row: (String, i64, Option<chrono::NaiveDateTime>) = sqlx::query_as(
            r#"
            SELECT
              COALESCE(ueh.hash, '') as hash,
              COUNT(ure.event_id) as event_count,
              MAX(e.created_at) as last_timestamp
            FROM user_event_hashes ueh
            LEFT JOIN user_readable_events ure ON ueh.wallet_id = ure.wallet_id AND ueh.user_id = ure.user_id
            LEFT JOIN events e ON ure.event_id = e.event_id
            WHERE ueh.wallet_id = $1 AND ueh.user_id = $2
            GROUP BY ueh.hash
            "#,
        )
        .bind(wallet_id)
        .bind(user_id)
        .fetch_optional(&self.pool)
        .await?
        .unwrap_or((String::new(), 0, None));

        Ok(row)
    }

    pub async fn rebuild_readable_events_for_user_impl(
        &self,
        wallet_id: Uuid,
        user_id: Uuid,
    ) -> Result<(), DbError> {
        // Delete all existing readable events for this user
        self.delete_readable_events_for_user_impl(wallet_id, user_id)
            .await?;

        // For now, return - rebuilding requires permission model which creates a circular dependency
        // In practice, this will be called from handlers after permission changes
        Ok(())
    }

    // ============ PERMISSION MATRIX CACHE ============

    /// Compute and cache the permission matrix for a user.
    ///
    /// This is called when:
    /// 1. User is added to wallet (WalletUserAdded event)
    /// 2. Permission events are processed (PermissionMatrixSet, UserGroupMemberAdded/Removed, etc.)
    ///
    /// The matrix maps: user → { contact_group → { allowed_actions } }
    /// This replaces expensive JOIN calculations with O(1) cache lookups.
    pub async fn compute_and_cache_user_permission_matrix(
        &self,
        wallet_id: Uuid,
        user_id: Uuid,
    ) -> Result<(), DbError> {
        // Step 1: Delete old cache for this user
        sqlx::query(
            "DELETE FROM user_permission_matrix_cache WHERE wallet_id = $1 AND user_id = $2",
        )
        .bind(wallet_id)
        .bind(user_id)
        .execute(&self.pool)
        .await?;

        // Step 2: Compute new matrix from user_groups → group_permission_matrix → contact_groups
        // This query:
        // - Gets all user groups the user belongs to
        // - Gets all permissions those groups have on contact groups
        // - Inserts into cache table
        sqlx::query(
            r#"
            INSERT INTO user_permission_matrix_cache
            (wallet_id, user_id, contact_group_id, permission_action_id, is_deny)
            SELECT $1, $2, m.contact_group_id, m.permission_action_id, m.is_deny
            FROM user_group_members ugm
            JOIN user_groups ug ON ug.id = ugm.user_group_id
            JOIN group_permission_matrix m ON m.user_group_id = ug.id
            WHERE ug.wallet_id = $1 AND ugm.user_id = $2
            ON CONFLICT (wallet_id, user_id, contact_group_id, permission_action_id)
            DO UPDATE SET is_deny = EXCLUDED.is_deny
            "#,
        )
        .bind(wallet_id)
        .bind(user_id)
        .execute(&self.pool)
        .await?;

        Ok(())
    }

    /// Fetch cached permission matrix for a user.
    ///
    /// Returns: HashMap<contact_group_id, HashMap<action_id, is_deny>>
    /// Used by: PermissionModel to make allow/deny decisions
    pub async fn get_user_permission_matrix_impl(
        &self,
        wallet_id: Uuid,
        user_id: Uuid,
    ) -> Result<std::collections::HashMap<Uuid, Vec<(i16, bool)>>, DbError> {
        let rows = sqlx::query(
            r#"
            SELECT contact_group_id, permission_action_id, is_deny
            FROM user_permission_matrix_cache
            WHERE wallet_id = $1 AND user_id = $2
            ORDER BY contact_group_id, permission_action_id
            "#,
        )
        .bind(wallet_id)
        .bind(user_id)
        .fetch_all(&self.pool)
        .await?;

        let mut result: std::collections::HashMap<Uuid, Vec<(i16, bool)>> =
            std::collections::HashMap::new();

        for row in rows {
            let contact_group_id: Uuid = row.get("contact_group_id");
            let action_id: i16 = row.get("permission_action_id");
            let is_deny: bool = row.get("is_deny");

            result
                .entry(contact_group_id)
                .or_insert_with(Vec::new)
                .push((action_id, is_deny));
        }

        Ok(result)
    }

    /// Invalidate permission matrix cache for a user.
    /// Called when permission events occur that might affect this user.
    pub async fn invalidate_permission_matrix_cache(
        &self,
        wallet_id: Uuid,
        user_id: Uuid,
    ) -> Result<(), DbError> {
        sqlx::query(
            "DELETE FROM user_permission_matrix_cache WHERE wallet_id = $1 AND user_id = $2",
        )
        .bind(wallet_id)
        .bind(user_id)
        .execute(&self.pool)
        .await?;

        Ok(())
    }

    /// Invalidate permission matrix cache for all users in a wallet.
    /// Called when global permission changes occur (e.g., contact_group changes).
    pub async fn invalidate_permission_matrix_cache_for_wallet(
        &self,
        wallet_id: Uuid,
    ) -> Result<(), DbError> {
        sqlx::query("DELETE FROM user_permission_matrix_cache WHERE wallet_id = $1")
            .bind(wallet_id)
            .execute(&self.pool)
            .await?;

        Ok(())
    }

    /// Get affected users when permission matrix changes for a contact group.
    /// Optimizes cache invalidation by only invalidating users with permissions on the changed group.
    pub async fn get_users_with_group_permissions(
        &self,
        wallet_id: Uuid,
        contact_group_id: Uuid,
    ) -> Result<Vec<Uuid>, DbError> {
        let user_ids = sqlx::query_scalar::<_, Uuid>(
            r#"
            SELECT DISTINCT user_id
            FROM user_permission_matrix_cache
            WHERE wallet_id = $1 AND contact_group_id = $2
            "#,
        )
        .bind(wallet_id)
        .bind(contact_group_id)
        .fetch_all(&self.pool)
        .await?;

        Ok(user_ids)
    }

    /// Handle permission matrix cache invalidation when permission events are inserted.
    /// Called automatically after events are inserted to keep cache in sync.
    /// This is the database's responsibility - sync handlers just insert events.
    pub async fn handle_cache_invalidation_for_event(
        &self,
        wallet_id: Uuid,
        domain_event: &crate::domain::events::DomainEvent,
    ) {
        use crate::domain::events::EventData;

        // Check if this event affects permissions
        let event_data = &domain_event.event_data;

        match event_data {
            // User added/removed from group - invalidate that user's cache
            EventData::UserGroupMemberAdded { data } | EventData::UserGroupMemberRemoved { data } => {
                if let Some(user_id_str) = data.get("user_id").and_then(|v| v.as_str()) {
                    if let Ok(user_id) = uuid::Uuid::parse_str(user_id_str) {
                        if let Err(e) = self.invalidate_permission_matrix_cache(wallet_id, user_id).await {
                            tracing::warn!(
                                "Failed to invalidate permission cache for user {}: {:?}",
                                user_id, e
                            );
                        }
                    }
                }
            }

            // Permission matrix changed - smart invalidation: only affected users
            EventData::PermissionMatrixSet { data } => {
                if let Some(contact_group_id_str) =
                    data.get("contact_group_id").and_then(|v| v.as_str())
                {
                    if let Ok(contact_group_id) = uuid::Uuid::parse_str(contact_group_id_str) {
                        // Find users with permissions on this group
                        match self.get_users_with_group_permissions(wallet_id, contact_group_id).await {
                            Ok(affected_users) => {
                                // Invalidate only affected users
                                for user_id in affected_users {
                                    if let Err(e) =
                                        self.invalidate_permission_matrix_cache(wallet_id, user_id).await
                                    {
                                        tracing::warn!(
                                            "Failed to invalidate permission cache for user {}: {:?}",
                                            user_id, e
                                        );
                                    }
                                }
                            }
                            Err(e) => {
                                // Fall back to full wallet invalidation if query fails
                                tracing::warn!(
                                    "Failed to query affected users for permission matrix change, \
                                     falling back to full wallet invalidation: {:?}",
                                    e
                                );
                                let _ = self.invalidate_permission_matrix_cache_for_wallet(wallet_id).await;
                            }
                        }
                        return;
                    }
                }

                // Fall back: Invalidate entire wallet cache if we can't extract contact_group_id
                tracing::warn!(
                    "PermissionMatrixSet event missing contact_group_id, invalidating entire wallet cache"
                );
                if let Err(e) = self.invalidate_permission_matrix_cache_for_wallet(wallet_id).await {
                    tracing::warn!(
                        "Failed to invalidate permission cache for wallet {}: {:?}",
                        wallet_id, e
                    );
                }
            }

            // New user added to wallet - populate cache
            EventData::WalletUserAdded { data } => {
                if let Some(user_id_str) = data.get("user_id").and_then(|v| v.as_str()) {
                    if let Ok(user_id) = uuid::Uuid::parse_str(user_id_str) {
                        if let Err(e) = self.compute_and_cache_user_permission_matrix(wallet_id, user_id).await {
                            tracing::warn!(
                                "Failed to compute permission matrix for new user {}: {:?}",
                                user_id, e
                            );
                        }
                    }
                }
            }

            // User removed from wallet - clean up cache
            EventData::WalletUserRemoved { data } => {
                if let Some(user_id_str) = data.get("user_id").and_then(|v| v.as_str()) {
                    if let Ok(user_id) = uuid::Uuid::parse_str(user_id_str) {
                        if let Err(e) = self.invalidate_permission_matrix_cache(wallet_id, user_id).await {
                            tracing::warn!(
                                "Failed to invalidate permission cache for removed user {}: {:?}",
                                user_id, e
                            );
                        }
                    }
                }
            }

            _ => {
                // Not a permission event - no cache invalidation needed
            }
        }
    }

    /// Internal helper: Handle cache invalidation for events using just event_type and raw JSON data.
    /// Used by insert_permission_event_and_apply() which doesn't construct a full DomainEvent.
    pub async fn handle_cache_invalidation_for_event_raw(
        &self,
        wallet_id: Uuid,
        event_type: &str,
        event_data: &serde_json::Value,
    ) {
        match event_type {
            // User added/removed from group - invalidate that user's cache
            "USER_GROUP_MEMBER_ADDED" | "USER_GROUP_MEMBER_REMOVED" => {
                if let Some(user_id_str) = event_data.get("user_id").and_then(|v| v.as_str()) {
                    if let Ok(user_id) = uuid::Uuid::parse_str(user_id_str) {
                        if let Err(e) = self.invalidate_permission_matrix_cache(wallet_id, user_id).await {
                            tracing::warn!(
                                "Failed to invalidate permission cache for user {}: {:?}",
                                user_id, e
                            );
                        }
                    }
                }
            }

            // Permission matrix changed - smart invalidation: only affected users
            "PERMISSION_MATRIX_SET" => {
                if let Some(contact_group_id_str) =
                    event_data.get("contact_group_id").and_then(|v| v.as_str())
                {
                    if let Ok(contact_group_id) = uuid::Uuid::parse_str(contact_group_id_str) {
                        // Find users with permissions on this group
                        match self.get_users_with_group_permissions(wallet_id, contact_group_id).await {
                            Ok(affected_users) => {
                                // Invalidate only affected users
                                for user_id in affected_users {
                                    if let Err(e) =
                                        self.invalidate_permission_matrix_cache(wallet_id, user_id).await
                                    {
                                        tracing::warn!(
                                            "Failed to invalidate permission cache for user {}: {:?}",
                                            user_id, e
                                        );
                                    }
                                }
                            }
                            Err(e) => {
                                // Fall back to full wallet invalidation if query fails
                                tracing::warn!(
                                    "Failed to query affected users for permission matrix change, \
                                     falling back to full wallet invalidation: {:?}",
                                    e
                                );
                                let _ = self.invalidate_permission_matrix_cache_for_wallet(wallet_id).await;
                            }
                        }
                        return;
                    }
                }

                // Fall back: Invalidate entire wallet cache if we can't extract contact_group_id
                tracing::warn!(
                    "PERMISSION_MATRIX_SET event missing contact_group_id, invalidating entire wallet cache"
                );
                if let Err(e) = self.invalidate_permission_matrix_cache_for_wallet(wallet_id).await {
                    tracing::warn!(
                        "Failed to invalidate permission cache for wallet {}: {:?}",
                        wallet_id, e
                    );
                }
            }

            // New user added to wallet - populate cache
            "WALLET_USER_ADDED" => {
                if let Some(user_id_str) = event_data.get("user_id").and_then(|v| v.as_str()) {
                    if let Ok(user_id) = uuid::Uuid::parse_str(user_id_str) {
                        if let Err(e) = self.compute_and_cache_user_permission_matrix(wallet_id, user_id).await {
                            tracing::warn!(
                                "Failed to compute permission matrix for new user {}: {:?}",
                                user_id, e
                            );
                        }
                    }
                }
            }

            // User removed from wallet - clean up cache
            "WALLET_USER_REMOVED" => {
                if let Some(user_id_str) = event_data.get("user_id").and_then(|v| v.as_str()) {
                    if let Ok(user_id) = uuid::Uuid::parse_str(user_id_str) {
                        if let Err(e) = self.invalidate_permission_matrix_cache(wallet_id, user_id).await {
                            tracing::warn!(
                                "Failed to invalidate permission cache for removed user {}: {:?}",
                                user_id, e
                            );
                        }
                    }
                }
            }

            _ => {
                // Not a permission event - no cache invalidation needed
            }
        }
    }
}
