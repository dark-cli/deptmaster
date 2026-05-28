use uuid::Uuid;
use crate::database::models::*;
use crate::database::error::DbError;
use crate::database::repository::Database;

impl Database {
    pub async fn get_wallet_impl(&self, wallet_id: Uuid) -> Result<Option<Wallet>, DbError> {
        todo!("Extract from handlers/wallets.rs")
    }

    pub async fn create_wallet_impl(&self, id: Uuid, name: String) -> Result<(), DbError> {
        todo!("Extract from handlers/wallets.rs")
    }

    pub async fn get_user_wallets_impl(&self, user_id: Uuid) -> Result<Vec<Wallet>, DbError> {
        todo!("Extract from handlers/wallets.rs")
    }

    pub async fn list_wallet_users_impl(&self, wallet_id: Uuid) -> Result<Vec<WalletUser>, DbError> {
        todo!("Extract from handlers/wallets.rs")
    }

    pub async fn add_wallet_user_impl(
        &self,
        wallet_id: Uuid,
        user_id: Uuid,
        role: String,
    ) -> Result<(), DbError> {
        todo!("Extract from handlers/wallets.rs")
    }

    pub async fn update_wallet_user_role_impl(
        &self,
        wallet_id: Uuid,
        user_id: Uuid,
        role: String,
    ) -> Result<bool, DbError> {
        todo!("Extract from handlers/wallets.rs")
    }
}

