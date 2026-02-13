//! Shared helpers for integration tests: server URL and multi-app setup.

use std::collections::HashMap;

use super::app_instance::{create_unique_test_user_and_wallet, AppInstance};
use super::event_generator::EventGenerator;

/// Default test server URL. Override with env `TEST_SERVER_URL`.
pub fn test_server_url() -> String {
    std::env::var("TEST_SERVER_URL").unwrap_or_else(|_| "http://127.0.0.1:8000".to_string())
}

/// Create three app instances (same user) and an EventGenerator. All initialized and logged in.
pub fn setup_three_apps(server_url: &str) -> EventGenerator {
    let (username, password, wallet_id) =
        create_unique_test_user_and_wallet(server_url).expect("create_unique_test_user_and_wallet");
    let app1 = AppInstance::with_credentials(
        "app1",
        server_url,
        username.clone(),
        password.clone(),
        Some(wallet_id.clone()),
    );
    let app2 = AppInstance::with_credentials(
        "app2",
        server_url,
        username.clone(),
        password.clone(),
        Some(wallet_id.clone()),
    );
    let app3 = AppInstance::with_credentials("app3", server_url, username, password, Some(wallet_id));
    app1.initialize().expect("initialize");
    app2.initialize().expect("initialize");
    app3.initialize().expect("initialize");
    app1.login().expect("login");
    app2.login().expect("login");
    app3.login().expect("login");
    let mut apps = HashMap::new();
    apps.insert("app1".to_string(), app1);
    apps.insert("app2".to_string(), app2);
    apps.insert("app3".to_string(), app3);
    EventGenerator::new(apps)
}
