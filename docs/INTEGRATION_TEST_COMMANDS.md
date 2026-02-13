# Integration test commands and assertions

The Rust client core integration tests use a **command/assert** style: you drive the app with text **commands** and check state with text **assertions**. Same idea as the Flutter integration tests. Full vocabulary is defined here; the source of truth is the implementation in `crates/debitum_client_core/tests/common/`.

- **Commands**: `command_runner.rs` (and `event_generator.rs` for multi-app `"app: action"`).
- **Assertions**: `assert_runner.rs`.

Empty lines and lines starting with `#` are skipped in both command and assert lists.

---

## Commands (run_commands / execute_commands)

Used with `AppInstance::run_commands(&["...", ...])` or, for multi-app, `EventGenerator::execute_commands(&["app1: ...", "app2: ..."])`. With `EventGenerator`, each command must be prefixed with the app name, e.g. `app1: contact create "Alice"`.

### General

| Command | Description |
|--------|-------------|
| `sync` | Call `manual_sync()` (pull + push). |
| `wait [ms]` | Sleep for `ms` milliseconds (default 100). Use after actions that trigger sync so other apps see data. |

### Contact

| Command | Description |
|--------|-------------|
| `contact create "Name" [label]` | Create contact; optional `label` for later reference (default: name lowercased). |
| `contact update <label> <field> "value"` | Update contact by label. `field`: `name`, `phone`, `email`, `notes`. |
| `contact delete <label>` | Delete contact by label. |

### Transaction

| Command | Description |
|--------|-------------|
| `transaction create <contactLabel> <direction> <amount> ["description"] [label]` | Create transaction. `direction`: e.g. `owed` / `lent`. Labels default to `t0`, `t1`, … |
| `transaction update <transLabel> <field> <value>` | Update transaction by label. |
| `transaction delete <transLabel>` | Delete transaction by label. |

Labels (contact/transaction) are stored in a single `CommandRunner` per test, so in multi-app tests the same labels refer to the same entities across apps.

---

## Assertions (assert_commands)

Used with `AppInstance::assert_commands(&["...", ...])`. The app is activated, then `get_contacts()`, `get_events()`, and `get_transactions()` are passed to the assert runner. All assertions run against that snapshot.

### Contacts

| Assertion | Meaning |
|-----------|--------|
| `contacts count <n>` | Exactly `n` contacts. |
| `contacts count >= <n>` | At least `n` contacts. |
| `contacts count > <n>` | More than `n` contacts. |
| `contact name "<name>"` | Some contact has this name. |
| `contact 0 name "<name>"` | First contact (by order) has this name. |
| `contact name "<name>" removed` | No contact has this name (e.g. after delete). |

### Events

| Assertion | Meaning |
|-----------|--------|
| `events count <n>` | Exactly `n` events. |
| `events count >= <n>` | At least `n` events. |
| `events event_type <CREATED\|UPDATED\|DELETED> count <n>` | Exactly `n` events of that type. |
| `events event_type <...> count >= <n>` | At least `n` events of that type. |
| `events event_type <...> count > <n>` | More than `n` events of that type. |
| `events aggregate_type <contact\|transaction> count <n>` | Exactly `n` events for that aggregate type. |
| `events aggregate_type <...> count >= <n>` / `count > <n>` | Same with >= or >. |
| `events aggregate_type <...> event_type <CREATED\|UPDATED\|DELETED> count <n>` | Exactly `n` events for that aggregate + event type. |
| `events aggregate_type <...> event_type <...> count >= <n>` / `count > <n>` | Same with >= or >. |
| `events aggregate_type <...> event_type DELETED or UNDO count >= <n>` | At least `n` events with aggregate type and event_type in `{DELETED, UNDO}`. |

### Transactions

| Assertion | Meaning |
|-----------|--------|
| `transactions count > <n>` | More than `n` transactions. |
| `transactions count >= <n>` | At least `n` transactions. |

(Exact `transactions count <n>` can be added if needed; currently only `>` and `>=` are implemented.)

---

## Conventions

- **Quotes**: Use double quotes for names and values that contain spaces, e.g. `contact create "Alice Smith"`.
- **Labels**: Lowercase, no spaces (e.g. `alice`, `contact1`, `t1`). Stored in the runner and shared across commands in the same test.
- **Sync**: Tests assume sync is driven by the app (e.g. WebSocket); use `wait 300` (or similar) after sequences that trigger sync, then one sync to simulate “WS connected”, then assert. No need for per-app manual sync in every step unless a scenario requires it.

**Run tests** (requires a running server; default `TEST_SERVER_URL=http://127.0.0.1:8000`). From the **repository root**:

```bash
cd crates/debitum_client_core
cargo test --test integration -- --ignored
```

For more reliable multi-app runs, add `--test-threads=1`. Filter by module: `cargo test --test integration single_app:: -- --ignored`.

**Suites** (all in one binary; filter by name):

- `single_app::` — single/two-app: signup, login, offline/online, many events
- `multi_app_sync::` — three-app: create/sync, concurrent creates, update/delete propagation
- `comprehensive_events::` — three-app: event types, mixed ops, full lifecycle, complex 20+ events
- `offline_online_multi_app::` — partial offline, offline multi-app conflict (skipped: thread-local offline)
- `conflict::` — simultaneous updates, update-delete conflict, offline-update conflict
- `resync::` — full resync, incremental resync
- `stress::` — high volume, rapid create-update-delete, mixed operations
- `connection::` — sync after many operations (single and multi-app)
- `permissions::` — give/take permissions: member sees data after grant, loses after revoke, read-only cannot create, grant create then member can create
- `groups::` — user groups and contact groups: create/list/add members (simple); revoke default read and grant per (user_group × contact_group) so member sees only contacts in permitted groups (complex). Priority/union: all_users×all_contacts (everyone sees all); custom user group×all_contacts (only that group sees all); different user groups×different contact groups (scoped visibility); user in multiple user groups gets union of permitted contacts.

For multi-app setup and shared helpers, see `crates/debitum_client_core/tests/common/` and [DEVELOPMENT.md](./DEVELOPMENT.md).
