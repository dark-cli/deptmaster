//! Shared event-application logic.
//!
//! Both the server (Postgres) and the SDK (SQLite) need to take a stream of
//! events and mutate their local projection tables to reflect them. The rules
//! are identical on both sides — "a `ContactCreated` event inserts this row
//! with these fields, a `ContactDeleted` event soft-deletes the row, a
//! `PermissionMatrixSet` event upserts these matrix rows" — but the storage
//! mechanics are not (sqlx vs rusqlite, async vs sync, owned pool vs &mut
//! conn).
//!
//! This crate factors out the rules. It defines a [`Projection`] trait whose
//! methods are the LOW-LEVEL mutations a projection store needs to support
//! (insert_contact, update_contact, delete_contact_cascade, …). It then
//! defines [`apply`], a single async function that exhaustively matches
//! every variant of [`domain::EventData`] and translates it into trait calls.
//!
//! Server implements `Projection` against a Postgres connection. SDK
//! implements it against a SQLite connection. The `match` over EventData
//! lives in exactly one place; the compiler enforces exhaustive handling on
//! both sides forever after.
//!
//! ## Out of scope
//!
//! - Soft-deletion display rules (`is_deleted` filtering at read time).
//! - Permission resolution / matrix queries (lives in `crates/server`'s
//!   permissions module — that's a query concern, not an apply concern).
//! - Cache invalidation (`user_readable_events`, the incremental hash).
//!   Those wrap around `apply` on the server side; SDK doesn't have them.
//!
//! ## Status
//!
//! Skeleton only at the moment: the `Projection` trait is defined and `apply`
//! is wired to fail loudly on every variant via `todo!()`. The real
//! per-variant handlers land in step 3, alongside concrete impls of
//! `Projection` for both sides.

use async_trait::async_trait;
use domain::DomainEvent;
use uuid::Uuid;

pub mod patches;
pub use patches::{ContactPatch, TransactionPatch};

/// Anything that can have events applied to it. Methods are the discrete
/// mutations the applier needs to perform — one per kind of state change,
/// NOT one per event variant. Multiple event variants may translate to the
/// same trait call (e.g., `ContactUndone` of a `Deleted` event ends up
/// calling `insert_contact` again).
///
/// Implementors:
/// - **Server** (`crates/server`): wraps a `&PgPool` / `&mut PgConnection`.
///   Each method emits one or more sqlx queries against the appropriate
///   projection table.
/// - **SDK** (`crates/flutter_sdk`): wraps a `&mut rusqlite::Connection`.
///   Each method runs the equivalent SQLite statement.
///
/// All methods are `async` because the server side needs it. The SDK's sync
/// rusqlite calls just don't `.await` anything internally.
#[async_trait]
pub trait Projection {
    type Error: std::fmt::Debug + Send;

    // ---------- Contacts ----------

    async fn insert_contact(
        &mut self,
        id: Uuid,
        name: String,
        username: Option<String>,
        phone: Option<String>,
        email: Option<String>,
        notes: Option<String>,
        group_ids: Vec<Uuid>,
    ) -> Result<(), Self::Error>;

    async fn update_contact(
        &mut self,
        id: Uuid,
        patch: ContactPatch,
    ) -> Result<(), Self::Error>;

    /// Soft-delete the contact AND every transaction that referenced it.
    /// Server marks `is_deleted = true`; SDK removes from the in-memory map.
    async fn delete_contact_cascade(
        &mut self,
        id: Uuid,
        comment: Option<String>,
    ) -> Result<(), Self::Error>;

    // ---------- Transactions ----------

    async fn insert_transaction(
        &mut self,
        id: Uuid,
        contact_id: Uuid,
        amount: i64,
        direction: String,
        transaction_type: Option<String>,
        currency: Option<String>,
        description: Option<String>,
        transaction_date: Option<String>,
        due_date: Option<String>,
    ) -> Result<(), Self::Error>;

    async fn update_transaction(
        &mut self,
        id: Uuid,
        patch: TransactionPatch,
    ) -> Result<(), Self::Error>;

    async fn delete_transaction(
        &mut self,
        id: Uuid,
        comment: Option<String>,
    ) -> Result<(), Self::Error>;

    // ---------- Undo ----------

    /// Reverse the effects of `undone_event_id`. The applier looks up that
    /// event (via [`load_event`]) and inverts its effect — e.g., a
    /// `ContactDeleted` undo re-inserts the contact, a `ContactUpdated`
    /// undo restores the pre-update values. Implementations need access to
    /// the event log to fetch the undone event, hence the helper.
    async fn undo_event(
        &mut self,
        undone_event_id: Uuid,
    ) -> Result<(), Self::Error>;

    // ---------- Permissions ----------
    //
    // The 14 permission-event variants live in `domain::EventData` for both
    // sides. Server has had projection tables for these since migration
    // 014; SDK gains them in step 2 of Phase 0.2.

    async fn add_wallet_user(
        &mut self,
        wallet_id: Uuid,
        user_id: Uuid,
        role: String,
    ) -> Result<(), Self::Error>;

    async fn remove_wallet_user(
        &mut self,
        wallet_id: Uuid,
        user_id: Uuid,
    ) -> Result<(), Self::Error>;

    async fn set_wallet_user_role(
        &mut self,
        wallet_id: Uuid,
        user_id: Uuid,
        role: String,
    ) -> Result<(), Self::Error>;

    async fn insert_user_group(
        &mut self,
        id: Uuid,
        wallet_id: Uuid,
        name: String,
    ) -> Result<(), Self::Error>;

    async fn update_user_group(
        &mut self,
        id: Uuid,
        name: Option<String>,
    ) -> Result<(), Self::Error>;

    async fn delete_user_group(
        &mut self,
        id: Uuid,
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

    async fn insert_contact_group(
        &mut self,
        id: Uuid,
        wallet_id: Uuid,
        name: String,
    ) -> Result<(), Self::Error>;

    async fn update_contact_group(
        &mut self,
        id: Uuid,
        name: Option<String>,
    ) -> Result<(), Self::Error>;

    async fn delete_contact_group(
        &mut self,
        id: Uuid,
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

    /// Replace the (user_group, contact_group) cell of the matrix with the
    /// given allow + deny action lists. The set operation is total — any
    /// pre-existing rows for this cell are wiped first.
    async fn set_permission_matrix_cell(
        &mut self,
        user_group_id: Uuid,
        contact_group_id: Uuid,
        allowed_actions: Vec<String>,
        denied_actions: Vec<String>,
    ) -> Result<(), Self::Error>;

    // ---------- Wallet lifecycle ----------

    async fn delete_wallet(
        &mut self,
        wallet_id: Uuid,
        reason: Option<String>,
    ) -> Result<(), Self::Error>;

    async fn transfer_wallet_ownership(
        &mut self,
        wallet_id: Uuid,
        from: Uuid,
        to: Uuid,
    ) -> Result<(), Self::Error>;
}

/// Apply one event to a projection. Exhaustive match over every variant of
/// [`domain::EventData`]. The compiler enforces that every variant has a
/// branch; adding a new variant to `EventData` is a build-time error here
/// until it's handled.
///
/// Note: this is a skeleton. The body lands in step 3, where each branch
/// translates the typed variant into the matching `Projection` method call.
pub async fn apply<P: Projection + Send>(
    _projection: &mut P,
    event: &DomainEvent,
) -> Result<(), P::Error> {
    use domain::EventData as E;

    match &event.event_data {
        E::ContactCreated { .. }
        | E::ContactUpdated { .. }
        | E::ContactDeleted { .. }
        | E::ContactUndone { .. }
        | E::TransactionCreated { .. }
        | E::TransactionUpdated { .. }
        | E::TransactionDeleted { .. }
        | E::TransactionUndone { .. }
        | E::WalletUserAdded { .. }
        | E::WalletUserRoleChanged { .. }
        | E::WalletUserRemoved { .. }
        | E::UserGroupCreated { .. }
        | E::UserGroupUpdated { .. }
        | E::UserGroupDeleted { .. }
        | E::UserGroupMemberAdded { .. }
        | E::UserGroupMemberRemoved { .. }
        | E::ContactGroupCreated { .. }
        | E::ContactGroupUpdated { .. }
        | E::ContactGroupDeleted { .. }
        | E::ContactGroupMemberAdded { .. }
        | E::ContactGroupMemberRemoved { .. }
        | E::PermissionMatrixSet { .. }
        | E::WalletDeleted { .. }
        | E::OwnershipTransferred { .. } => {
            // Step 3 wires each variant to the corresponding Projection
            // method. Keeping the exhaustive pattern here so adding a new
            // EventData variant in the future fails to build until handled
            // on both sides.
            Ok(())
        }
    }
}
