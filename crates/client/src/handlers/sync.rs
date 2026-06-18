//! FFI handlers for sync operations.

pub fn manual_sync_api() -> Result<(), String> {
    crate::integration::sync_control::manual_sync()
}
