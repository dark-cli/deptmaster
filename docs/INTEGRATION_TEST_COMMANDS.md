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

**Run tests** (requires a running server; default `TEST_SERVER_URL=http://127.0.0.1:8000`):

- `cargo test --test integration_single_app -- --ignored` — single/two-app: signup, login, offline/online, many events
- `cargo test --test integration_multi_app_sync -- --ignored` — three-app: create/sync, concurrent creates, update/delete propagation
- `cargo test --test integration_comprehensive_events -- --ignored` — three-app: event types, mixed ops, full lifecycle

For multi-app setup and shared helpers, see `crates/debitum_client_core/tests/common/` and [DEVELOPMENT.md](./DEVELOPMENT.md).
