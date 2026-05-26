# Integration test commands and assertions

The Rust client core integration tests use a **command/assert** style: you drive the app with text **commands** and check state with text **assertions**. Same idea as the Flutter integration tests. Full vocabulary is defined here; the source of truth is the implementation in `crates/debitum_client_core/tests/common/`.

- **Commands**: `command_runner.rs` (and `event_generator.rs` for multi-app `app: action`).
- **Assertions**: `assert_runner.rs`.

Empty lines and lines starting with `#` are skipped in both command and assert lists.

---

## Standards

- **Quoting**: Use **single quotes** (`'...'`) for string arguments in Rust test code so you don’t need backslash escaping, e.g. `'Alice'` instead of `\"Alice\"`. Double quotes are also supported.
- **Multi-app**: Use `EventGenerator::execute_commands(&["app1: ...", "app2: ..."])`. Every command must be prefixed with the app name (e.g. `app1: contact create 'Alice'`). One shared `CommandRunner` keeps labels (contact/transaction) consistent across apps.
- **Wait**: In EventGenerator, use a **standalone** `wait [ms]` command (no app prefix). It sleeps the test thread for `ms` ms (default 100), then syncs all apps. `app1: wait 300` does the same (sleep then sync all). Prefer `wait 300` at the generator level rather than per-app wait for timing.
- **Wallet and permissions**: Do all wallet setup and permission changes via **commands only**—`wallet create`, `wallet select`, `wallet create-invite`, `wallet join`, `permission grant-full`. Avoid manual API calls in tests so scenarios are reproducible and readable.

---

## Helpers (`tests/common/test_helpers.rs`)

| Helper | Purpose |
|--------|---------|
| `test_server_url()` | Server URL; override with env `TEST_SERVER_URL` (default `http://127.0.0.1:8000`). |
| `create_app_instances(n, server_url)` | Create `n` app instances, each with a **unique user**. Each is initialized, signed up, and logged in. Returns a map `"app1"` → instance, … No wallet is created; use commands for that. |
| `create_app_instances_with_user_counts(server_url, counts_per_user)` | Create apps with **shared users**. Example: `&[2, 2, 1, 1, 1]` → app1/app2 = user1, app3/app4 = user2, app5–app7 = user3–user5. All init/signup/login; no wallet. Use for multi-user shared-wallet scenarios. |
| `setup_three_apps(server_url)` | Legacy: one user, one pre-created wallet, three app instances with that wallet selected. Returns an `EventGenerator`. Use the helpers above + commands for new tests. |

---

## Commands (run_commands / execute_commands)

Used with `AppInstance::run_commands(&["...", ...])` or, for multi-app, `EventGenerator::execute_commands(&["app1: ...", "app2: ..."])`. With EventGenerator, prefix each command with the app name. Use standalone `wait [ms]` (no prefix) to sleep the test thread then sync all apps.

### General

| Command | Description |
|--------|-------------|
| `sync` | Call `manual_sync()` (pull + push). |
| `wait [ms]` | Sleep for `ms` milliseconds (default 100). In `run_commands` this runs in the app thread; in EventGenerator use `wait 300` (no app prefix) to sleep the test thread then sync all. |

### Wallet

| Command | Description |
|--------|-------------|
| `wallet create 'name' ['description']` | Create wallet, set it as current, and store as `last_wallet_id` (used by `wallet select`). |
| `wallet select` | Set current wallet to `last_wallet_id` (from a prior `wallet create` or `wallet join` on this runner). |
| `wallet create-invite` | Create invite code for current wallet; store as `last_invite_code` (used by `wallet join` without args). |
| `wallet join [code]` | Join wallet by code; if omitted, use `last_invite_code`. Sets current wallet and `last_wallet_id`. |

### Permission

| Command | Description |
|--------|-------------|
| `permission grant-full` | Set default (all_users × all_contacts) row to full actions: read/create/update/delete for contacts and transactions. |
| `permission grant-read` | Set default row to read-only: contact:read, transaction:read, events:read. |
| `permission revoke-all` | Set default row to no actions (members lose access until re-granted). |

### Contact

| Command | Description |
|--------|-------------|
| `contact create 'Name' [label]` | Create contact; optional `label` for later reference (default: name lowercased). |
| `contact update <label> <field> 'value'` | Update contact by label. `field`: `name`, `phone`, `email`, `notes`. |
| `contact delete <label>` | Delete contact by label. |
| `contact undo <label>` | Undo last action on contact (within undo window, e.g. 5s). |

### Transaction

| Command | Description |
|--------|-------------|
| `transaction create <contactLabel> <direction> <amount> ['description'] [label]` | Create transaction. `direction`: e.g. `owed` / `lent`. Labels default to `t0`, `t1`, … |
| `transaction update <transLabel> <field> <value>` | Update transaction by label. `field`: `amount`, `description`. |
| `transaction delete <transLabel>` | Delete transaction by label. |
| `transaction undo <transLabel>` | Undo last action on transaction (within undo window). |

Labels (contact/transaction) are stored in a single `CommandRunner` per test, so in multi-app tests the same labels refer to the same entities across apps.

---

## Assertions (assert_commands)

Used with `AppInstance::assert_commands(&["...", ...])`. The app is activated, then `get_contacts()`, `get_events()`, and `get_transactions()` are passed to the assert runner. All assertions run against that snapshot.

All count assertions are **exact equality only** (no `>=` or `>`). Use `contacts count 5`, `events count 12`, etc.

### Contacts

| Assertion | Meaning |
|-----------|--------|
| `contacts count <n>` | Exactly `n` contacts. |
| `contact name 'name'` | Some contact has this name. |
| `contact 0 name 'name'` | First contact (by order) has this name. |
| `contact name 'name' removed` | No contact has this name (e.g. after delete). |

### Events

| Assertion | Meaning |
|-----------|--------|
| `events count <n>` | Exactly `n` events. |
| `events event_type <CREATED\|UPDATED\|DELETED> count <n>` | Exactly `n` events of that type. |
| `events aggregate_type <contact\|transaction> count <n>` | Exactly `n` events for that aggregate type. |
| `events aggregate_type <...> event_type <CREATED\|UPDATED\|DELETED> count <n>` | Exactly `n` events for that aggregate + event type. |
| `events aggregate_type <...> event_type DELETED or UNDO count <n>` | Exactly `n` events with aggregate type and event_type in `{DELETED, UNDO}`. |

### Transactions

| Assertion | Meaning |
|-----------|--------|
| `transactions count <n>` | Exactly `n` transactions. |

---

## Conventions

- **Quotes**: Prefer single quotes in Rust (e.g. `'Alice'`, `'Alice Smith'`). Use double quotes when the string contains single quotes.
- **Labels**: Lowercase, no spaces (e.g. `alice`, `contact1`, `t1`). Stored in the runner and shared across commands in the same test.
- **Sync**: Tests assume sync is driven by the app (e.g. WebSocket); use `wait 300` (or similar) after sequences that trigger sync, then sync once to simulate “WS connected”, then assert. No need for per-app manual sync every step unless the scenario requires it.

---

## Run tests

Requires a running server (default `TEST_SERVER_URL=http://127.0.0.1:8000`). From the **repository root**:

```bash
cd crates/debitum_client_core
cargo test --test integration -- --ignored
```

For more reliable multi-app runs, add `--test-threads=1`. Filter by module or test name:

```bash
cargo test --test integration single_app:: -- --ignored
cargo test --test integration comprehensive_events::comprehensive_seven_apps -- --ignored
```

**Suites** (all in one binary; filter by name):

- `single_app::` — single/two-app: signup, login, offline/online, many events
- `multi_app_sync::` — three-app: create/sync, concurrent creates, update/delete propagation
- `comprehensive_events::` — 7 apps, 5 users, one shared wallet; all event types (create/update/delete/undo); wallet and permissions via commands; exact sync check (event signatures + contacts/transactions)
- `offline_online_multi_app::` — partial offline, offline multi-app conflict (skipped: thread-local offline)
- `conflict::` — update-delete conflict (one app updates, another deletes; simultaneous updates in multi_app_sync)
- `resync::` — full resync, incremental resync (uses `create_app_instances` + wallet/permission commands)
- `permissions::` — permissions and groups: give/take (member sees/loses/restores on grant/revoke/grant-read; read-only cannot create; grant-full then member can create); permission limits (deny overrides allow, union of groups, scoped denial); user/contact groups (create/list/add members); matrix and priority (custom ug×cg, union, scoped visibility, two-app join with no default then grant via contact group).

For multi-app setup and shared helpers, see `crates/debitum_client_core/tests/common/` and [DEVELOPMENT.md](./DEVELOPMENT.md).
