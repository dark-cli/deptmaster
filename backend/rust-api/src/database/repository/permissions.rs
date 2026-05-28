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
}

