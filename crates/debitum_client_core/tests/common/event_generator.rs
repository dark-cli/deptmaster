//! Event generator: run commands like "app1: contact create \"Name\" label" by dispatching to the right AppInstance.
//! Mirror of Flutter's EventGenerator — same command format. Uses one shared CommandRunner so labels
//! (contact1, t1, etc.) are shared across apps (same user's data).

use std::cell::RefCell;
use std::collections::HashMap;

use debitum_client_core::manual_sync;

use super::app_instance::AppInstance;
use super::command_runner::CommandRunner;

/// Runs text commands, dispatching "appName: action" to the corresponding AppInstance.
/// Holds a single CommandRunner so contact/transaction labels persist across apps (e.g. app1 creates contact1, app2 uses contact1).
pub struct EventGenerator {
    pub apps: HashMap<String, AppInstance>,
    runner: RefCell<CommandRunner>,
}

impl EventGenerator {
    pub fn new(apps: HashMap<String, AppInstance>) -> Self {
        Self {
            apps,
            runner: RefCell::new(CommandRunner::new()),
        }
    }

    /// Execute a list of commands. Format: "app1: contact create \"Alice\" alice" or "app2: transaction create contact1 owed 1000 \"T1\" t1".
    /// Empty lines and # comments are skipped.
    pub fn execute_commands(&self, commands: &[&str]) -> Result<(), String> {
        for cmd in commands {
            let cmd = cmd.trim();
            if cmd.is_empty() || cmd.starts_with('#') {
                continue;
            }
            self.execute_command(cmd)?;
        }
        Ok(())
    }

    /// Execute a single command "appName: action part". Activates that app (thread-local storage) then runs the command with the shared runner.
    /// Before transaction update/delete we sync so the active app has data created on other apps (get_transaction reads from current storage).
    pub fn execute_command(&self, command: &str) -> Result<(), String> {
        let parts: Vec<&str> = command.splitn(2, ':').collect();
        if parts.len() != 2 {
            return Err(format!("Invalid command format: {}. Expected: \"app: action\"", command));
        }
        let app_name = parts[0].trim();
        let action_part = parts[1].trim();
        let app = self
            .apps
            .get(app_name)
            .ok_or_else(|| format!("App instance not found: {}", app_name))?;
        app.activate()?;
        // So the active app has contacts/transactions from other apps: state_builder requires contact to exist for transaction create; get_transaction reads current app for update/delete.
        let action_lower = action_part.trim().to_lowercase();
        let needs_sync = action_lower.starts_with("transaction create")
            || action_lower.starts_with("transaction update")
            || action_lower.starts_with("transaction delete")
            || action_lower.starts_with("contact update")
            || action_lower.starts_with("contact delete");
        if needs_sync {
            let _ = manual_sync();
            // If sync was skipped (in-flight), give it time to finish so next sync can run
            std::thread::sleep(std::time::Duration::from_millis(150));
            let _ = manual_sync();
        }
        self.runner.borrow_mut().execute_command(action_part)
    }
}
