---
tags:
  - client
  - planning
  - active
---

# Client Refactoring Plan

**Branch:** `client/refactor-and-stabilize`
**Started:** 2026-06-08
**Goal:** Stabilize the Rust client core and get most of the 12 known failing integration tests passing.

This mirrors the backend process: **read → document → divide & conquer → fix → tests pass**.

---

## Phase 1: Discovery (✅ in progress)
## Phase 0: Shared domain crate (NEW — added 2026-06-08)
> 🔴 **Read [[03-api-contract-audit]] first.** The current `client/refactor-and-stabilize` backend hardened `DomainEvent` to require `idempotency_key` and reject client-provided `id`. The client was never updated. Right now the client's push events fail to deserialize on the server, and the client treats the failure as "offline" — so events stay local forever.
>
> **Important correction:** `BUGS.md` was written against `main`, where the contract was different and the client's payload worked. The contract gap **blocks running the tests** but does not by itself explain the 12 catalogued bugs. After the payload fix, we have to actually run the tests against the current backend to see which bugs are still real and which were silently fixed by other backend work (user_readable_events cache, type-driven dispatch, etc.).
>
> Phase 0 (shared crate) is still the right structural move — it makes this class of contract drift impossible.

> 🔴 **Read [[03-api-contract-audit]] first.** The client's `POST /api/sync/events` payload doesn't match what the server's `DomainEvent` deserializer accepts (`id` instead of generated, missing `idempotency_key`/`wallet_id`/`user_id`/`created_at`, wrong `event_data` shape). Every event the client pushes silently fails to deserialize on the server and the client treats it as a network error, keeping events local forever. This is almost certainly the root cause of BUGS #1–#11 in `BUGS.md`. Phase 0 (shared crate) makes this class of bug structurally impossible.


After the discovery review surfaced how much the client and server duplicate (events, permissions, projections, replay logic), the decision was made to extract shared types **first**, before applying any bug fixes. See [[02-shared-domain-crate]] for the full proposal and [[01-design-notes]] Decision 4 for the summary.

**Order:**
1. Create `crates/domain` (pure types) with backend's `EventData`, `Action`, `Resource`, `WalletRole`, projection structs copied in. No callers touched yet.
2. Create `crates/debitum_event_replay` (`apply(state, &event) -> state`) factored from the server's type-driven handlers.
3. Migrate backend to use the shared crates. All 59 backend tests must still pass.
4. Migrate client to use the shared crates. This alone should kill some of the BUGS (#8, #9 likely).
5. Then continue with Phase 2 / Phase 3 below.

**Open questions blocking start** (need user input):
1. Workspace `Cargo.toml` at the root, or keep crates independent with path deps?
2. Should `frontend/` (Dioxus web) also depend on `domain`?
3. OK with a thin DTO shell in `flutter_sdk` for FRB ↔ Dart?

---


- [x] Branch created off `fix/test-compilation`
- [x] Inventoried Rust core modules (`06-client/00-overview.md`)
- [x] Catalogued failing tests (`BUGS.md` already exists with 12 entries)
- [ ] Run integration tests against live backend, confirm BUGS.md still accurate (Task #12)
- [ ] Document sync flow, storage schema, event flow

---

## Phase 2: Divide & Conquer

The Rust core is ~3000 LOC across 8 handwritten modules. Tackle in dependency order (foundational first):

### Module 1: `ids.rs` (109 LOC)
**Status:** likely clean already
**Review checklist:**
- [ ] Are `WalletId`, `ContactId`, `TransactionId` actually used everywhere they should be? Or do raw `String`/`Uuid` slip through?
- [ ] Is parse-validation centralized?

### Module 2: `models.rs` (167 LOC)
**Review:**
- [ ] Domain types match server's `EventData` variants?
- [ ] Currency handling consistent?
- [ ] Any place where structs duplicate fields they shouldn't?

### Module 3: `storage.rs` (343 LOC) — **CRITICAL**
**Review:**
- [ ] SQLite schema documented
- [ ] `StoredEvent` matches what server expects on push
- [ ] **Bug-relevant:** add `idempotency_key` column (currently missing — server-side fix already shipped expects this)
- [ ] Wallet-scoped clears, projection writes, config storage

### Module 4: `state_builder.rs` (333 LOC)
**Review:**
- [ ] Event-replay logic matches backend's `apply_event_batch` semantics
- [ ] Handles all event variants the server emits (CREATED/UPDATED/DELETED/UNDO for contact + transaction)
- [ ] **Bug-relevant:** does it handle UPDATED events at all? (BUGS #8, #9 say "no UPDATED for transaction/contact" — could be replay or could be event_type mapping)

### Module 5: `crud.rs` (400 LOC)
**Review:**
- [ ] Event creation produces correctly-shaped events
- [ ] **Bug-relevant:** generate `idempotency_key` per UI action, NOT `event_id` locally (the backend now expects this)
- [ ] Update/delete semantics (do updates actually produce UPDATED events?)

### Module 6: `sync.rs` (261 LOC) — **CRITICAL, root of most BUGS**
**Review:**
- [ ] Push payload structure (rename `id` → `idempotency_key`)
- [ ] Pull merge logic: full vs incremental, dedup
- [ ] Permission revoke/grant cascade (clear + resync)
- [ ] **Bug-relevant:** most of BUGS #1-#7, #10, #11 land here

### Module 7: `api.rs` (500 LOC)
**Review:**
- [ ] HTTP client correctness
- [ ] Auth header propagation
- [ ] Error handling (network vs permission errors)

### Module 8: `lib.rs` (790 LOC)
**Review:**
- [ ] FRB exports
- [ ] Backoff and in-flight gating
- [ ] Initialization order

---

## Phase 3: Fixes (in priority order)

### Cluster A: Architectural — idempotency_key
**Tracked in:** [[../client-todo]] HIGH PRIORITY
**Blocks:** unknown — but backend now expects this so we may be silently broken
**Fix:** client generates `idempotency_key` per action, stores it, sends in sync payload; never generates `event_id` locally.

### Cluster B: UPDATED events not visible (BUGS #8, #9)
**Theory:** likely event_type mapping or the client's `crud::update_*` functions emit something other than `UPDATED`.
**Approach:** add a test that triggers update → check the local event log shape → check what's pushed → check what comes back from pull. The discrepancy will be obvious.

### Cluster C: Multi-app sync visibility (BUGS #1, #2, #3, #10, #11)
**Theory:** likely `pull_and_merge` doesn't honor "wallet has events I never saw" properly. Backend's user_readable_events cache should make these visible; maybe the client's pull never fetches them.
**Approach:** add tracing around the pull path, compare what server returns vs what local SQLite ends up with.

### Cluster D: Permission-filtered visibility (BUGS #4, #5, #6, #7)
**Theory:** related to C — when a member gets read permission, they should see existing data; the resync-on-grant logic in `check_read_revoked_and_resync` may not actually pull everything.
**Approach:** verify after a grant the client does a *full* pull (not incremental).

### Cluster E: Permission resolution (BUG #12)
**Theory:** backend issue, not client. Confirm via direct API call (curl `/api/permissions/my`).

---

## Success Criteria

- [ ] BUGS.md down to 0–2 entries
- [ ] All client integration tests pass (or have a documented reason to skip)
- [ ] No "TODO: ARCHITECTURE FIX NEEDED" comments left in `sync.rs` / `crud.rs`
- [ ] Client/server agree on payload shape (`idempotency_key` everywhere)
- [ ] Documentation in `vault/06-client/` is complete (overview + sync-flow + storage-schema + event-flow)
- [ ] Update `vault/client-todo.md` and `vault/backend-todo.md` to reflect work done

---

## Out of Scope (for this branch)

- Flutter UI redesign (`mobile/lib/screens/*.dart`) — only touch if it blocks a fix
- New features
- Anything in `mobile/lib/` larger than a small fix
- Backend changes (separate branch if needed)

---

## Related

- [[00-overview]] — module map
- [[../client-todo]] — full client backlog
- [[../backend-todo]] — backend backlog (for cross-reference)
- `crates/flutter_sdk/BUGS.md` — failing test catalog
