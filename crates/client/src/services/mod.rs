//! Business logic layer: CRUD operations, sync orchestration.

pub mod crud;
pub mod sync;

pub use crud::{
    bulk_delete_contacts, bulk_delete_transactions, create_contact, create_transaction,
    delete_contact, delete_transaction, get_contact, get_contacts, get_transaction,
    get_transactions, logout, undo_contact_action, undo_transaction_action, update_contact,
    update_transaction, wallet_total_debt,
};
pub use sync::push_unsynced;
