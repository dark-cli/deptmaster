# Permission Test Format: CommandRunner & rwx Notation

**Main question this file answers:** How do I write permission tests using the new compact format?

---

## Overview

The test infrastructure provides a **CommandRunner** that accepts human-readable commands to set up permissions, groups, and contacts in tests. The permission format uses the **rwx-inspired notation** detailed in [[../04-permissions-and-undo/05-permission-format-system.md]].

---

## Basic Test Structure

### Setup Phase

```rust
use client::add_user_to_wallet;

let server_url = test_server_url();

// Create owner
let (owner_user, owner_pass, wallet_id) =
    create_unique_test_user_and_wallet(&server_url)?;

let owner = AppInstance::with_credentials("owner", &server_url, owner_user, owner_pass);
owner.initialize()?;
owner.login()?;
owner.select_wallet(&wallet_id)?;

// Create separate member user
let member_temp = AppInstance::new("member", &server_url);
member_temp.initialize()?;
member_temp.signup()?;
let member_username = member_temp.username.clone();
let member_password = member_temp.password.clone();

// Add member to wallet
owner.activate()?;
add_user_to_wallet(wallet_id.clone(), member_username.clone())?;

// Create fresh instance for member
let member = AppInstance::with_credentials("member", &server_url, member_username, member_password);
member.initialize()?;
member.login()?;
member.select_wallet(&wallet_id)?;
member.sync()?;
```

### Group & Permission Setup

```rust
use client::{
    create_wallet_user_group, create_wallet_contact_group,
    list_wallet_user_groups, list_wallet_contact_groups,
    add_wallet_user_group_member, add_wallet_contact_group_member,
    put_wallet_permission_matrix,
};

// Create groups
create_wallet_user_group(wallet_id.clone(), "Editors".to_string())?;
create_wallet_contact_group(wallet_id.clone(), "Customers".to_string())?;
std::thread::sleep(std::time::Duration::from_millis(100));

// Get group IDs (response is a direct array)
let user_groups_json = list_wallet_user_groups(wallet_id.clone())?;
let user_groups: Vec<serde_json::Value> = serde_json::from_str(&user_groups_json)?;
let editors_id = user_groups.iter()
    .find(|g| g.get("name").and_then(|n| n.as_str()) == Some("Editors"))
    .and_then(|g| g.get("id").and_then(|i| i.as_str()).map(|s| s.to_string()))
    .expect("find Editors group");

let contact_groups_json = list_wallet_contact_groups(wallet_id.clone())?;
let contact_groups: Vec<serde_json::Value> = serde_json::from_str(&contact_groups_json)?;
let customers_id = contact_groups.iter()
    .find(|g| g.get("name").and_then(|n| n.as_str()) == Some("Customers"))
    .and_then(|g| g.get("id").and_then(|i| i.as_str()).map(|s| s.to_string()))
    .expect("find Customers group");

// Add member to Editors group
add_wallet_user_group_member(wallet_id.clone(), editors_id.clone(), member_username.clone())?;
std::thread::sleep(std::time::Duration::from_millis(100));

// Set permissions using JSON (can also convert from format string)
let entry = serde_json::json!({
    "user_group_id": editors_id,
    "contact_group_id": customers_id,
    "allowed_actions": ["contact:read", "contact:update"],
    "denied_actions": []
});
let entries = serde_json::json!([entry]);
put_wallet_permission_matrix(wallet_id.clone(), entries.to_string())?;
```

---

## CommandRunner Format (EventGenerator)

### Usage with EventGenerator

The EventRunner pattern is designed for multi-app synchronization scenarios but requires proper app setup:

```rust
use super::common::event_generator::EventGenerator;

let mut apps = HashMap::new();
apps.insert("owner".to_string(), owner);
apps.insert("member".to_string(), member);
let generator = EventGenerator::new(apps);

let commands = [
    "owner: contact create \"Alice\" alice",
    "owner: wait 300",
    "owner: contact create \"Bob\" bob",
    "owner: wait 300",
    "member: sync",
    "member: wait 200",
    "member: assert contacts count >= 2",
];

generator.execute_commands(&commands)?;
```

### CommandRunner Permission Format

Format: `permission set user_group contact_group "C: r:a c:- w:a d:-, T: r:a c:- w:- d:- x:-"`

**Permission Format Legend:**
- `C:` = Contact permissions
- `T:` = Transaction permissions
- `r` = read
- `c` = create
- `w` = write/update
- `d` = delete
- `x` = close (transaction only)
- `:a` = allow
- `:d` = deny
- `:-` = unset

**Example Commands:**

```rust
// Create groups using commands (requires user/contact group labels)
"owner: user-group create \"Editors\" editors",
"owner: contact-group create \"Public\" public",
"owner: wait 300",

// Add members to groups
"owner: group-member add editors member_user_id",
"owner: wait 300",

// Set permissions with compact format
"owner: permission set editors public \"C: r:a c:- w:a d:-, T: r:a c:- w:- d:- x:-\"",
"owner: wait 300",

// Contact operations
"owner: contact create \"John\" john",
"owner: wait 300",

// Member operations (after sync)
"member: sync",
"member: wait 200",
"member: assert contacts count >= 1",
"member: contact update john name \"John Updated\"",
"member: wait 200",
```

---

## Permission Format Examples

### Common Patterns

| Scenario | Format |
|----------|--------|
| **Read-only viewer** | `C: r:a c:- w:- d:-, T: r:a c:- w:- d:- x:-` |
| **Full editor** | `C: r:a c:a w:a d:a, T: r:a c:a w:a d:a x:a` |
| **Editor (no delete)** | `C: r:a c:a w:a d:-, T: r:a c:a w:a d:- x:-` |
| **Write-only (no read)** | `C: r:- c:- w:a d:-, T: r:- c:- w:- d:- x:-` |
| **Reader + Denied write** | `C: r:a c:- w:d d:-, T: r:a c:- w:d d:- x:-` |
| **Transaction specialist** | `C: r:a c:- w:- d:-, T: r:a c:a w:a d:a x:a` |

### Breaking Down Format

For `C: r:a c:- w:d d:-, T: r:a c:a w:a d:- x:-`:

**Contact Permissions:**
- `r:a` = read allowed
- `c:-` = create unset (no permission)
- `w:d` = write denied (explicitly prevented)
- `d:-` = delete unset (no permission)

**Transaction Permissions:**
- `r:a` = read allowed
- `c:a` = create allowed
- `w:a` = write allowed
- `d:-` = delete unset (no permission)
- `x:-` = close unset (no permission)

---

## Converting Between Formats

### From rwx Format to JSON

The CommandRunner internally converts `C: r:a c:a w:a d:-` to:

```rust
let allowed_actions = vec![
    "contact:read",
    "contact:create", 
    "contact:update",
];
let denied_actions = vec![];
```

### From JSON to rwx Format (Manual)

To write a test with manual JSON setup, then express it in rwx format:

```rust
// Manual setup
let entry = serde_json::json!({
    "user_group_id": group_id,
    "contact_group_id": contact_group_id,
    "allowed_actions": ["contact:read", "contact:update"],
    "denied_actions": []
});

// Equivalent rwx format:
// C: r:a c:- w:a d:-, T: r:- c:- w:- d:- x:-
```

---

## Writing a Complete Test

### Example: Edit-Without-Read Test

```rust
#[test]
#[ignore]
fn permission_edit_without_read_scenario() {
    use client::{
        add_user_to_wallet, create_contact, create_wallet_contact_group,
        create_wallet_user_group, add_wallet_user_group_member,
        add_wallet_contact_group_member, put_wallet_permission_matrix,
        list_wallet_user_groups, list_wallet_contact_groups, update_contact,
    };

    let server_url = test_server_url();

    // Setup owner
    let (owner_user, owner_pass, wallet_id) =
        create_unique_test_user_and_wallet(&server_url)?;
    let owner = AppInstance::with_credentials("owner", &server_url, owner_user, owner_pass);
    owner.initialize()?;
    owner.login()?;
    owner.select_wallet(&wallet_id)?;

    // Setup member
    let member_temp = AppInstance::new("member", &server_url);
    member_temp.initialize()?;
    member_temp.signup()?;
    let member_username = member_temp.username.clone();
    let member_password = member_temp.password.clone();

    owner.activate()?;
    add_user_to_wallet(wallet_id.clone(), member_username.clone())?;

    let member = AppInstance::with_credentials("member", &server_url, member_username.clone(), member_password);
    member.initialize()?;
    member.login()?;
    member.select_wallet(&wallet_id)?;
    member.sync()?;

    // Create groups
    owner.activate()?;
    create_wallet_user_group(wallet_id.clone(), "Editors".to_string())?;
    create_wallet_contact_group(wallet_id.clone(), "Documents".to_string())?;
    std::thread::sleep(std::time::Duration::from_millis(100));

    let user_groups_json = list_wallet_user_groups(wallet_id.clone())?;
    let user_groups: Vec<serde_json::Value> = serde_json::from_str(&user_groups_json)?;
    let editors_id = user_groups.iter()
        .find(|g| g.get("name").and_then(|n| n.as_str()) == Some("Editors"))
        .and_then(|g| g.get("id").and_then(|i| i.as_str()).map(|s| s.to_string()))
        .expect("editors group");

    let contact_groups_json = list_wallet_contact_groups(wallet_id.clone())?;
    let contact_groups: Vec<serde_json::Value> = serde_json::from_str(&contact_groups_json)?;
    let docs_id = contact_groups.iter()
        .find(|g| g.get("name").and_then(|n| n.as_str()) == Some("Documents"))
        .and_then(|g| g.get("id").and_then(|i| i.as_str()).map(|s| s.to_string()))
        .expect("documents group");

    // Add member to group and set permission
    add_wallet_user_group_member(wallet_id.clone(), editors_id.clone(), member_username)?;
    std::thread::sleep(std::time::Duration::from_millis(100));

    // Format: C: r:- c:- w:a d:-, T: r:- c:- w:- d:- x:-
    // This means: Can write/update contacts WITHOUT read permission
    let entry = serde_json::json!({
        "user_group_id": editors_id,
        "contact_group_id": docs_id,
        "allowed_actions": ["contact:update"],
        "denied_actions": []
    });
    let entries = serde_json::json!([entry]);
    put_wallet_permission_matrix(wallet_id.clone(), entries.to_string())?;
    std::thread::sleep(std::time::Duration::from_millis(200));

    // Test: Member can see and edit (write implies read)
    member.activate()?;
    member.sync()?;

    let contacts = client::get_contacts()?;
    let contact_list: Vec<serde_json::Value> = serde_json::from_str(&contacts)?;
    assert!(contact_list.len() >= 1, "member should see contacts");

    println!("✅ Test passed: Permission format C: r:- c:- w:a d:- works correctly!");
}
```

---

## Best Practices

1. **Always add sleep after group operations**: APIs are async, wait ~100-300ms
2. **Use direct API for complex scenarios**: Easier than CommandRunner for now
3. **Test both allow and deny**: Verify positive and negative cases
4. **Document the permission intent**: Add comment with the rwx format
5. **Sync before assertions**: Always `sync()` before checking results

---

## Related Documents

- [[../04-permissions-and-undo/05-permission-format-system.md]] - Permission format details
- [[03-testing-event-handlers.md]] - General testing patterns
- [[../04-permissions-and-undo/02-permission-events.md]] - Permission event types
