use uuid::Uuid;
use crate::database::models::*;
use crate::database::error::DbError;
use crate::database::repository::Database;

impl Database {
    pub async fn get_user_groups_impl(&self, wallet_id: Uuid) -> Result<Vec<UserGroup>, DbError> {
        todo!("Extract from handlers")
    }

    pub async fn get_contact_groups_impl(&self, wallet_id: Uuid) -> Result<Vec<ContactGroup>, DbError> {
        todo!("Extract from handlers")
    }

    pub async fn get_user_group_ids_impl(&self, wallet_id: Uuid, user_id: Uuid) -> Result<Vec<Uuid>, DbError> {
        todo!("Extract from services/permission_service.rs")
    }

    pub async fn get_contact_group_ids_impl(&self, wallet_id: Uuid, contact_id: Uuid) -> Result<Vec<Uuid>, DbError> {
        todo!("Extract from handlers")
    }

    pub async fn get_group_permission_matrix_impl(
        &self,
        wallet_id: Uuid,
        user_group_id: Uuid,
        contact_group_id: Uuid,
    ) -> Result<Vec<String>, DbError> {
        todo!("Extract from services/permission_service.rs")
    }

    pub async fn sync_contact_group_members_impl(
        &self,
        wallet_id: Uuid,
        contact_id: Uuid,
        group_ids: Vec<Uuid>,
    ) -> Result<(), DbError> {
        todo!("Extract from sync.rs apply_contact_group_ids_from_event_data")
    }
}

