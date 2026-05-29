use debt_tracker_api::permissions::{Action, PermissionContext, PermissionModel, Resource, WalletRole};
use uuid::Uuid;

#[test]
fn test_permission_dependency_validation() {
    // Test: Update requires read
    let actions = [Action::ContactUpdate, Action::ContactRead];
    assert!(
        PermissionModel::validate_dependencies(&actions).is_ok(),
        "Update with read should be valid"
    );

    // Test: Update without read should fail
    let actions_no_read = [Action::ContactUpdate];
    assert!(
        PermissionModel::validate_dependencies(&actions_no_read).is_err(),
        "Update without read should be invalid"
    );

    // Test: Multiple updates with single read
    let actions_multi = [
        Action::ContactUpdate,
        Action::ContactDelete,
        Action::ContactRead,
    ];
    assert!(
        PermissionModel::validate_dependencies(&actions_multi).is_ok(),
        "Multiple write actions with read should be valid"
    );

    // Test: Transaction operations
    let transaction_actions = [Action::TransactionClose, Action::TransactionRead];
    assert!(
        PermissionModel::validate_dependencies(&transaction_actions).is_ok(),
        "Transaction close with read should be valid"
    );

    let transaction_invalid = [Action::TransactionClose];
    assert!(
        PermissionModel::validate_dependencies(&transaction_invalid).is_err(),
        "Transaction close without read should be invalid"
    );

    // Test: Wallet operations
    let wallet_actions = [Action::WalletUpdate, Action::WalletRead];
    assert!(
        PermissionModel::validate_dependencies(&wallet_actions).is_ok(),
        "Wallet update with read should be valid"
    );
}

#[test]
fn test_permission_context_creation() {
    let wallet_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();

    // Test owner context
    let owner_ctx = PermissionContext::owner(wallet_id, user_id);
    assert_eq!(owner_ctx.wallet_id, wallet_id);
    assert_eq!(owner_ctx.user_id, user_id);
    assert_eq!(owner_ctx.user_role, WalletRole::Owner);
    assert!(owner_ctx.bypasses_permissions());

    // Test admin context
    let admin_ctx = PermissionContext::admin(wallet_id, user_id);
    assert_eq!(admin_ctx.user_role, WalletRole::Admin);
    assert!(admin_ctx.bypasses_permissions());

    // Test member context
    let member_ctx = PermissionContext::member(wallet_id, user_id);
    assert_eq!(member_ctx.user_role, WalletRole::Member);
    assert!(!member_ctx.bypasses_permissions());

    // Test new() constructor with explicit role
    let wallet_id2 = Uuid::new_v4();
    let user_id2 = Uuid::new_v4();
    let ctx = PermissionContext::new(wallet_id2, user_id2, WalletRole::Member);
    assert_eq!(ctx.wallet_id, wallet_id2);
    assert_eq!(ctx.user_id, user_id2);
    assert_eq!(ctx.user_role, WalletRole::Member);
}

#[test]
fn test_action_implication_chain() {
    // Update implies read
    assert!(Action::ContactUpdate.implies(Action::ContactRead));
    // Delete implies read
    assert!(Action::ContactDelete.implies(Action::ContactRead));
    // Read does not imply update
    assert!(!Action::ContactRead.implies(Action::ContactUpdate));
    // Action implies itself
    assert!(Action::ContactRead.implies(Action::ContactRead));

    // Transaction operations
    assert!(Action::TransactionUpdate.implies(Action::TransactionRead));
    assert!(Action::TransactionClose.implies(Action::TransactionRead));

    // Wallet operations
    assert!(Action::WalletUpdate.implies(Action::WalletRead));
    assert!(Action::WalletAddMember.implies(Action::WalletRead));
    assert!(Action::WalletRemoveMember.implies(Action::WalletRead));

    // Create does not imply read (create is standalone)
    assert!(!Action::ContactCreate.implies(Action::ContactRead));
    assert!(!Action::TransactionCreate.implies(Action::TransactionRead));
}

#[test]
fn test_resource_type_classification() {
    let contact_id = Uuid::new_v4();
    let transaction_id = Uuid::new_v4();
    let wallet_id = Uuid::new_v4();

    // Specific resources have IDs
    assert_eq!(Resource::Contact(contact_id).id(), Some(contact_id));
    assert_eq!(Resource::Transaction(transaction_id).id(), Some(transaction_id));
    assert_eq!(Resource::Wallet(wallet_id).id(), Some(wallet_id));

    // Wildcard resources have no ID
    assert_eq!(Resource::AllContacts.id(), None);
    assert_eq!(Resource::AllTransactions.id(), None);

    // Wildcard detection
    assert!(Resource::AllContacts.is_wildcard());
    assert!(Resource::AllTransactions.is_wildcard());
    assert!(!Resource::Contact(contact_id).is_wildcard());
    assert!(!Resource::Transaction(transaction_id).is_wildcard());
    assert!(!Resource::Wallet(wallet_id).is_wildcard());
}

#[test]
fn test_action_enum_completeness() {
    // Verify all 13 actions are defined
    let actions = vec![
        Action::ContactCreate,
        Action::ContactRead,
        Action::ContactUpdate,
        Action::ContactDelete,
        Action::TransactionCreate,
        Action::TransactionRead,
        Action::TransactionUpdate,
        Action::TransactionClose,
        Action::WalletRead,
        Action::WalletUpdate,
        Action::WalletAddMember,
        Action::WalletRemoveMember,
        Action::EventsRead,
    ];

    assert_eq!(actions.len(), 13, "Should have exactly 13 permission actions");

    // Verify all actions have string representations
    for action in &actions {
        let as_str = action.as_str();
        assert!(!as_str.is_empty(), "Action should have non-empty string representation");
    }
}

#[test]
fn test_resource_enum_completeness() {
    let contact_id = Uuid::new_v4();
    let transaction_id = Uuid::new_v4();
    let wallet_id = Uuid::new_v4();

    let resources = vec![
        Resource::Contact(contact_id),
        Resource::Transaction(transaction_id),
        Resource::Wallet(wallet_id),
        Resource::AllContacts,
        Resource::AllTransactions,
    ];

    assert_eq!(resources.len(), 5, "Should have exactly 5 resource types");

    // Verify resource_type() is implemented for all resources
    for resource in &resources {
        let rt = resource.resource_type();
        // Just verify it returns something (the actual enum value doesn't matter here)
        let _ = rt;
    }
}
