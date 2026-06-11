//! Shared event-application logic.
//!
//! Both the server (Postgres) and the SDK (SQLite) need to take a stream of
//! events and mutate their local projection tables to reflect them. The rules
//! are identical on both sides — "a `ContactCreated` event inserts this row,
//! also auto-adds the contact to `all_contacts`, then attaches to any
//! requested groups; a `ContactDeleted` soft-deletes the row AND cascades
//! to its transactions" — but the storage mechanics aren't (sqlx vs
//! rusqlite, async vs sync, owned pool vs &mut conn).
//!
//! This crate factors out the rules. The [`Projection`] trait is a small set
//! of LOW-LEVEL storage mutations (upsert this row, soft-delete that row,
//! cascade-delete transactions for this contact, …). The [`apply`] function
//! pattern-matches on every [`domain::EventData`] variant and translates
//! each one into a sequence of trait calls. The per-variant rules live in
//! `apply` alone; impls just translate to SQL.
//!
//! ## Server-only context
//!
//! Server's projection tables track a `last_event_id` (BIGSERIAL) per row
//! for snapshot bookkeeping; that's a server-only concern the trait doesn't
//! expose. Instead, the server's impl stashes the per-event context (event
//! id, position, wallet/user, timestamp) inside the impl via
//! [`Projection::set_event_context`] before each apply call. SDK's impl
//! leaves the default no-op.
//!
//! ## Status
//!
//! Step 3a covers **contact** events. Transaction and permission events
//! still flow through the server's existing `apply_*_typed` paths; the
//! `apply()` body has placeholder no-op branches for them. 3b/3c migrate
//! those.

use async_trait::async_trait;
use domain::DomainEvent;
use uuid::Uuid;

pub mod patches;
pub use patches::{ContactPatch, TransactionPatch};

/// Storage backend for projections. Implementors:
///
/// - **Server** (`crates/server`): wraps `&PgPool` + per-event metadata
///   (event_db_id, wallet_id, user_id, created_at) set via
///   [`Projection::set_event_context`]. Each mutation emits one or more
///   sqlx queries.
/// - **Client** (`crates/client`): wraps a rusqlite connection.
///   Each mutation runs an equivalent SQLite statement. The per-event
///   context default no-op fits — client doesn't track `last_event_id`.
#[async_trait]
pub trait Projection {
    type Error: std::fmt::Debug + Send;

    /// Optional per-event bookkeeping the impl may need. Called by
    /// [`apply`] right before processing each event so the impl can stash
    /// `event.id`, `event.created_at`, etc. for use inside its CRUD calls.
    async fn set_event_context(&mut self, _event: &DomainEvent) -> Result<(), Self::Error> {
        Ok(())
    }

    // ---------- Contact CRUD ----------

    /// Insert-or-update the contact row by id. Fields are passed by value;
    /// for first creation this writes them all. For an idempotent replay
    /// the impl should overwrite the row (no field-merge — that's
    /// `update_contact_row`'s job).
    async fn upsert_contact_row(
        &mut self,
        id: Uuid,
        wallet_id: Uuid,
        user_id: Uuid,
        name: &str,
        username: Option<&str>,
        phone: Option<&str>,
        email: Option<&str>,
        notes: Option<&str>,
    ) -> Result<(), Self::Error>;

    /// Patch update: any `Some(v)` overwrites the existing field; any
    /// `None` leaves it alone. Implementations use `COALESCE($new, col)`
    /// (Postgres) or load-then-merge (SQLite).
    async fn update_contact_row(
        &mut self,
        id: Uuid,
        wallet_id: Uuid,
        patch: ContactPatch,
    ) -> Result<(), Self::Error>;

    /// Mark the contact as deleted (soft-delete). Does NOT cascade —
    /// `apply` calls [`Self::soft_delete_transactions_for_contact`]
    /// explicitly so the rule is visible at the apply site.
    async fn soft_delete_contact_row(
        &mut self,
        id: Uuid,
        wallet_id: Uuid,
    ) -> Result<(), Self::Error>;

    /// Soft-delete every transaction that referenced this contact. Used by
    /// `apply` when handling [`domain::EventData::ContactDeleted`] (cascade
    /// semantics live in apply, not in `soft_delete_contact_row`).
    async fn soft_delete_transactions_for_contact(
        &mut self,
        contact_id: Uuid,
        wallet_id: Uuid,
    ) -> Result<(), Self::Error>;

    // ---------- Contact group memberships ----------

    /// Add the contact to a wallet-scoped system group by its well-known
    /// name (e.g., `"all_contacts"`). System groups are seeded on wallet
    /// creation and looked up by `(wallet_id, name)`. No-op if the group
    /// doesn't exist (defensive — should always exist).
    async fn add_contact_to_system_group(
        &mut self,
        contact_id: Uuid,
        wallet_id: Uuid,
        system_group_name: &str,
    ) -> Result<(), Self::Error>;

    /// Add the contact to specific groups by id. Each id is validated
    /// against `wallet_id` (silently skipped if it doesn't belong to this
    /// wallet — same defensive policy as the server). Duplicates are
    /// silently ignored.
    async fn add_contact_to_groups(
        &mut self,
        contact_id: Uuid,
        wallet_id: Uuid,
        group_ids: &[Uuid],
    ) -> Result<(), Self::Error>;

    /// Replace the contact's group memberships with exactly the given set.
    /// Implementations DELETE existing memberships (except the system
    /// `all_contacts` membership, which stays) and INSERT the new ones.
    /// Validation against wallet_id same as `add_contact_to_groups`.
    async fn replace_contact_group_memberships(
        &mut self,
        contact_id: Uuid,
        wallet_id: Uuid,
        group_ids: &[Uuid],
    ) -> Result<(), Self::Error>;

    // ---------- Transaction CRUD ----------

    /// True iff the contact exists in this wallet and is NOT soft-deleted.
    /// Used by [`apply`] before processing `TransactionCreated` — the
    /// server-side rule is "transactions can only be created against live
    /// contacts." A `false` here makes `apply` silently skip the event
    /// (no error; matches existing apply_transaction_event_typed behavior).
    async fn contact_is_active(
        &self,
        contact_id: Uuid,
        wallet_id: Uuid,
    ) -> Result<bool, Self::Error>;

    /// Insert-or-update the transaction row. Date strings are in
    /// `%Y-%m-%d` format; impls parse them. `transaction_date = None`
    /// means "default to the event's created_at date" (impls use
    /// [`Self::set_event_context`] for the fallback).
    #[allow(clippy::too_many_arguments)]
    async fn upsert_transaction_row(
        &mut self,
        id: Uuid,
        wallet_id: Uuid,
        user_id: Uuid,
        contact_id: Uuid,
        amount: i64,
        direction: &str,
        transaction_type: Option<&str>,
        currency: Option<&str>,
        description: Option<&str>,
        transaction_date: Option<&str>,
        due_date: Option<&str>,
    ) -> Result<(), Self::Error>;

    /// Patch update. `contact_id == Some(Uuid::nil())` is treated as "no
    /// change" by the impl (server's existing sentinel; preserved here).
    async fn update_transaction_row(
        &mut self,
        id: Uuid,
        wallet_id: Uuid,
        patch: TransactionPatch,
    ) -> Result<(), Self::Error>;

    /// Mark the transaction as soft-deleted. No cascade.
    async fn soft_delete_transaction_row(
        &mut self,
        id: Uuid,
        wallet_id: Uuid,
    ) -> Result<(), Self::Error>;

    // ---------- Wallet membership ----------

    /// Add the user to the wallet's membership table with the given role.
    /// Upserts: if already present, role is replaced. Does NOT manage
    /// the user's system-group membership — `apply` calls
    /// [`Self::add_user_to_system_group`] explicitly for that rule.
    async fn upsert_wallet_user(
        &mut self,
        wallet_id: Uuid,
        user_id: Uuid,
        role: &str,
    ) -> Result<(), Self::Error>;

    /// Replace the user's role in the wallet. No-op if the user isn't a
    /// member yet (defensive — matches existing behavior).
    async fn update_wallet_user_role(
        &mut self,
        wallet_id: Uuid,
        user_id: Uuid,
        role: &str,
    ) -> Result<(), Self::Error>;

    /// Remove the user from the wallet's membership table. Cascading
    /// cleanup of their user_group_members rows happens via the DB's
    /// ON DELETE CASCADE (server) or PRAGMA FK (SDK).
    async fn remove_wallet_user(
        &mut self,
        wallet_id: Uuid,
        user_id: Uuid,
    ) -> Result<(), Self::Error>;

    /// Add the user to a wallet-scoped system user-group by well-known
    /// name (e.g., `"all_users"`). Mirror of
    /// [`Self::add_contact_to_system_group`] for users.
    async fn add_user_to_system_group(
        &mut self,
        wallet_id: Uuid,
        user_id: Uuid,
        system_group_name: &str,
    ) -> Result<(), Self::Error>;

    // ---------- User groups ----------

    /// Insert or rename a (non-system) user group. `name` overwrites on
    /// conflict; impls don't touch the `is_system` flag.
    async fn upsert_user_group(
        &mut self,
        id: Uuid,
        wallet_id: Uuid,
        name: &str,
    ) -> Result<(), Self::Error>;

    /// Rename a non-system user group. Silently no-op for system groups
    /// (server enforces `WHERE is_system = false`; SDK should too).
    async fn rename_user_group(
        &mut self,
        id: Uuid,
        wallet_id: Uuid,
        name: &str,
    ) -> Result<(), Self::Error>;

    /// Delete a non-system user group. Members are cleaned up by DB
    /// cascade. Silently no-op for system groups.
    async fn delete_user_group(
        &mut self,
        id: Uuid,
        wallet_id: Uuid,
    ) -> Result<(), Self::Error>;

    async fn add_user_group_member(
        &mut self,
        user_group_id: Uuid,
        user_id: Uuid,
    ) -> Result<(), Self::Error>;

    async fn remove_user_group_member(
        &mut self,
        user_group_id: Uuid,
        user_id: Uuid,
    ) -> Result<(), Self::Error>;

    // ---------- Contact groups ----------

    async fn upsert_contact_group(
        &mut self,
        id: Uuid,
        wallet_id: Uuid,
        name: &str,
    ) -> Result<(), Self::Error>;

    async fn rename_contact_group(
        &mut self,
        id: Uuid,
        wallet_id: Uuid,
        name: &str,
    ) -> Result<(), Self::Error>;

    async fn delete_contact_group(
        &mut self,
        id: Uuid,
        wallet_id: Uuid,
    ) -> Result<(), Self::Error>;

    async fn add_contact_group_member(
        &mut self,
        contact_group_id: Uuid,
        contact_id: Uuid,
    ) -> Result<(), Self::Error>;

    async fn remove_contact_group_member(
        &mut self,
        contact_group_id: Uuid,
        contact_id: Uuid,
    ) -> Result<(), Self::Error>;
}

/// Apply one event to a projection. Exhaustive match over every variant of
/// [`domain::EventData`]. The compiler enforces every variant has a branch;
/// adding a new variant to `EventData` is a build error here until it's
/// handled.
///
/// Step 3a: contact variants are wired through the trait. Transaction and
/// permission variants are placeholders — they fall through to no-op so
/// the existing per-side apply paths still own them. 3b/3c migrate those.
pub async fn apply<P: Projection + Send>(
    projection: &mut P,
    event: &DomainEvent,
) -> Result<(), P::Error> {
    use domain::EventData as E;

    projection.set_event_context(event).await?;

    match &event.event_data {
        // -------- Contact --------
        E::ContactCreated {
            name,
            username,
            phone,
            email,
            notes,
            group_ids,
        } => {
            projection
                .upsert_contact_row(
                    event.aggregate_id,
                    event.wallet_id,
                    event.user_id,
                    name,
                    username.as_deref(),
                    phone.as_deref(),
                    email.as_deref(),
                    notes.as_deref(),
                )
                .await?;
            // Every contact is implicitly in `all_contacts` (system group).
            projection
                .add_contact_to_system_group(event.aggregate_id, event.wallet_id, "all_contacts")
                .await?;
            // Plus any explicitly requested groups (validated against wallet).
            if !group_ids.is_empty() {
                projection
                    .add_contact_to_groups(event.aggregate_id, event.wallet_id, group_ids)
                    .await?;
            }
            Ok(())
        }

        E::ContactUpdated {
            name,
            username,
            phone,
            email,
            notes,
            group_ids,
        } => {
            let patch = ContactPatch {
                name: name.clone(),
                username: username.clone(),
                phone: phone.clone(),
                email: email.clone(),
                notes: notes.clone(),
                group_ids: group_ids.clone(),
            };
            projection
                .update_contact_row(event.aggregate_id, event.wallet_id, patch)
                .await?;
            // `group_ids = Some(vec)` means "replace memberships with this
            // exact set." `None` means "leave memberships alone."
            if let Some(ids) = group_ids {
                projection
                    .replace_contact_group_memberships(event.aggregate_id, event.wallet_id, ids)
                    .await?;
            }
            Ok(())
        }

        E::ContactDeleted { .. } => {
            projection
                .soft_delete_contact_row(event.aggregate_id, event.wallet_id)
                .await?;
            // Cascade: any transactions for this contact also get soft-deleted.
            projection
                .soft_delete_transactions_for_contact(event.aggregate_id, event.wallet_id)
                .await?;
            Ok(())
        }

        E::ContactUndone { .. } => {
            // UNDO events are filtered before dispatch (their effect is
            // captured in undone_event_ids and skipped events). Nothing to
            // do at apply time.
            Ok(())
        }

        // -------- Transaction --------
        E::TransactionCreated {
            contact_id,
            amount,
            direction,
            transaction_type,
            currency,
            description,
            transaction_date,
            due_date,
        } => {
            // Existing server rule: silently skip the event if the
            // referenced contact doesn't exist or is soft-deleted. The
            // event is still in the log; it just never lands in the
            // transactions projection. Matches apply_transaction_event_typed
            // behavior verbatim.
            if !projection
                .contact_is_active(*contact_id, event.wallet_id)
                .await?
            {
                return Ok(());
            }
            projection
                .upsert_transaction_row(
                    event.aggregate_id,
                    event.wallet_id,
                    event.user_id,
                    *contact_id,
                    *amount,
                    direction,
                    transaction_type.as_deref(),
                    currency.as_deref(),
                    description.as_deref(),
                    transaction_date.as_deref(),
                    due_date.as_deref(),
                )
                .await?;
            Ok(())
        }

        E::TransactionUpdated {
            contact_id,
            amount,
            direction,
            transaction_type,
            currency,
            description,
            transaction_date,
            due_date,
        } => {
            // The wire format makes contact_id non-optional (it's a Uuid,
            // not Option<Uuid>) but the server treats Uuid::nil() as the
            // "don't change contact_id" sentinel. Encode that here so
            // both impls share the convention.
            let patch_contact_id = if *contact_id == Uuid::nil() {
                None
            } else {
                Some(*contact_id)
            };
            let patch = TransactionPatch {
                contact_id: patch_contact_id,
                amount: *amount,
                direction: direction.clone(),
                transaction_type: transaction_type.clone(),
                currency: currency.clone(),
                description: description.clone(),
                transaction_date: transaction_date.clone(),
                due_date: due_date.clone(),
            };
            projection
                .update_transaction_row(event.aggregate_id, event.wallet_id, patch)
                .await?;
            Ok(())
        }

        E::TransactionDeleted { .. } => {
            projection
                .soft_delete_transaction_row(event.aggregate_id, event.wallet_id)
                .await?;
            Ok(())
        }

        E::TransactionUndone { .. } => {
            // UNDO events are filtered before dispatch.
            Ok(())
        }

        // -------- Permission events --------
        //
        // The wire format for permission events uses `data: serde_json::Value`
        // (the inner payload varies by variant). apply() extracts the typed
        // fields it needs here so the Projection trait sees only well-typed
        // args, never raw JSON.

        E::WalletUserAdded { data } => {
            let user_id = parse_uuid_field(data, "user_id");
            let role = data.get("role").and_then(|v| v.as_str()).unwrap_or("member");
            if let Some(uid) = user_id {
                projection
                    .upsert_wallet_user(event.wallet_id, uid, role)
                    .await?;
                // Every wallet member is in the `all_users` system group so
                // the default permission matrix applies to them. Without
                // this they'd be in wallet_users but no permission group,
                // and every action would be rejected.
                projection
                    .add_user_to_system_group(event.wallet_id, uid, "all_users")
                    .await?;
            }
            Ok(())
        }

        E::WalletUserRoleChanged { data } => {
            if let (Some(uid), Some(role)) = (
                parse_uuid_field(data, "user_id"),
                data.get("role").and_then(|v| v.as_str()),
            ) {
                projection
                    .update_wallet_user_role(event.wallet_id, uid, role)
                    .await?;
            }
            Ok(())
        }

        E::WalletUserRemoved { data } => {
            if let Some(uid) = parse_uuid_field(data, "user_id") {
                projection.remove_wallet_user(event.wallet_id, uid).await?;
            }
            Ok(())
        }

        E::UserGroupCreated { data } => {
            let name = data.get("name").and_then(|v| v.as_str()).unwrap_or("");
            projection
                .upsert_user_group(event.aggregate_id, event.wallet_id, name)
                .await?;
            Ok(())
        }

        E::UserGroupUpdated { data } => {
            // Covers USER_GROUP_RENAMED too (same wire effect: change name).
            let name = data.get("name").and_then(|v| v.as_str()).unwrap_or("");
            projection
                .rename_user_group(event.aggregate_id, event.wallet_id, name)
                .await?;
            Ok(())
        }

        E::UserGroupDeleted { .. } => {
            projection
                .delete_user_group(event.aggregate_id, event.wallet_id)
                .await?;
            Ok(())
        }

        E::UserGroupMemberAdded { data } => {
            // aggregate_id is the user_group id; data carries the user.
            if let Some(uid) = parse_uuid_field(data, "user_id") {
                projection
                    .add_user_group_member(event.aggregate_id, uid)
                    .await?;
            }
            Ok(())
        }

        E::UserGroupMemberRemoved { data } => {
            if let Some(uid) = parse_uuid_field(data, "user_id") {
                projection
                    .remove_user_group_member(event.aggregate_id, uid)
                    .await?;
            }
            Ok(())
        }

        E::ContactGroupCreated { data } => {
            let name = data.get("name").and_then(|v| v.as_str()).unwrap_or("");
            projection
                .upsert_contact_group(event.aggregate_id, event.wallet_id, name)
                .await?;
            Ok(())
        }

        E::ContactGroupUpdated { data } => {
            let name = data.get("name").and_then(|v| v.as_str()).unwrap_or("");
            projection
                .rename_contact_group(event.aggregate_id, event.wallet_id, name)
                .await?;
            Ok(())
        }

        E::ContactGroupDeleted { .. } => {
            projection
                .delete_contact_group(event.aggregate_id, event.wallet_id)
                .await?;
            Ok(())
        }

        E::ContactGroupMemberAdded { data } => {
            // aggregate_id is the contact_group id; data carries the contact_id.
            if let Some(cid) = parse_uuid_field(data, "contact_id") {
                projection
                    .add_contact_group_member(event.aggregate_id, cid)
                    .await?;
            }
            Ok(())
        }

        E::ContactGroupMemberRemoved { data } => {
            if let Some(cid) = parse_uuid_field(data, "contact_id") {
                projection
                    .remove_contact_group_member(event.aggregate_id, cid)
                    .await?;
            }
            Ok(())
        }

        // -------- Intentional no-ops at apply layer --------
        //
        // PermissionMatrixSet: the put_permission_matrix HTTP handler writes
        // to group_permission_matrix directly via set_permission_matrix_entries_impl,
        // then emits this event for cache invalidation / WS broadcast.
        // Applying it here would double-write. Once the SDK has its own
        // matrix-set path (post Phase 0.4) this branch may grow.
        //
        // WalletDeleted / OwnershipTransferred: no projection rows are
        // mutated by these in the current model.
        E::PermissionMatrixSet { .. }
        | E::WalletDeleted { .. }
        | E::OwnershipTransferred { .. } => Ok(()),
    }
}

/// Parse a UUID string out of a JSON object field. Returns `None` if the
/// field is missing, not a string, or not a valid UUID — same defensive
/// posture as the existing handlers (events with malformed payloads are
/// silently dropped, not rejected).
fn parse_uuid_field(data: &serde_json::Value, field: &str) -> Option<Uuid> {
    data.get(field)
        .and_then(|v| v.as_str())
        .and_then(|s| Uuid::parse_str(s).ok())
}
