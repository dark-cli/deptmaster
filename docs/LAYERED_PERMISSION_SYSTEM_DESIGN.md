# Layered Permission System – Full Rebuild Design

## Goal

Rebuild the permission system so that **all permissions are resolved through a single layered pipeline**. After resolution, each (user, contact) and each (user, create-context) gets **one** final permission set: the full set of allowed actions (read, create, update, delete, etc.). Every enforcement point (sync push, contact API, transaction API, event filtering) uses this same resolved set—no special cases.

---

## 1. Core idea: layers → single resolved set

- **Layers** = ordered sources of rules. Each layer contributes (user_group × contact_group) → allowed actions.
- **Input**: user, resource (contact/transaction) or “create” context.
- **Resolution**: gather all (user_group, contact_group) pairs that apply; for each pair get actions from the matrix; **combine layers** into one set.
- **Output**: one set of action names per (user, resource) or (user, create-scope). Either “full” (owner/admin) or the resolved allow set.

All read/write/edit/delete checks use this output. No separate code paths.

---

## 2. Rule evaluation: firewall-style vs other options

We need a clear rule: how do we combine multiple (user_group × contact_group) rows into one allow/deny result per action?

### Option A: Allow-only + union (current proposal)

- Matrix stores **only allowed** actions per (ug, cg).
- **Resolution**: union of all allowed actions from every applicable (ug × cg).
- **No explicit deny.** If a row has no action, it doesn’t grant it; other rows can still grant it.
- **Pros**: Simple, predictable, no order dependency. “Any path that allows → allow.”
- **Cons**: Can’t express “Editors can do everything on Shared except delete” without extra groups or rows.

### Option B: First-allow-wins (firewall allow list)

- Rules have a **priority/order** (e.g. layer 0 = system, layer 1 = custom; or each matrix row has a priority).
- For each action, **evaluate rules in order**; **first rule that allows** that action → allow; then stop for that action (or continue for “deny” if we add it).
- So: “first allow passes.”
- **Pros**: Like firewall allow lists; easy to reason “this rule opens the door.”
- **Cons**: Order matters a lot; adding a row can change behaviour; union is often simpler for “multiple groups grant access.”

### Option C: First-deny-wins (firewall deny list)

- Rules can **allow** or **deny** actions. Evaluate in order; **first rule that denies** an action → deny (for that action). Otherwise allow if at least one rule allows.
- So: “first deny blocks.”
- **Pros**: Good for “by default allow, but this one rule denies.”
- **Cons**: We don’t have “default allow” for members today (we have default no-access and then matrix grants). So “first deny” is more natural when you have a broad allow and want to carve out exceptions.

### Option D: Allow + explicit deny, deny wins (Discord-style)

- Matrix can store **allow** and **deny** (e.g. two lists per (ug, cg), or a separate deny matrix).
- **Resolution**: allowed_set = union(all allows) **minus** union(all denies). So **any deny removes the action** regardless of order.
- **Pros**: Very clear: “deny always wins.” No rule order. Easy to say “Viewers × Shared = read only” and “Viewers × VIP = read, deny delete.”
- **Cons**: Schema and UI need allow vs deny; slightly more complex than allow-only.

**Three states per (ug, cg, action): allow, deny, unset.** For this system to be useful we need an implicit **passive / unset** state:

- **Allow** – this rule grants the action (add to allow set).
- **Deny** – this rule revokes the action (add to deny set; wins in final result).
- **Unset / passive** – this rule has **no opinion** for this action: don’t add to allow, don’t add to deny. Other (ug × cg) rows can still allow or deny it.

Without unset, every row would have to explicitly allow or deny every action (e.g. “all_users × all_contacts = read only” would require deny for create, update, delete on that row). With unset, we only list what that row **does** (e.g. allow [read]); anything not listed is passive, so other rows or the default “no access” apply. So yes: **allow + deny is only useful if we have a passive/unset state** — otherwise we can’t express “this rule grants only these” or “this rule denies only these” without listing everything else.

### Option E: Layer priority (override, not union)

- **Layers** are ordered (e.g. 0 = system default, 1 = custom matrix). For each action, **higher layer overrides lower**: if layer 1 has a value (allow or deny) for that action, use it; else use layer 0.
- So we get a single “effective” row per (ug, cg) by layer order, then union across (ug, cg) pairs as today.
- **Pros**: Clear “custom overrides default.” Familiar from firewall “last match” or “override” semantics.
- **Cons**: Order and override semantics must be defined and documented; union across groups is still needed for “user in multiple groups.”

---

### Recommendation

- **Short term (current rebuild):** **Option A (allow-only + union)**. No schema change, no deny, no order. Fix create and placement; all checks use one union. Matches current matrix shape.
- **Next step if you want “deny” or firewall feel:** **Option D (allow + deny, deny wins)**. Add optional deny list per (ug, cg); resolution = allow_union - deny_union. Still no rule order; “deny” is explicit and wins.
- **If you need “first match” behaviour:** **Option B or C** (first allow or first deny wins). Then we need **priority/order** on matrix rows (or layers) and define evaluation order clearly.

So: **firewall “first allow passes” (B) or “first deny blocks” (C) are possible**, but they require ordered rules and clear semantics; **allow-only union (A)** or **allow + deny, deny wins (D)** are simpler and don’t depend on order. Choose A for minimal change, D if you want explicit deny like Discord.

---

### Which is more intuitive and easier to debug: allow+deny vs firewall-style?

**Allow + deny (Discord-style)** is generally **more intuitive** and **easier to debug** than firewall-style.

| Aspect | Allow + deny (Discord-style) | Firewall-style (first match) |
|--------|-----------------------------|-----------------------------|
| **Mental model** | “What do we allow? What do we deny? Deny wins.” No order to remember. | “Rules run in order; first match wins.” You must know and maintain rule order. |
| **Intuitive?** | Yes for most people: add/remove permissions; one rule (deny wins). | Familiar to network/security people; others often find order and “which rule fired?” confusing. |
| **Why can’t X do Y?** | Is Y in deny set? Which (ug×cg) rows have deny for Y? No ordering to trace. | Replay rules in order until one matches; that rule “fired” and caused allow/deny. Order-dependent. |
| **Why can X do Y?** | Which (ug×cg) rows have allow for Y? Union is order-independent. | Which rule was first to allow Y? Depends on full ordered list. |
| **Changing rules** | Add/remove allow or deny; behaviour is predictable (deny still wins). | Inserting or reordering a rule can change which rule fires; easy to break things accidentally. |
| **Debugging** | Two questions: “Who allows this action?” and “Who denies it?” Simple queries, no replay. | “Which rule matched first?” requires evaluating in order or stepping through; harder to automate. |

**Summary:** Allow + deny is more intuitive (“allow list minus deny list”) and easier to debug (“show me who denies this” / “show me who allows this”) because there is **no rule order**. Firewall-style is powerful but order-dependent and harder to explain and trace. Prefer **allow + deny** if you want something intuitive and debuggable.

---

## 4. What counts as a “layer”

Today we effectively have one layer: the **matrix** (user_group × contact_group → actions). Every (ug, cg) row is a rule. “Layered” here means:

1. **Treat the matrix as multiple rules** that apply together (already true: we have many rows).
2. **Resolution always unions** across all (user_groups × resource’s contact_groups) for that user and resource.
3. **Create is just another resolution**: for “create”, the “resource” is “any scope the user can create in” (see below).

So we don’t need new tables for “layers”—we make the **resolution algorithm** the single contract and fix the places that don’t use it (e.g. create).

Optional later: add an explicit **layer order** (e.g. system default = 0, custom matrix = 1, user overrides = 2) and a combine policy (e.g. union vs deny-overrides). For the rebuild, **union of all matrix cells** that apply is enough.

---

## 5. Resolution pipeline (single place)

### 5.1 Inputs

- `wallet_id`, `user_id`, `user_role` (owner | admin | member).
- **Context**:
  - **Existing resource**: `resource_type` (Contact | Transaction), `resource_id` (contact_id or transaction_id).
  - **Create**: `resource_type` (Contact | Transaction), `resource_id = None` (no resource yet).

### 5.2 Steps (one function / one path)

1. **Owner/admin**: if `user_role` is owner or admin → return **full action set** (all contact/transaction/events actions). Done.
2. **User groups**: resolve `user_group_ids` for this user in this wallet (all_users + explicit user_group_members).
3. **Contact groups for context**:
   - **Existing contact**: contact_group_ids = [all_contacts] ∪ contact_group_members(contact_id).
   - **Existing transaction**: contact_group_ids = [all_contacts] ∪ contact_groups of the transaction’s contact (same as today).
   - **Create contact**: contact_group_ids = **all contact groups in the wallet** (or “all contact groups where the matrix has at least one action for this user’s user groups”). So we union over “every scope the user might create in.”
   - **Create transaction**: analogous (all_contacts + any transaction-group logic if we add it).
4. **Matrix lookup**: `SELECT DISTINCT pa.name FROM group_permission_matrix m JOIN permission_actions pa … WHERE m.user_group_id = ANY(user_group_ids) AND m.contact_group_id = ANY(contact_group_ids)`.
5. **Return** the set of action names as the **resolved permission set** for this (user, context).

No other code path should compute “can user do X?”. All callers use this.

### 5.3 Output

- One **HashSet&lt;String&gt;** (or similar) of action names, e.g. `{"contact:read", "contact:create", "transaction:read", …}`.
- **can_perform(action, resource_type, resource_id)** = `resolved_set.contains(action)`.

---

## 6. What “full” means

After resolution, a user either has:

- **Full set** (owner/admin): all contact, transaction, events actions the backend knows about; or  
- **Resolved set** (member): exactly the union of actions from all (user_group × contact_group) pairs that apply.

So “read, write, edit, delete” (and create, etc.) are just elements of that set. No separate “read vs write” logic—only “is this action in the resolved set?”

---

## 7. Create and placement

- **Permission**: For contact:create (resource_id = None), step 3.2 uses “contact_group_ids = all contact groups in wallet” (or “all cg where user has any permission”). So if the user has contact:create in **any** (ug × cg), they get contact:create in the resolved set. Create is allowed.
- **Placement**: When applying a contact CREATED event, the new contact must be placed in at least one contact group so the creator can see it:
  - If the client sends `group_ids`, validate the user has contact:create for those groups (using resolved set for that scope) and add the contact to those groups.
  - If the client omits `group_ids`, use **user_wallet_settings.default_contact_group_ids**; if that’s empty, derive from “contact groups where the user had contact:create” (e.g. pick one) and add the contact there.

Same idea for transaction:create when we have transaction groups.

---

## 8. Sync and events

- **Push**: For each event, map event → (action, resource_type, resource_id). Call **can_perform(action, resource_type, resource_id)** using the resolution pipeline. If false → 403 DEBITUM_INSUFFICIENT_WALLET_PERMISSION.
- **Pull / event filtering**: Use **SyncReadContext** built from the **same** resolution idea: which contact_group_ids grant contact:read / transaction:read for this user’s user groups? Union them; then contact_ids_allowed = contacts in those groups (or None if all_contacts has read). No separate logic.

So sync push and pull both rely on the same layered resolution (same matrix, same union).

---

## 9. API surface (unchanged from outside)

- **GET /api/wallets/:id/me/permissions** (optional resource_type, resource_id): run resolution for that (user, context); return the resolved action set. UI uses this for “can show edit/delete/create?”
- **Matrix GET/PUT**: still edit (user_group × contact_group) → actions. These are the **rules** that feed the layers; resolution doesn’t change the matrix shape.
- **Create contact/transaction**: optional `group_ids`; server validates and places new resource using resolved set + defaults as above.

---

## 10. Implementation checklist (rebuild)

| # | Task | Notes |
|---|------|--------|
| 1 | **Single resolution function** | One place that takes (wallet, user, role, resource_type, resource_id). Returns full set or union of matrix actions. Owner/admin → full set. |
| 2 | **Contact groups for “create”** | When resource_id is None and resource_type is Contact, set contact_group_ids = all wallet contact groups (or “all cg where user has any matrix action”). So create is allowed if any (ug×cg) grants contact:create. |
| 3 | **can_perform** | Thin wrapper: resolve once, then `resolved_set.contains(action)`. All handlers and sync call this only. |
| 4 | **Sync push** | No change to event loop; keep using can_perform for each event. Fix is in resolution. |
| 5 | **Sync pull / read context** | Keep SyncReadContext; ensure it’s derived from same matrix union (which contact groups grant read for this user). Already mostly correct. |
| 6 | **Apply contact CREATED** | When applying CREATED, if creator has create only via specific contact groups (not all_contacts), add new contact to group_ids from request or default from user_wallet_settings or from “groups where user had create”. |
| 7 | **Tests** | Existing permission/groups tests (including “app2 create after grant on Shared”) should pass after 1–6. |

---

## 11. What this fixes

- **Create denied when user has create on a scope**: Fixed by resolving create with “all contact groups” (or “all groups user has any access to”) so any (ug×cg) with contact:create allows create.
- **Inconsistent resolution**: All checks go through one pipeline; no special case for “new contact” that only looks at all_contacts.
- **Visibility of new contact**: Fixed by placement rule (add new contact to creator’s scope or default groups).

After the rebuild, **each user and contact gets a single resolved permission set (read, write, edit, delete, etc.) from the layered matrix; no overwriting, no missing create.**

---

## 12. UI for allow + deny (three states)

You already have a **Rules** tab and a per–(user group × contact group) **Edit Permissions** dialog with checkboxes (allow-only). To support **allow / deny / unset**:

### Per-action control: tri-state

- **Replace each checkbox** with a **tri-state** control so the user can choose:
  - **Allow** (grant)
  - **Deny** (revoke; wins in resolution)
  - **Default** or **—** (unset; no opinion from this rule)
- **Ways to implement:**
  - **Segmented button / chip row** per action: `[ Allow | Deny | — ]`. One option selected; default = “—”.
  - **Icon row**: three icons (check / block / minus), tap to cycle or tap one to set. Tooltip: “Allow”, “Deny”, “No rule”.
  - **Dropdown** per action: “Allow” | “Deny” | “Default (no rule)”.
- **Dependencies** (e.g. “write implies read”, “transaction implies contact:read”) can stay: when user sets Allow for a write action, auto-allow read for that resource; when they set Deny for read, consider denying dependent actions or at least show a hint. Same logic as today, applied to both allow and deny.

### Structure (keep current flow)

- **Rules tab**: list/grid of (user group × contact group) cells; each cell shows a short summary, e.g. “3 allow, 1 deny” or “Read only” (preset label). Tap cell → open **Edit Permissions** dialog.
- **Edit Permissions dialog**: title “Viewers → Shared” (or “all_users → all_contacts”). Group actions by resource (Contact, Transaction, Events) as now. For each action, show the **tri-state** control (Allow / Deny / —). **Save** sends both `allowed_actions` and `denied_actions` (or a single list with a type: allow | deny) to the API.
- **Presets (optional):** “No access”, “Read only”, “Full” as shortcuts that set Allow/Deny/— in bulk so users don’t have to click every row. “Read only” = allow read actions, leave rest unset (or explicitly deny write if you want).

### API shape for three states

- **GET matrix**: each cell returns e.g. `{ "user_group_id", "contact_group_id", "allowed_actions": [...], "denied_actions": [...] }`. Omitted action = unset.
- **PUT matrix**: same shape; backend stores allow and deny per (ug, cg) and resolves with allow_union − deny_union.

### Summary

- **One dialog per (ug, cg)**; inside it, **one tri-state per action** (Allow / Deny / —). Keep grouping by Contact / Transaction / Events. Add optional presets. API carries both allowed and denied lists so the system is easy to debug (“who allows?” / “who denies?”).

---

## 13. Optional later: explicit layer order and deny

- **Layer order**: e.g. layer 0 = system default (all_users×all_contacts), layer 1 = custom matrix rows. Combine in order (e.g. start with layer 0, then union layer 1).
- **Deny rules**: If we add explicit “deny” entries (e.g. “Editors × VIP = deny contact:delete”), combine with “deny wins” or “allow wins” per layer. For now, allow-only + union is enough.

This design keeps the current matrix and adds a **single layered resolution pipeline** so that after resolving the layers, each user and contact gets one clear permission set (full or resolved); create and visibility are part of the same system.
