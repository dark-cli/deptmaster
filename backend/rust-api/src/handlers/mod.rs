pub mod admin;
pub mod contacts;
pub mod transactions;
pub mod settings;
pub mod auth;
pub mod admin_auth;
pub mod sync;
pub mod users;
pub mod wallets;

pub use admin::{
    admin_panel,
    config_js,
    favicon,
    backfill_transaction_events,
    get_events,
    get_contacts as get_admin_contacts,
    get_transactions as get_admin_transactions,
    get_latest_event_id,
    get_projection_status,
    get_total_debt,
    dev_clear_database,
};
pub use contacts::{
    create_contact, 
    update_contact, 
    delete_contact,
    get_contacts,
};
pub use transactions::{
    get_transactions,
    create_transaction, 
    update_transaction, 
    delete_transaction,
};
pub use settings::{get_settings, update_setting};
pub use auth::login;
pub use admin_auth::admin_login;
pub use sync::{
    get_sync_hash,
    get_sync_events,
    post_sync_events,
};
pub use users::{
    get_users,
    create_user,
    delete_user,
    change_password,
    admin_change_password,
    get_user_login_logs,
    backup_user_data,
};
pub use wallets::{
    create_wallet,
    create_my_wallet,
    list_wallets,
    get_wallet,
    update_wallet,
    delete_wallet,
    add_user_to_wallet,
    list_wallet_users,
    update_wallet_user,
    remove_user_from_wallet,
    list_user_wallets,
};