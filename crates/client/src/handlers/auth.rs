//! FFI handlers for authentication.

use crate::api;

/// FFI wrapper: login with error conversion to String
pub fn login(username: String, password: String) -> Result<(), String> {
    api::login(username, password).map_err(|e| e.to_string())
}

/// FFI wrapper: register with error conversion to String
pub fn register(username: String, password: String) -> Result<(), String> {
    api::register(username, password).map_err(|e| e.to_string())
}
