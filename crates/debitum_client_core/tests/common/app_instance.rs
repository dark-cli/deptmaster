//! App instance: one simulated app (own storage, optional own user/wallet).
//! Mirror of Flutter's AppInstance — create, initialize, signup/login, sync, run_commands, get_*.

use debitum_client_core::{
    create_wallet, ensure_current_wallet, get_contacts, get_transactions, init_storage,
    manual_sync, register, set_backend_config, set_current_wallet_id, set_network_offline,
};
use std::cell::RefCell;
use std::path::PathBuf;

use super::command_runner::CommandRunner;

/// Simulated app instance. Each has its own storage path; "activate" switches global state to this app.
/// Holds a single CommandRunner so contact/transaction labels persist across run_command calls (e.g. from EventGenerator).
pub struct AppInstance {
    pub id: String,
    pub server_url: String,
    pub ws_url: String,
    pub username: String,
    pub password: String,
    pub storage_path: PathBuf,
    pub wallet_id: Option<String>,
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
            id: id.clone(),
            server_url: server_url.to_string(),
            ws_url: ws_url.clone(),
            username,
            password,
            storage_path,
            wallet_id: None,
            _temp_dir: Some(dir),
            runner: RefCell::new(CommandRunner::new()),
        }
    }

    /// Create an app instance with given credentials (e.g. same user for app1/app2/app3). Call initialize() then login().
    pub fn with_credentials(
        id: impl Into<String>,
        server_url: &str,
        username: String,
        password: String,
        wallet_id: Option<String>,
    ) -> Self {
        let id = id.into();
        let dir = tempfile::tempdir().expect("tempdir");
        let storage_path = dir.path().to_path_buf();
        let ws_url = ws_url_from_base(server_url);
        Self {
            id,
            server_url: server_url.to_string(),
            ws_url,
            username,
            password,
            storage_path,
            wallet_id,
            _temp_dir: Some(dir),
            runner: RefCell::new(CommandRunner::new()),
        }
    }

    /// Switch global (thread-local) client state to this app (storage + backend). Used by EventGenerator so labels persist across apps.
    pub fn activate(&self) -> Result<(), String> {
        init_storage(self.storage_path.to_string_lossy().to_string())?;
        set_backend_config(self.server_url.clone(), self.ws_url.clone());
        Ok(())
    }

    /// Initialize storage and backend config. Call once before signup/login.
    pub fn initialize(&self) -> Result<(), String> {
        self.activate()
    }

    /// Register this app's user, create a wallet, set as current. Use after new().
    pub fn signup(&self) -> Result<(), String> {
        self.activate()?;
        register(self.username.clone(), self.password.clone())?;
        let wallet_json = create_wallet("Test Wallet".to_string(), "".to_string())?;
        let wallet: serde_json::Value = serde_json::from_str(&wallet_json).map_err(|e| e.to_string())?;
        let wallet_id = wallet["id"].as_str().ok_or("No wallet id")?.to_string();
        set_current_wallet_id(wallet_id.clone())?;
        Ok(())
    }

    /// Login with this app's credentials and ensure wallet. Use after with_credentials() or when reusing same user.
    pub fn login(&self) -> Result<(), String> {
        self.activate()?;
        debitum_client_core::login(self.username.clone(), self.password.clone())?;
        if let Some(ref w) = self.wallet_id {
            set_current_wallet_id(w.clone())?;
        } else {
            ensure_current_wallet()?;
        }
        Ok(())
    }

    /// Run sync (push + pull). Call after run_commands or when you want to sync.
    pub fn sync(&self) -> Result<(), String> {
        self.activate()?;
        manual_sync()
    }

    /// Get events for this app. Call after sync to assert.
    pub fn get_events(&self) -> Result<String, String> {
        self.activate()?;
        debitum_client_core::get_events()
    }

    /// Get contacts for this app.
    pub fn get_contacts(&self) -> Result<String, String> {
        self.activate()?;
        get_contacts()
    }

    /// Get transactions for this app.
    pub fn get_transactions(&self) -> Result<String, String> {
        self.activate()?;
        get_transactions()
    }

    /// Run assertion commands (same style as run_commands). E.g. "contacts count 1", "contact name \"Alice\"", "events count >= 12".
    pub fn assert_commands(&self, commands: &[&str]) -> Result<(), String> {
        self.activate()?;
        let contacts = get_contacts()?;
        let events = debitum_client_core::get_events()?;
        let transactions = get_transactions()?;
        super::assert_runner::assert_commands(&contacts, &events, &transactions, commands)
    }

    /// Run a single command (action part only, e.g. "contact create \"Alice\" alice"). No "app1:" prefix.
    /// Uses a shared CommandRunner so labels (contact1, t1, etc.) persist across calls (e.g. from EventGenerator).
    pub fn run_command(&self, command: &str) -> Result<(), String> {
        self.activate()?;
        self.runner.borrow_mut().execute_command(command)
    }

    /// Run a list of commands on this app. Commands have no "app:" prefix (e.g. "contact create \"Alice\" alice").
    pub fn run_commands(&self, commands: &[&str]) -> Result<(), String> {
        self.activate()?;
        self.runner.borrow_mut().execute_commands(commands)
    }

    /// Logout (clear session for this app's storage).
    pub fn logout(&self) -> Result<(), String> {
        self.activate()?;
        debitum_client_core::logout()
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

/// Create a unique test user and wallet via the client (register + create_wallet). Returns (username, password, wallet_id).
pub fn create_unique_test_user_and_wallet(server_url: &str) -> Result<(String, String, String), String> {
    let app = AppInstance::new("_setup", server_url);
    app.initialize()?;
    app.signup()?;
    let wallet_id = debitum_client_core::get_current_wallet_id().ok_or("No wallet id")?;
    Ok((app.username, app.password, wallet_id))
}
