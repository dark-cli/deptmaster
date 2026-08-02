//! Client-side delegable permission handling tests
//!
//! Tests that the client properly handles authorization errors from the server
//! when the user lacks delegable permissions for an operation.

use client::ClientError;

#[test]
fn insufficient_permission_error_displays_correctly() {
    let error = ClientError::InsufficientPermission("User lacks wallet:groups_create permission".to_string());
    let display_str = format!("{}", error);

    assert!(display_str.contains("Insufficient permission"));
    assert!(display_str.contains("wallet:groups_create"));
}

#[test]
fn insufficient_permission_error_matches_variant() {
    let error = ClientError::InsufficientPermission("test".to_string());

    match error {
        ClientError::InsufficientPermission(msg) => {
            assert_eq!(msg, "test");
        }
        _ => panic!("Expected InsufficientPermission variant"),
    }
}

#[test]
fn insufficient_permission_error_is_distinct_from_sync_error() {
    let perm_error = ClientError::InsufficientPermission("No access".to_string());
    let sync_error = ClientError::Sync("403 No access".to_string());

    match perm_error {
        ClientError::InsufficientPermission(_) => {
            // Expected
        }
        _ => panic!("Expected InsufficientPermission"),
    }

    match sync_error {
        ClientError::Sync(_) => {
            // Expected
        }
        _ => panic!("Expected Sync error"),
    }
}

#[test]
fn insufficient_permission_error_converts_to_string() {
    let error = ClientError::InsufficientPermission("Access denied".to_string());
    let error_string: String = error.into();

    assert!(error_string.contains("Insufficient permission"));
    assert!(error_string.contains("Access denied"));
}
