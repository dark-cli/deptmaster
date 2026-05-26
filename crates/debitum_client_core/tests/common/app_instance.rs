//! App instance: one simulated app (own storage, optional own user/wallet).
//! Mirror of Flutter's AppInstance — create, initialize, signup/login, sync, run_commands, assert_commands.
//!
//! ## Split actions (after app instance creation)
//!
//! - **signup()**: Register the user only; no wallet. Use after **new()**.
//! - **login()**: Authenticate only; does **not** select or create a wallet.
//! - **create_wallet(name, description)**: Create a wallet (must be logged in). Sets it as current; returns wallet_id.
//! - **select_wallet(wallet_id)**: Set current wallet (must be logged in; wallet must be one you own or joined).
//!
//! So: **signup** = register only. **login** = auth only. Wallet selection and creation are separate.

use debitum_client_core::{
    create_wallet, get_contacts, get_transactions, init_storage, register, set_backend_config, set_log_context,
    set_current_wallet_id, set_network_offline,
};
use std::cell::RefCell;
use std::path::PathBuf;

use super::command_runner::CommandRunner;

/// Simulated app instance. Each has its own storage path; "activate" switches global state to this app.
/// Holds a single CommandRunner so contact/transaction labels persist across run_commands (e.g. from EventGenerator).
/// Wallet is chosen after login via select_wallet() or create_wallet(); it is stored here so helpers can use it.
pub struct AppInstance {
    pub _id: String,
    pub server_url: String,
    pub ws_url: String,
    pub username: String,
    pub password: String,
    pub storage_path: PathBuf,
    /// Set when select_wallet() or create_wallet() is called.
    wallet_id: RefCell<Option<String>>,
    _temp_dir: Option<tempfile::TempDir>,
    runner: RefCell<CommandRunner>,
}

impl AppInstance {
    /// Create a new app instance with a unique user (itest-{uuid}). Call signup() to register and create wallet.
    pub fn new(id: impl Into<String>, server_url: &str) -> Self {
        let id = id.into();
        let username = format!("itest-{}", uuid::Uuid::new_v4());
        let password = "test-pass-1234".to_string();
        let dir = tempfile::tempdir().expect("tempdir");
        let storage_path = dir.path().to_path_buf();
        let ws_url = ws_url_from_base(server_url);
        Self {
            _id: id.clone(),
            server_url: server_url.to_string(),
            ws_url: ws_url.clone(),
            username,
            password,
            storage_path,
            wallet_id: RefCell::new(None),
            _temp_dir: Some(dir),
            runner: RefCell::new(CommandRunner::new()),
        }
    }

    /// Create an app instance with given credentials (e.g. same user for app1/app2/app3).
    /// Call initialize() then login() then select_wallet(&id). Wallet is never passed at construction; create/select wallet after login.
    pub fn with_credentials(
        id: impl Into<String>,
        server_url: &str,
        username: String,
        password: String,
    ) -> Self {
        let id = id.into();
        let dir = tempfile::tempdir().expect("tempdir");
        let storage_path = dir.path().to_path_buf();
        let ws_url = ws_url_from_base(server_url);
        Self {
            _id: id,
            server_url: server_url.to_string(),
            ws_url,
            username,
            password,
            storage_path,
            wallet_id: RefCell::new(None),
            _temp_dir: Some(dir),
            runner: RefCell::new(CommandRunner::new()),
        }
    }

    /// Switch global (thread-local) client state to this app (storage + backend). Used by EventGenerator so labels persist across apps.
    /// Sets log context to this instance's id so rust_log lines show [timestamp][app1] etc.
    pub fn activate(&self) -> Result<(), String> {
        set_log_context(Some(self._id.clone()));
        init_storage(self.storage_path.to_string_lossy().to_string())?;
        set_backend_config(self.server_url.clone(), self.ws_url.clone());
        Ok(())
    }

    /// Initialize storage and backend config. Call once before register/login.
    pub fn initialize(&self) -> Result<(), String> {
        self.activate()
    }

    /// Register this app's user only (no wallet). Use after new(). Then login() then create_wallet() or select_wallet().
    pub fn signup(&self) -> Result<(), String> {
        self.activate()?;
        register(self.username.clone(), self.password.clone())?;
        Ok(())
    }

    /// Authenticate only; does not select or create a wallet. Call select_wallet() or create_wallet() after if needed.
    pub fn login(&self) -> Result<(), String> {
        self.activate()?;
        debitum_client_core::login(self.username.clone(), self.password.clone())?;
        Ok(())
    }

    /// Create a wallet and set it as current. Must be logged in. Returns the new wallet id.
    pub fn create_wallet(&self, name: String, description: String) -> Result<String, String> {
        self.activate()?;
        let wallet_json = create_wallet(name, description)?;
        let wallet: serde_json::Value = serde_json::from_str(&wallet_json).map_err(|e| e.to_string())?;
        let wallet_id = wallet["id"].as_str().ok_or("No wallet id")?.to_string();
        set_current_wallet_id(wallet_id.clone())?;
        *self.wallet_id.borrow_mut() = Some(wallet_id.clone());
        Ok(wallet_id)
    }

    /// Set the current wallet (must be logged in; wallet must be one you own or have joined). Stores id on this instance.
    pub fn select_wallet(&self, wallet_id: &str) -> Result<(), String> {
        self.activate()?;
        set_current_wallet_id(wallet_id.to_string())?;
        *self.wallet_id.borrow_mut() = Some(wallet_id.to_string());
        Ok(())
    }

    /// Run sync (push + pull). Call when you need to force a sync (e.g. offline test).
    pub fn sync(&self) -> Result<(), String> {
        self.activate()?;
        debitum_client_core::manual_sync()
    }

    /// Run assertion commands (same style as run_commands). E.g. "contacts count 1", "contact name \"Alice\"", "events count 12". All counts are exact.
    pub fn assert_commands(&self, commands: &[&str]) -> Result<(), String> {
        self.activate()?;
        let contacts = get_contacts()?;
        let events = debitum_client_core::get_events()?;
        let transactions = get_transactions()?;
        super::assert_runner::assert_commands(&contacts, &events, &transactions, commands)
    }

    /// Run a list of commands on this app. Commands have no "app:" prefix (e.g. "contact create \"Alice\" alice").
    pub fn run_commands(&self, commands: &[&str]) -> Result<(), String> {
        self.activate()?;
        let mut runner = self.runner.borrow_mut();
        for cmd in commands {
            let cmd = cmd.trim();
            if cmd.is_empty() || cmd.starts_with('#') {
                continue;
            }
            runner.execute_command(cmd)?;
        }
        Ok(())
    }

    /// Simulate offline: API calls (sync, login, etc.) will return "Network offline" without sending requests.
    pub fn go_offline(&self) -> Result<(), String> {
        self.activate()?;
        set_network_offline(true);
        Ok(())
    }

    /// Simulate online: clear offline flag so API calls hit the server again.
    pub fn go_online(&self) -> Result<(), String> {
        self.activate()?;
        set_network_offline(false);
        Ok(())
    }
}

fn ws_url_from_base(base: &str) -> String {
    let base = base.trim_end_matches('/');
    if base.starts_with("https://") {
        base.replacen("https://", "wss://", 1) + "/ws"
    } else {
        base.replacen("http://", "ws://", 1) + "/ws"
    }
}

/// Create a unique test user and wallet via the client (register, login, create_wallet). Returns (username, password, wallet_id).
pub fn create_unique_test_user_and_wallet(server_url: &str) -> Result<(String, String, String), String> {
    let app = AppInstance::new("_setup", server_url);
    app.initialize()?;
    app.signup()?;
    app.login()?;
    let wallet_id = app.create_wallet("Test Wallet".to_string(), "".to_string())?;
    Ok((app.username, app.password, wallet_id))
}
