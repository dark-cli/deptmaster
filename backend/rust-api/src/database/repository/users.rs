use uuid::Uuid;
use crate::database::models::*;
use crate::database::error::DbError;
use crate::database::repository::Database;

impl Database {
    pub async fn get_user_by_email_impl(&self, email: &str) -> Result<Option<User>, DbError> {
        todo!("Extract from handlers/auth.rs")
    }

    pub async fn get_user_by_id_impl(&self, user_id: Uuid) -> Result<Option<User>, DbError> {
        todo!("Extract from handlers")
    }

    pub async fn create_user_impl(
        &self,
        id: Uuid,
        email: String,
        password_hash: String,
    ) -> Result<(), DbError> {
        todo!("Extract from handlers/auth.rs")
    }

    pub async fn update_user_password_impl(&self, user_id: Uuid, password_hash: String) -> Result<bool, DbError> {
        todo!("Extract from handlers")
    }

    pub async fn get_user_settings_impl(
        &self,
        user_id: Uuid,
        wallet_id: Uuid,
    ) -> Result<Option<UserSettings>, DbError> {
        todo!("Extract from handlers/settings.rs")
    }

    pub async fn set_default_groups_impl(
        &self,
        user_id: Uuid,
        wallet_id: Uuid,
        contact_group_id: Option<Uuid>,
        transaction_group_id: Option<Uuid>,
    ) -> Result<(), DbError> {
        todo!("Extract from handlers/settings.rs")
    }
}

