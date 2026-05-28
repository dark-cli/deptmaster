use uuid::Uuid;
use crate::database::error::DbError;
use crate::database::repository::Database;

impl Database {
    pub async fn get_all_contacts_group_impl(&self, wallet_id: Uuid) -> Result<Option<Uuid>, DbError> {
        todo!("Extract from sync.rs apply_contact_group_ids_from_event_data")
    }

    pub async fn count_events_impl(&self, wallet_id: Uuid) -> Result<i64, DbError> {
        todo!("Extract from sync.rs")
    }

    pub async fn clear_projections_impl(&self, wallet_id: Uuid) -> Result<(), DbError> {
        todo!("Extract from admin handler or sync.rs")
    }
}

