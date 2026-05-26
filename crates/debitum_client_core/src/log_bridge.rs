//! Buffers Rust log lines so Dart can drain them and show in Flutter console (debugPrint).

use once_cell::sync::Lazy;
use std::sync::Mutex;

static RUST_LOG_BUFFER: Lazy<Mutex<Vec<String>>> = Lazy::new(|| Mutex::new(Vec::new()));

const MAX_BUFFER_LEN: usize = 500;

fn should_log(s: &str) -> bool {
    let lower = s.to_lowercase();
    // Always keep errors/warnings and auth/permission signals.
    if lower.contains("error")
        || lower.contains("warn")
        || lower.contains("failed")
        || lower.contains("debitum_auth_declined")
        || lower.contains("debitum_insufficient_wallet_permission")
    {
        return true;
    }

    // Keep core sync logs; drop the rest to reduce noise.
    lower.contains("manual_sync")
        || lower.contains("push_unsynced")
        || lower.contains("pull_and_merge")
        || lower.contains("sync loop")
}

/// Push a log line (also prints to stderr). Called by rust_log! macro.
pub fn push(s: String) {
    if !should_log(&s) {
        return;
    }
    eprintln!("{}", s);
    if let Ok(mut v) = RUST_LOG_BUFFER.lock() {
        v.push(s);
        let n = v.len();
        if n > MAX_BUFFER_LEN {
            v.drain(0..n - MAX_BUFFER_LEN);
        }
    }
}

/// Drain and clear buffered log lines. Dart calls this and debugPrint's each line.
pub fn drain_rust_logs() -> Vec<String> {
    RUST_LOG_BUFFER
        .lock()
        .map(|mut v| std::mem::take(&mut *v))
        .unwrap_or_default()
}

#[macro_export]
macro_rules! rust_log {
    ($($t:tt)*) => {
        crate::log_bridge::push(format!($($t)*))
    };
}
