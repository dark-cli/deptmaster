# EventGenerator Missing Features - User ID Resolution

## Problem
The EventGenerator pattern is clean and unified but incomplete. Tests fail with "User not found" when using commands like:
```
"owner: group-member add contributors member_id"
```

The `member_id` literal doesn't resolve to an actual user UUID.

## Root Cause
The CommandRunner has label-to-ID mappings for:
- Contacts: `contact_ids: HashMap<String, String>`
- Transactions: `transaction_ids: HashMap<String, String>`
- User Groups: `user_group_ids: HashMap<String, String>`
- Contact Groups: `contact_group_ids: HashMap<String, String>`

But is MISSING:
- `user_ids: HashMap<String, String>` to map user labels (e.g., "member") to their actual server-assigned UUIDs

## Solution: 4-Part Implementation

### 1. Add user_id getter to client (TRIVIAL)
**File:** `crates/client/src/handlers/auth.rs`

Already exists! The auth response stores `user_id` in database via `persist_auth_response()`:
```rust
database::config_set("user_id", user_id)?;
```

Just need to expose it:
```rust
pub fn get_current_user_id() -> Result<String, String> {
    database::config_get("user_id")
        .map_err(|e| e.to_string())?
        .ok_or_else(|| "No user logged in".to_string())
}
```

### 2. Modify AppInstance to expose user ID (TRIVIAL)
**File:** `crates/client/tests/common/app_instance.rs`

Add after login:
```rust
pub fn get_user_id(&self) -> Result<String, String> {
    self.activate()?;
    client::get_current_user_id()
}
```

### 3. Modify EventGenerator to map user IDs (SIMPLE)
**File:** `crates/client/tests/common/event_generator.rs`

```rust
pub struct EventGenerator {
    pub apps: HashMap<String, AppInstance>,
    runner: RefCell<CommandRunner>,
    user_ids: HashMap<String, String>,  // NEW: app_name -> user_id
}

impl EventGenerator {
    pub fn new(apps: HashMap<String, AppInstance>) -> Self {
        let mut user_ids = HashMap::new();
        for (app_name, app) in &apps {
            if let Ok(uid) = app.get_user_id() {
                user_ids.insert(app_name.clone(), uid);
            }
        }
        
        Self {
            apps,
            runner: RefCell::new(CommandRunner::new()),
            user_ids,
        }
    }
    
    pub fn execute_command(&self, command: &str) -> Result<(), String> {
        // ... existing code ...
        self.runner.borrow_mut().execute_command_with_users(
            action_part,
            &self.user_ids  // PASS user_ids to runner
        )
    }
}
```

### 4. Modify CommandRunner to resolve user IDs (SIMPLE)
**File:** `crates/client/tests/common/command_runner.rs`

```rust
pub struct CommandRunner {
    pub contact_ids: HashMap<String, String>,
    pub transaction_ids: HashMap<String, String>,
    pub user_group_ids: HashMap<String, String>,
    pub contact_group_ids: HashMap<String, String>,
    pub user_ids: HashMap<String, String>,  // NEW: user_label -> user_id
}

impl CommandRunner {
    pub fn execute_command_with_users(
        &mut self, 
        command: &str,
        user_ids: &HashMap<String, String>  // NEW: from EventGenerator
    ) -> Result<(), String> {
        self.user_ids = user_ids.clone();  // Store for use in do_group_member
        self.execute_command(command)
    }

    fn do_group_member(&mut self, args: &[&str], original: &str) -> Result<(), String> {
        // ... existing code ...
        let id = args[2];
        
        // NEW: Try to resolve user label to actual user ID
        let resolved_id = self.user_ids
            .get(id)
            .cloned()
            .unwrap_or_else(|| id.to_string());
        
        // Use resolved_id instead of id
        add_wallet_user_group_member(wallet_id, group_id, resolved_id)?;
        // ...
    }
}
```

## Implementation Steps

1. ✅ Add `get_current_user_id()` to client auth handlers
2. ✅ Add `get_user_id()` method to AppInstance  
3. ✅ Store user_ids HashMap in EventGenerator
4. ✅ Pass user_ids to CommandRunner during command execution
5. ✅ Resolve user labels in `do_group_member` using stored user_ids

## Result
Tests will then work with commands like:
```rust
"owner: group-member add contributors member"  // 'member' resolves to member's UUID
"owner: permission set staff public \"C: r:a c:- w:- d:-, T: r:a c:- w:- d:- x:-\""
"member: sync"
"member: assert contacts count >= 1"
```

## Benefits
- Clean, readable test commands
- Unified pattern across all tests
- Labels stored and reused across apps
- No need for direct API calls per test
