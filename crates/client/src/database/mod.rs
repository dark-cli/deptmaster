//! Database layer: storage abstraction with typed error handling.

pub(crate) mod models;
pub mod repository;
pub mod storage;

pub use models::StoredEvent;
pub use repository::{
    clear_all, clear_wallet, config_get, config_remove, config_set, events_count,
    events_delete_all_for_wallet, events_delete_unsynced, events_get_all,
    events_get_for_aggregate, events_get_unsynced, events_insert, events_mark_synced,
    events_update_event_data, init, is_ready, load_contacts_from_tables,
    load_transactions_from_tables, with_db,
};
