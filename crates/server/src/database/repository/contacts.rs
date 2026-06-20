use crate::database::error::DbError;
use crate::database::models::*;
use crate::database::repository::Database;
use uuid::Uuid;

#[allow(dead_code)]
impl Database {
    pub async fn get_contacts_for_wallet_impl(
        &self,
        wallet_id: Uuid,
    ) -> Result<Vec<Contact>, DbError> {
        let contacts = sqlx::query_as::<_, Contact>(
            r#"
            SELECT id, name, phone, wallet_id, created_at, updated_at, version
            FROM contacts_projection
            WHERE wallet_id = $1 AND is_deleted = false
            ORDER BY created_at ASC
            "#,
        )
        .bind(wallet_id)
        .fetch_all(&self.pool)
        .await?;

        Ok(contacts)
    }

    pub async fn get_contact_impl(
        &self,
        contact_id: Uuid,
        wallet_id: Uuid,
    ) -> Result<Option<Contact>, DbError> {
        let contact = sqlx::query_as::<_, Contact>(
            r#"
            SELECT id, name, phone, wallet_id, created_at, updated_at, version
            FROM contacts_projection
            WHERE id = $1 AND wallet_id = $2 AND is_deleted = false
            "#,
        )
        .bind(contact_id)
        .bind(wallet_id)
        .fetch_optional(&self.pool)
        .await?;

        Ok(contact)
    }

    pub async fn insert_contact_impl(
        &self,
        id: Uuid,
        name: String,
        phone: Option<String>,
        wallet_id: Uuid,
    ) -> Result<(), DbError> {
        sqlx::query(
            r#"
            INSERT INTO contacts_projection (id, name, phone, wallet_id, is_deleted, created_at, updated_at, version)
            VALUES ($1, $2, $3, $4, false, NOW(), NOW(), 1)
            ON CONFLICT (id) DO NOTHING
            "#
        )
        .bind(id)
        .bind(&name)
        .bind(&phone)
        .bind(wallet_id)
        .execute(&self.pool)
        .await?;

        Ok(())
    }

    pub async fn update_contact_impl(
        &self,
        contact_id: Uuid,
        wallet_id: Uuid,
        name: Option<String>,
        phone: Option<String>,
    ) -> Result<bool, DbError> {
        let query = if let Some(name) = name {
            if let Some(phone) = phone {
                sqlx::query("UPDATE contacts_projection SET name = $1, phone = $2, updated_at = NOW(), version = version + 1 WHERE id = $3 AND wallet_id = $4 AND is_deleted = false")
                    .bind(name)
                    .bind(phone)
                    .bind(contact_id)
                    .bind(wallet_id)
                    .execute(&self.pool)
                    .await?
            } else {
                sqlx::query("UPDATE contacts_projection SET name = $1, updated_at = NOW(), version = version + 1 WHERE id = $2 AND wallet_id = $3 AND is_deleted = false")
                    .bind(name)
                    .bind(contact_id)
                    .bind(wallet_id)
                    .execute(&self.pool)
                    .await?
            }
        } else if let Some(phone) = phone {
            sqlx::query("UPDATE contacts_projection SET phone = $1, updated_at = NOW(), version = version + 1 WHERE id = $2 AND wallet_id = $3 AND is_deleted = false")
                .bind(phone)
                .bind(contact_id)
                .bind(wallet_id)
                .execute(&self.pool)
                .await?
        } else {
            return Ok(false);
        };

        Ok(query.rows_affected() > 0)
    }

    pub async fn delete_contact_impl(
        &self,
        contact_id: Uuid,
        wallet_id: Uuid,
    ) -> Result<bool, DbError> {
        let result = sqlx::query("UPDATE contacts_projection SET is_deleted = true, updated_at = NOW(), version = version + 1 WHERE id = $1 AND wallet_id = $2")
            .bind(contact_id)
            .bind(wallet_id)
            .execute(&self.pool)
            .await?;

        Ok(result.rows_affected() > 0)
    }

    pub async fn get_contact_projection_impl(
        &self,
        contact_id: Uuid,
        wallet_id: Uuid,
    ) -> Result<Option<ContactProjection>, DbError> {
        let projection = sqlx::query_as::<_, ContactProjection>(
            r#"
            SELECT id, name, phone, wallet_id, created_at, updated_at, version
            FROM contacts_projection
            WHERE id = $1 AND wallet_id = $2 AND is_deleted = false
            "#,
        )
        .bind(contact_id)
        .bind(wallet_id)
        .fetch_optional(&self.pool)
        .await?;

        Ok(projection)
    }
}
