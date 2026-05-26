# Permission matrix: overwriting vs layering analysis

## Summary

**Matrix storage does NOT overwrite.** Each (user_group, contact_group) cell is updated independently; multiple rows coexist (e.g. `all_users×all_contacts=[]` and `all_users×Shared=full`).

**The bug:** For **contact:create** (and similarly for any “create” on a resource that doesn’t exist yet), permission is resolved using **only** the `all_contacts` scope. Other matrix rows (e.g. `all_users×Shared`) are never considered, so we don’t get a “layered” / union effect for create.

---

## 1. Matrix storage: per-cell, not full replace

**Where:** `backend/rust-api/src/handlers/wallets.rs` – `put_permission_matrix`  
**Apply:** `backend/rust-api/src/handlers/sync.rs` – `PERMISSION_MATRIX_SET` in `apply_single_event_to_projections`.

- PUT body is `{ "entries": [ { "user_group_id", "contact_group_id", "action_names" }, ... ] }`.
- For **each** entry we insert one permission event and apply it.
- Application of `PERMISSION_MATRIX_SET` (sync.rs ~2228):
  - `DELETE FROM group_permission_matrix WHERE user_group_id = $1 AND contact_group_id = $2` (only that cell).
  - Then `INSERT` the new action rows for that (ug, cg).

So when the test does:

1. `set_matrix_actions(all_ug, all_cg, [])`  →  all_users×all_contacts has 0 actions.
2. `set_matrix_actions(all_ug, cg_shared_id, full)`  →  all_users×Shared has full actions.

both cells exist; we do **not** replace the whole matrix. **Conclusion: storage is not overwriting.**

---

## 2. Permission resolution: union over (user_groups × resource’s contact_groups)

**Where:** `backend/rust-api/src/services/permission_service.rs` – `resolve_allowed_actions`.

- `user_group_ids` = user’s groups (e.g. `[all_users]`).
- `contact_group_ids` = contact groups that “apply” to the resource (see below).
- Query: `SELECT DISTINCT pa.name FROM group_permission_matrix m ... WHERE m.user_group_id = ANY($1) AND m.contact_group_id = ANY($2)`.

So we take the **union** of all actions from every (user_group × contact_group) pair. That is already a “layered” / priority-union behaviour for **existing** resources.

**Where `contact_group_ids` comes from:** `resolve_contact_groups_for_resource(wallet_id, resource_type, resource_id)`:

- Always includes the wallet’s **all_contacts** group (if present).
- If `resource_type == Contact` and `resource_id == Some(contact_id)`, we also add every `contact_group_id` from `contact_group_members` for that contact.

So for an **existing** contact in Shared:

- `contact_group_ids = [all_contacts, Shared]`.
- We get actions from (all_users×all_contacts) ∪ (all_users×Shared) = [] ∪ full = full.

So for **read/update/delete** on an existing contact, layering works.

---

## 3. Why contact:create is denied (the bug)

For a **contact CREATED** event:

- Sync calls `can_perform(..., "contact:create", ResourceType::Contact, Some(new_contact_id))` (sync.rs uses `map_event_to_permission_action`; for contact it passes `Some(aggregate_id)`).
- `resolve_contact_groups_for_resource(Contact, Some(new_contact_id))`:
  - Adds `all_contacts`.
  - For `contact_id = new_contact_id`, it runs `SELECT contact_group_id FROM contact_group_members WHERE contact_id = $1`. The contact has just been created and **is not in any contact_group_members row yet**, so we get no extra groups.
- So `contact_group_ids = [all_contacts]` only.
- Matrix lookup: only (all_users × all_contacts) is used → actions = [] → contact:create is denied.

So we **never** consider (all_users×Shared) or any other contact group for “create”. The effective rule for create is: “only the all_contacts cell counts,” so it looks like create doesn’t participate in layering. That matches the observed bug (app2 has full on Shared but cannot create).

---

## 4. Root cause in one sentence

**For contact:create we only consider the all_contacts scope (because the new contact has no contact_group_members yet), so permission is not layered/unioned across other contact groups.**

---

## 5. Direction for a layered/priority rules system

- **Keep current behaviour for existing resources:** union of actions over (user_groups × resource’s contact_groups) is correct and already in place.
- **Fix create (and similar “no resource yet” cases):**
  - **Option A – “create if allowed on any scope”:** For `contact:create` (and optionally `transaction:create`), resolve permission by checking whether the user has that action in **any** (user_group × contact_group) cell they have access to (e.g. all contact groups in the wallet, or all groups where the matrix grants any action for this user). If any such cell has `contact:create`, allow create. New contact could stay in all_contacts only, or we could later add “default contact group” or “create in group X” from the client.
  - **Option B – explicit “create scope”:** Introduce a separate concept (e.g. “user may create in contact groups [Shared]”) and check that for create; then you can assign the new contact to one of those groups (or all_contacts) by policy.

Recommendation: implement **Option A** so that “create” obeys the same layered idea as read/update/delete: allow create if the user has contact:create on **any** (user_group × contact_group) they’re in. That fixes the test without changing the matrix storage model and keeps a single, consistent “union over matrix cells” semantics.

---

## 6. Code touchpoints

| Area | File | What to change |
|------|------|----------------|
| Create permission | `permission_service.rs` | For `contact:create` (and optionally `transaction:create`) when the resource is “new” (e.g. contact not in any group yet), resolve allowed actions by using “all contact groups in wallet” (or “all contact groups where user has any permission”) instead of only `[all_contacts]`, so that any matrix row granting create allows the action. |
| Sync push | `sync.rs` | No change to event application; permission check already goes through `can_perform` → `resolve_allowed_actions`. Fix in permission_service is enough. |
| Matrix storage | `wallets.rs`, `sync.rs` (PERMISSION_MATRIX_SET) | No change; per-cell updates are correct. |
