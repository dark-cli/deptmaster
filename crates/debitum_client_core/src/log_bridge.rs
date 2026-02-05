//! Buffers Rust log lines so Dart can drain them and show in Flutter console (debugPrint).

use once_cell::sync::Lazy;
use std::sync::Mutex;

static RUST_LOG_BUFFER: Lazy<Mutex<Vec<String>>> = Lazy::new(|| Mutex::new(Vec::new()));

const MAX_BUFFER_LEN: usize = 500;

/// Push a log line (also prints to stderr). Called by rust_log! macro.
pub fn push(s: String) {
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
