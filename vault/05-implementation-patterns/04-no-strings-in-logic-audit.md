# No-Strings-in-Logic Audit

> **Rule:** No string values flow through logic in this project. Strings exist only at I/O boundaries (HTTP/JSON wire, SQL rows, FFI). Inside applier, resolver, snapshot, projection, and permission code, every domain concept must be a typed enum or newtype. If a type is missing a variant or feature, **extend the type** — never fall back to `String`.
>
> See memory: `no-strings-in-logic`.

Status snapshot taken 2026-06-16 after the `set_permission_matrix_entries(&[String])` violation. This file lists every site, the replacement plan, and the order to tackle them.

---

## Tier 0 — Type gaps to fill first

These are missing variants / new types that other fixes depend on. Land them before touching call sites.

| Gap | Location | What to add | Why blocking |
|---|---|---|---|
| `Action::TransactionClose` | `crates/core/domain/src/permission.rs:14` | New variant + `as_str`/`from_str` entry for `"transaction:close"` | Live events use this string; `Action::from_str` returns `None` today → would silently no-op when we switch to `&[Action]`. |
| `Action::WalletManageMembers` | same | `"wallet:manage_members"` | Same — live events reference it. |
| `Action::UserGroupDelete`, `Action::ContactGroupDelete` | same | `"user_group:delete"`, `"contact_group:delete"` | Permission system has these events; enum doesn't. |
| `enum SystemGroup { AllUsers, AllContacts, Owners }` | new file `crates/core/domain/src/system_group.rs` | + `as_str`/`from_str` | `"all_users"` / `"all_contacts"` / `"__owners__"` are hardcoded in 6+ logic sites today. |
| `enum Direction { Owed, Lent }` | new in `domain` | + `as_str`/`from_str` + sign helper | Transaction direction is a raw `&str` through the entire applier + projection chain. |
| `enum TransactionType { Expense, Income, Loan, Repayment, ... }` | new in `domain` | + `as_str`/`from_str` | Same — raw string today. Variants to be derived from current data. |
| `struct Currency(String)` (newtype, validate at construction) | new in `domain` | parses ISO-4217 + custom codes (`IQD`, `USD`, ...) | Currently raw `Option<&str>` everywhere. |
| `EventKind` enum or use existing `EventData` for dispatch | `crates/core/domain/src/event.rs` | Either lift event-type strings out into a typed enum, or always go through `EventData` for branching (no `event_type == "UNDO"`) | 10+ sites do `event_type == "UNDO"` string compares. |

---

## Tier 1 — Applier (`crates/core/applier/src/lib.rs`)

The applier is the most-violated subsystem. Every trait method that takes a string for a domain concept needs to switch to a type.

| Line | Current | Replacement |
|---|---|---|
| 76 | `upsert_contact_row(... name: &str, username: Option<&str>, phone: Option<&str>, email: Option<&str>, notes: Option<&str> ...)` | `Name` and `Email` newtypes (validate non-empty / shape on construction); keep `&str` only for free-form `notes`. |
| 117, 226 | `add_contact_to_system_group(... system_group_name: &str)` / `add_user_to_system_group(... system_group_name: &str)` | `SystemGroup` enum (Tier 0). |
| 167 | `upsert_transaction_row(... direction: &str, transaction_type: Option<&str>, currency: Option<&str>, transaction_date: Option<&str>, due_date: Option<&str> ...)` | `Direction`, `TransactionType`, `Currency` (Tier 0), `chrono::NaiveDate` for dates. |
| 202, 211 | `upsert_wallet_user(... role: &str)` / `update_wallet_user_role(... role: &str)` | `WalletRole` (already exists in domain). |
| 241, 250, 278, 286 | `upsert_user_group(... name: &str)`, `rename_user_group`, `upsert_contact_group`, `rename_contact_group` | `GroupName` newtype (validate uniqueness chars / max length once, propagate everywhere). |
| 313 | `set_permission_matrix_entries(... allowed_actions: &[String], denied_actions: &[String])` ← **my recent code** | `&[Action]` (after Tier 0 adds missing variants). |
| 366 | `add_contact_to_system_group(..., "all_contacts")` | `SystemGroup::AllContacts`. |
| 520 | `let role = data.get("role").and_then(\|v\| v.as_str()).unwrap_or("member");` | Parse to `WalletRole`; missing/invalid → reject the event, not silent fallback. |
| 530 | `add_user_to_system_group(..., "all_users")` | `SystemGroup::AllUsers`. |
| `string_array_field` helper | New helper I added | Replace with `action_array_field` returning `Vec<Action>`; defensive skip per element. |

**Note on `EventData::PermissionMatrixSet { data: serde_json::Value }`:** the payload is a raw blob today. Convert to a typed struct (`PermissionMatrixSetPayload { user_group_id: Uuid, contact_group_id: Uuid, allowed: Vec<Action>, denied: Vec<Action> }`) so the applier never touches `serde_json::Value`.

---

## Tier 2 — Server projection (`crates/server/src/database/repository/server_projection.rs`)

Implements the applier's `Projection` trait. Every `&str` param it takes is downstream from a Tier 1 trait change — when Tier 1 lands, these signatures change in lockstep. Specifics:

| Line | Current | Replacement |
|---|---|---|
| 76, 207, 513, 538, 559, 627, 648 | `name: &str` / `system_group_name: &str` | `GroupName` / `SystemGroup`. |
| 319 | `direction: &str` (in transaction upsert) | `Direction` enum. |
| In my new `set_permission_matrix_entries` impl | `for name in allowed_actions { ... query_scalar("SELECT id FROM permission_actions WHERE name = $1").bind(name) ... }` | Take `&[Action]`; on each, call `Action::as_str()` at the SQL bind boundary only. Better: cache `Action → action_id` in a `HashMap` at startup (the table is fixed). |

---

## Tier 3 — SDK projection (`crates/client/src/sdk_projection.rs`)

Same shape as Tier 2 — every string param is downstream of the trait. Plus:

| Line | Current | Replacement |
|---|---|---|
| 391, 428 | `let is_owner = role == "owner";` | Parse to `WalletRole`, then `matches!(role, WalletRole::Owner)`. |
| In my new `set_permission_matrix_entries` impl | Stores action as TEXT (`group_permission_matrix.action`) using raw `String` | Take `&[Action]`, call `action.as_str()` only at the SQL bind. (DB stays TEXT; logic stays typed.) |

---

## Tier 4 — Permission system

### `crates/server/src/database/repository/permissions.rs`

| Line | Current | Replacement |
|---|---|---|
| 154, 192, 286, 326, 387 | `name: &str` on lookup methods | `GroupName` / `Action` depending on which lookup. |
| 1038 | `handle_cache_invalidation_for_event_raw(... event_type: &str ...)` | Take `EventKind` (or `&EventData`); dispatch by enum, not string. |
| 1043, 1061 | `match event_type { "USER_GROUP_MEMBER_ADDED" \| ... => ... "PERMISSION_MATRIX_SET" => ... }` | `match event_kind { EventKind::UserGroupMemberAdded \| ... }`. |
| 1180–1186 | `matches!(event_type, "PERMISSION_MATRIX_SET" \| "USER_GROUP_MEMBER_ADDED" \| ...)` | Same as above; replace string disjunction with typed `matches!` on enum. |

### `crates/server/src/permissions/resolver.rs`

| Line | Current | Replacement |
|---|---|---|
| 174 | `permitted_contacts_for_action(pool, ctx, "contact:read")` | `Action::ContactRead`. |
| 183 | `permitted_contacts_for_action(pool, ctx, "transaction:read")` | `Action::TransactionRead`. |
| (function signature) | `permitted_contacts_for_action(... action: &str)` | `permitted_contacts_for_action(... action: Action)` then `.as_str()` at the SQL bind only. |

### `crates/core/resolver/src/lib.rs`

| Line | Current | Replacement |
|---|---|---|
| 156 | `if let Some(action) = Action::from_str(&row.action)` | Already typed inside the comparison — fine. But `row.action` is `String` from SQL. Move the parse to the row-load boundary; downstream code holds `Action`. |
| 196, 221 | `row.contact_group_name == "all_contacts"` | Add `SystemGroup` to the row, compare against `Some(SystemGroup::AllContacts)`. |

---

## Tier 5 — Projection rebuild (`crates/server/src/services/projections.rs`)

Eight sites do `event_type == "UNDO"` (lines 70, 113, 178, 259, 376, 429, 524, 569). All should switch to `matches!(event_data, EventData::Undo { .. })` or an `EventKind::Undo` discriminant.

Also: the rebuild's UNDO branch deletes non-system groups (the original matrix-corruption bug). After Tier 1, that delete still happens via raw SQL string. Consider routing it through `Projection::delete_user_group` / `delete_contact_group` calls in a loop, so the rebuild path uses the same typed API as the live path. (Lower priority — the SQL works and runs in a single statement; just flagged for completeness.)

---

## Tier 6 — Snapshot system

### `crates/core/snapshots/src/lib.rs`

| Line | Current | Replacement |
|---|---|---|
| 21 | `pub const UNDO_EVENT_TYPE: &str = "UNDO";` | Delete. Use `EventKind::Undo` or `EventData::Undo { .. }` everywhere. |
| `batch_has_undo(impl Iterator<Item = &str>)` | Iterates strings | `batch_has_undo(impl Iterator<Item = &EventKind>)`. |
| 226–243 (tests) | String literals | Update with typed enum after the API change. |

---

## Tier 7 — Events repository (`crates/server/src/database/repository/events.rs`)

This sits at the SQL boundary, so some string handling is unavoidable on the row-load side. The violations are downstream of the load.

| Line | Current | Replacement |
|---|---|---|
| 48 | `fn from_database(aggregate_type: &str, event_type: &str)` | Take the strings from the row, parse to `AggregateType` + `EventKind`, return typed values. Already half-done — finish the conversion. |
| 504, 534 | `if event_type == "UNDO"` inside `apply_event_batch` | `matches!(event_data, EventData::Undo { .. })`. |
| 653 | `aggregate_type == "permission"` inside `parse_event_data_typed` | `AggregateType::Permission` (parse once, branch on the enum). |
| 846 | `direction = data.get("direction").and_then(\|v\| v.as_str()).unwrap_or("lent");` | Parse to `Direction`; reject event if missing rather than defaulting (defaulting to `"lent"` is a correctness footgun). |
| 1012, 1015, 1021 | `if aggregate_type == "permission"/"contact"/"transaction"` | Branch on `AggregateType` enum. |

---

## Tier 8 — Storage / sync glue

| File:line | Current | Replacement |
|---|---|---|
| `crates/client/src/storage.rs:560` | `let direction = if direction_str == "lent" { ... }` | Parse to `Direction` at the storage boundary; pass enum thereafter. |
| `crates/server/src/handlers/sync.rs:309` | `fn is_undo_event(event_data: &EventData) -> bool` | Already takes `&EventData` ✓. Inspect impl to ensure it branches on the enum (not on serialized data). |

---

## Suggested order of work

1. **Tier 0** — extend `Action`, add `SystemGroup` / `Direction` / `TransactionType` / `Currency` / `EventKind`. One PR per type; each lands with no callers changed.
2. **Tier 1 applier trait signatures** — flip them one at a time. Every flip propagates compile errors to Tier 2 + Tier 3 impls; fix as the compiler points.
3. **Tier 4 permission system** — once `Action` is fully populated, replace string action params everywhere.
4. **Tier 5 projection rebuild + Tier 6 snapshot** — flip the `UNDO` string compares to `EventKind::Undo`. These are mechanical and high-volume.
5. **Tier 7 events repo** — last because everything else depends on it being the *only* place strings leave SQL.

Each tier is its own PR so reviews stay focused and the test suite gates each step.

---

## Recently introduced strings that need to be redone first

These were added in the last session and are technically already "new logic with strings" — they violate the rule retroactively. Fix on top of the audit:

- `applier::Projection::set_permission_matrix_entries(&[String], &[String])` → `&[Action]`.
- `applier::string_array_field` helper → `action_array_field`.
- `ServerProjection::set_permission_matrix_entries` impl: name-to-id lookup per call. Replace with `Action`-keyed cache populated on pool init.
- `SdkProjection::set_permission_matrix_entries` impl: stores action as TEXT via `String`. Take `&[Action]`, serialize via `as_str()` at the SQL bind only.

These should be the very first commits — pay back the new debt before sweeping the old.
