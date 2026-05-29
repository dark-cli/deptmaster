use uuid::Uuid;
use crate::database::models::*;
use crate::database::error::DbError;
use crate::database::repository::Database;

impl Database {
    pub async fn get_user_groups_impl(&self, wallet_id: Uuid) -> Result<Vec<UserGroup>, DbError> {
        let groups = sqlx::query_as::<_, UserGroup>(
            r#"
            SELECT id, wallet_id, name, created_at
            FROM user_groups
            WHERE wallet_id = $1
            ORDER BY created_at ASC
            "#
        )
        .bind(wallet_id)
        .fetch_all(&self.pool)
        .await?;

        Ok(groups)
    }

    pub async fn get_contact_groups_impl(&self, wallet_id: Uuid) -> Result<Vec<ContactGroup>, DbError> {
        let groups = sqlx::query_as::<_, ContactGroup>(
            r#"
            SELECT id, wallet_id, name, created_at
            FROM contact_groups
            WHERE wallet_id = $1
            ORDER BY created_at ASC
            "#
        )
        .bind(wallet_id)
        .fetch_all(&self.pool)
        .await?;

        Ok(groups)
    }

    pub async fn get_user_group_ids_impl(&self, wallet_id: Uuid, user_id: Uuid) -> Result<Vec<Uuid>, DbError> {
        let ids = sqlx::query_scalar::<_, Uuid>(
            r#"
            SELECT DISTINCT ugm.user_group_id
            FROM user_group_members ugm
            INNER JOIN user_groups ug ON ugm.user_group_id = ug.id
            WHERE ug.wallet_id = $1 AND ugm.user_id = $2
            "#
        )
        .bind(wallet_id)
        .bind(user_id)
        .fetch_all(&self.pool)
        .await?;

        Ok(ids)
    }

    pub async fn get_contact_group_ids_impl(&self, wallet_id: Uuid, contact_id: Uuid) -> Result<Vec<Uuid>, DbError> {
        let ids = sqlx::query_scalar::<_, Uuid>(
            r#"
            SELECT DISTINCT cgm.contact_group_id
            FROM contact_group_members cgm
            INNER JOIN contact_groups cg ON cgm.contact_group_id = cg.id
            WHERE cg.wallet_id = $1 AND cgm.contact_id = $2
            "#
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
            "#
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
            "#
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
                "#
            )
            .bind(contact_id)
            .bind(group_id)
            .execute(&self.pool)
            .await?;
        }

        Ok(())
    }

    // User group operations
    pub async fn create_user_group_impl(&self, wallet_id: Uuid, name: &str, is_system: bool) -> Result<Uuid, DbError> {
        let id = Uuid::new_v4();
        sqlx::query(
            r#"
            INSERT INTO user_groups (id, wallet_id, name, is_system)
            VALUES ($1, $2, $3, $4)
            ON CONFLICT (wallet_id, name) DO NOTHING
            "#
        )
        .bind(id)
        .bind(wallet_id)
        .bind(name)
        .bind(is_system)
        .execute(&self.pool)
        .await?;
        Ok(id)
    }

    pub async fn get_user_group_impl(&self, group_id: Uuid, wallet_id: Uuid) -> Result<Option<(Uuid, String, bool)>, DbError> {
        let row = sqlx::query_as::<_, (Uuid, String, bool)>(
            "SELECT id, name, is_system FROM user_groups WHERE id = $1 AND wallet_id = $2"
        )
        .bind(group_id)
        .bind(wallet_id)
        .fetch_optional(&self.pool)
        .await?;
        Ok(row)
    }

    pub async fn get_user_group_by_name_impl(&self, wallet_id: Uuid, name: &str) -> Result<Option<Uuid>, DbError> {
        let id = sqlx::query_scalar::<_, Uuid>(
            "SELECT id FROM user_groups WHERE wallet_id = $1 AND name = $2 LIMIT 1"
        )
        .bind(wallet_id)
        .bind(name)
        .fetch_optional(&self.pool)
        .await?;
        Ok(id)
    }

    pub async fn list_user_groups_impl(&self, wallet_id: Uuid) -> Result<Vec<(Uuid, String, bool)>, DbError> {
        let groups = sqlx::query_as::<_, (Uuid, String, bool)>(
            "SELECT id, name, is_system FROM user_groups WHERE wallet_id = $1 ORDER BY is_system DESC, name"
        )
        .bind(wallet_id)
        .fetch_all(&self.pool)
        .await?;
        Ok(groups)
    }

    pub async fn delete_user_group_impl(&self, group_id: Uuid, wallet_id: Uuid) -> Result<bool, DbError> {
        let result = sqlx::query(
            "DELETE FROM user_groups WHERE id = $1 AND wallet_id = $2 AND is_system = false"
        )
        .bind(group_id)
        .bind(wallet_id)
        .execute(&self.pool)
        .await?;
        Ok(result.rows_affected() > 0)
    }

    pub async fn list_user_group_members_impl(&self, group_id: Uuid, wallet_id: Uuid) -> Result<Vec<(Uuid, Option<String>)>, DbError> {
        let members = sqlx::query_as::<_, (Uuid, Option<String>)>(
            r#"
            SELECT ugm.user_id, u.username
            FROM user_group_members ugm
            INNER JOIN user_groups ug ON ug.id = ugm.user_group_id
            LEFT JOIN users_projection u ON u.id = ugm.user_id
            WHERE ug.id = $1 AND ug.wallet_id = $2
            "#
        )
        .bind(group_id)
        .bind(wallet_id)
        .fetch_all(&self.pool)
        .await?;
        Ok(members)
    }

    pub async fn add_user_group_member_impl(&self, group_id: Uuid, user_id: Uuid) -> Result<(), DbError> {
        sqlx::query(
            "INSERT INTO user_group_members (user_id, user_group_id) VALUES ($1, $2) ON CONFLICT DO NOTHING"
        )
        .bind(user_id)
        .bind(group_id)
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    pub async fn remove_user_group_member_impl(&self, group_id: Uuid, user_id: Uuid) -> Result<bool, DbError> {
        let result = sqlx::query(
            "DELETE FROM user_group_members WHERE user_group_id = $1 AND user_id = $2"
        )
        .bind(group_id)
        .bind(user_id)
        .execute(&self.pool)
        .await?;
        Ok(result.rows_affected() > 0)
    }

    // Contact group operations
    pub async fn create_contact_group_impl(&self, wallet_id: Uuid, name: &str, group_type: &str, is_system: bool) -> Result<Uuid, DbError> {
        let id = Uuid::new_v4();
        sqlx::query(
            r#"
            INSERT INTO contact_groups (id, wallet_id, name, type, is_system)
            VALUES ($1, $2, $3, $4, $5)
            ON CONFLICT (wallet_id, name) DO NOTHING
            "#
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

    pub async fn get_contact_group_impl(&self, group_id: Uuid, wallet_id: Uuid) -> Result<Option<(Uuid, String, String, bool)>, DbError> {
        let row = sqlx::query_as::<_, (Uuid, String, String, bool)>(
            "SELECT id, name, type, is_system FROM contact_groups WHERE id = $1 AND wallet_id = $2"
        )
        .bind(group_id)
        .bind(wallet_id)
        .fetch_optional(&self.pool)
        .await?;
        Ok(row)
    }

    pub async fn get_contact_group_by_name_impl(&self, wallet_id: Uuid, name: &str) -> Result<Option<Uuid>, DbError> {
        let id = sqlx::query_scalar::<_, Uuid>(
            "SELECT id FROM contact_groups WHERE wallet_id = $1 AND name = $2 LIMIT 1"
        )
        .bind(wallet_id)
        .bind(name)
        .fetch_optional(&self.pool)
        .await?;
        Ok(id)
    }

    pub async fn list_contact_groups_impl(&self, wallet_id: Uuid) -> Result<Vec<(Uuid, String, String, bool)>, DbError> {
        let groups = sqlx::query_as::<_, (Uuid, String, String, bool)>(
            "SELECT id, name, type, is_system FROM contact_groups WHERE wallet_id = $1 ORDER BY is_system DESC, name"
        )
        .bind(wallet_id)
        .fetch_all(&self.pool)
        .await?;
        Ok(groups)
    }

    pub async fn delete_contact_group_impl(&self, group_id: Uuid, wallet_id: Uuid) -> Result<bool, DbError> {
        let result = sqlx::query(
            "DELETE FROM contact_groups WHERE id = $1 AND wallet_id = $2 AND is_system = false"
        )
        .bind(group_id)
        .bind(wallet_id)
        .execute(&self.pool)
        .await?;
        Ok(result.rows_affected() > 0)
    }

    pub async fn list_contact_group_members_impl(&self, group_id: Uuid, wallet_id: Uuid) -> Result<Vec<Uuid>, DbError> {
        let members = sqlx::query_scalar::<_, Uuid>(
            r#"
            SELECT cgm.contact_id
            FROM contact_group_members cgm
            INNER JOIN contact_groups cg ON cg.id = cgm.contact_group_id
            WHERE cg.id = $1 AND cg.wallet_id = $2
            "#
        )
        .bind(group_id)
        .bind(wallet_id)
        .fetch_all(&self.pool)
        .await?;
        Ok(members)
    }

    // Permission actions and matrix
    pub async fn get_permission_action_id_impl(&self, name: &str) -> Result<Option<i16>, DbError> {
        let id = sqlx::query_scalar::<_, i16>(
            "SELECT id FROM permission_actions WHERE name = $1"
        )
        .bind(name)
        .fetch_optional(&self.pool)
        .await?;
        Ok(id)
    }

    pub async fn get_all_permission_actions_impl(&self) -> Result<Vec<(i16, String, String)>, DbError> {
        let actions = sqlx::query_as::<_, (i16, String, String)>(
            "SELECT id, name, resource FROM permission_actions ORDER BY resource, name"
        )
        .fetch_all(&self.pool)
        .await?;
        Ok(actions)
    }

    pub async fn grant_permission_impl(&self, user_group_id: Uuid, contact_group_id: Uuid, action_id: i16) -> Result<(), DbError> {
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

    pub async fn revoke_permission_impl(&self, user_group_id: Uuid, contact_group_id: Uuid, action_id: i16) -> Result<bool, DbError> {
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
    pub async fn user_group_in_wallet_impl(&self, group_id: Uuid, wallet_id: Uuid) -> Result<bool, DbError> {
        let exists = sqlx::query_scalar::<_, bool>(
            "SELECT EXISTS(SELECT 1 FROM user_groups WHERE id = $1 AND wallet_id = $2)"
        )
        .bind(group_id)
        .bind(wallet_id)
        .fetch_one(&self.pool)
        .await?;
        Ok(exists)
    }

    pub async fn contact_group_in_wallet_impl(&self, group_id: Uuid, wallet_id: Uuid) -> Result<bool, DbError> {
        let exists = sqlx::query_scalar::<_, bool>(
            "SELECT EXISTS(SELECT 1 FROM contact_groups WHERE id = $1 AND wallet_id = $2)"
        )
        .bind(group_id)
        .bind(wallet_id)
        .fetch_one(&self.pool)
        .await?;
        Ok(exists)
    }
}

