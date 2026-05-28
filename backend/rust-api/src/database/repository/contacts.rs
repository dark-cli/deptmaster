use uuid::Uuid;
use crate::database::models::*;
use crate::database::error::DbError;
use crate::database::repository::Database;

impl Database {
    pub async fn get_contacts_for_wallet_impl(&self, wallet_id: Uuid) -> Result<Vec<Contact>, DbError> {
        todo!("Extract from handlers")
    }

    pub async fn get_contact_impl(&self, contact_id: Uuid, wallet_id: Uuid) -> Result<Option<Contact>, DbError> {
        todo!("Extract from handlers")
    }

    pub async fn insert_contact_impl(
        &self,
        id: Uuid,
        name: String,
        phone: Option<String>,
        wallet_id: Uuid,
    ) -> Result<(), DbError> {
        todo!("Extract from sync.rs")
    }

    pub async fn update_contact_impl(
        &self,
        contact_id: Uuid,
        wallet_id: Uuid,
        name: Option<String>,
        phone: Option<String>,
    ) -> Result<bool, DbError> {
        todo!("Extract from sync.rs")
    }

    pub async fn delete_contact_impl(&self, contact_id: Uuid, wallet_id: Uuid) -> Result<bool, DbError> {
        todo!("Extract from sync.rs")
    }

    pub async fn get_contact_projection_impl(
        &self,
        contact_id: Uuid,
        wallet_id: Uuid,
    ) -> Result<Option<ContactProjection>, DbError> {
        todo!("Extract from handlers")
    }
}
