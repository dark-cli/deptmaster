//! Typed error handling for the client. Replaces untyped `String` errors.

use std::fmt;

/// Client errors with typed variants for pattern matching and better error handling.
///
/// All public APIs return `Result<T, ClientError>` instead of `Result<T, String>`.
#[derive(Debug, Clone)]
pub enum ClientError {
    /// Network error (connectivity, timeout, DNS, etc.)
    Network(String),

    /// Authentication failed: credentials rejected, token expired, or invalid JWT
    AuthDeclined,

    /// Authentication chain broken: refresh token expired/revoked, must re-login
    AuthExpired,

    /// HTTP response body is invalid JSON or missing required fields
    InvalidResponse(String),

    /// Storage/database operation failed (SQLite error, file I/O, etc.)
    Storage(String),

    /// Sync operation failed (event application, hash mismatch, etc.)
    Sync(String),

    /// Invalid input to a public API
    InvalidInput(String),

    /// Internal error (should never happen in production)
    Internal(String),
}

impl fmt::Display for ClientError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Network(msg) => write!(f, "Network error: {}", msg),
            Self::AuthDeclined => write!(f, "Authentication failed: invalid credentials or device revoked"),
            Self::AuthExpired => write!(f, "Session expired: please log in again"),
            Self::InvalidResponse(msg) => write!(f, "Invalid server response: {}", msg),
            Self::Storage(msg) => write!(f, "Storage error: {}", msg),
            Self::Sync(msg) => write!(f, "Sync error: {}", msg),
            Self::InvalidInput(msg) => write!(f, "Invalid input: {}", msg),
            Self::Internal(msg) => write!(f, "Internal error: {}", msg),
        }
    }
}

impl std::error::Error for ClientError {}

/// Convert from generic errors. Used at I/O boundaries.
impl From<reqwest::Error> for ClientError {
    fn from(e: reqwest::Error) -> Self {
        if e.is_timeout() {
            Self::Network("Request timeout".to_string())
        } else if e.is_connect() {
            Self::Network("Connection failed".to_string())
        } else {
            Self::Network(format!("HTTP error: {}", e))
        }
    }
}

impl From<rusqlite::Error> for ClientError {
    fn from(e: rusqlite::Error) -> Self {
        Self::Storage(e.to_string())
    }
}

impl From<serde_json::Error> for ClientError {
    fn from(e: serde_json::Error) -> Self {
        Self::InvalidResponse(e.to_string())
    }
}

impl From<String> for ClientError {
    fn from(msg: String) -> Self {
        Self::Sync(msg)
    }
}

impl From<&str> for ClientError {
    fn from(msg: &str) -> Self {
        Self::Sync(msg.to_string())
    }
}

/// For FFI boundaries: convert to String for Dart
impl From<ClientError> for String {
    fn from(e: ClientError) -> Self {
        e.to_string()
    }
}
