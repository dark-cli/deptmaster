//! Shared permission-resolution logic.
//!
//! Both the server and the SDK need to answer:
//! - "What actions can user U perform on resource R?"  ([`resolve_actions`])
//! - "Which contacts can user U perform action A on?"  ([`permitted_contacts_for_action`])
//!
//! The rules behind both questions are identical and live HERE, in pure
//! Rust. Storage backends (server's Postgres, SDK's SQLite) implement the
//! [`PermissionStore`] trait, which exposes only low-level reads:
//! "which user_groups is this user in", "which matrix rows do these
//! user_groups have", "is this contact in this contact_group", etc.
//!
//! ## The rules (encoded by [`resolve_actions`])
//!
//! - Wallet owners get every action automatically.
//! - For non-owners: collect every matrix row from every user_group the
//!   user belongs to (including the implicit `all_users` system group).
//! - A row is APPLICABLE to a query if:
//!   - The row's contact_group is `all_contacts`, OR
//!   - The query is a wildcard (`Resource::AllContacts`), OR
//!   - The row's contact_group contains the specific contact named in the
//!     query.
//! - Among applicable rows: a row with `is_deny = false` adds its action
//!   to the `allowed` set; `is_deny = true` adds to `denied`.
//! - Final = `allowed \ denied` (deny wins).
//!
//! ## Companion crate
//!
//! `applier` is the parallel crate for event-application rules. `applier`
//! says what events DO; `resolver` says what users CAN DO. Together they
//! contain every rule of the permission model in pure Rust, with no SQL
//! and no platform-specific code.

use async_trait::async_trait;
use std::collections::HashSet;
use uuid::Uuid;

use domain::{Action, PermissionContext, Resource};

/// One row of the permission matrix from a user's perspective. The
/// `contact_group_name` is included so callers can detect the system
/// `all_contacts` group without an extra round-trip; everything else is
/// raw matrix data.
#[derive(Debug, Clone)]
pub struct MatrixRow {
    pub contact_group_id: Uuid,
    pub contact_group_name: String,
    pub action: String,
    pub is_deny: bool,
}

/// Storage backend for permission resolution. Methods are low-level: each
/// one corresponds to a single SQL query (or its in-memory equivalent).
/// The resolver functions ([`resolve_actions`], [`permitted_contacts_for_action`])
/// compose them in pure Rust.
#[async_trait]
pub trait PermissionStore {
    type Error: std::fmt::Debug + Send;

    /// True iff `user_id` is recorded as an owner of `wallet_id`. Owners
    /// short-circuit to "all actions allowed."
    async fn is_wallet_owner(
        &self,
        wallet_id: Uuid,
        user_id: Uuid,
    ) -> Result<bool, Self::Error>;

    /// IDs of every user_group the user is a member of in this wallet,
    /// INCLUDING the implicit `all_users` system group (every wallet
    /// member is in `all_users` regardless of explicit memberships).
    async fn user_group_ids_for_user(
        &self,
        wallet_id: Uuid,
        user_id: Uuid,
    ) -> Result<Vec<Uuid>, Self::Error>;

    /// All matrix rows where the user_group_id is in the given set, for
    /// the given wallet. Each row carries its contact_group name so the
    /// caller can detect the system `all_contacts` group inline.
    async fn matrix_rows_for_user_groups(
        &self,
        wallet_id: Uuid,
        user_group_ids: &[Uuid],
    ) -> Result<Vec<MatrixRow>, Self::Error>;

    /// IDs of every contact_group the contact is a member of (explicit
    /// memberships via `contact_group_members`; the implicit `all_contacts`
    /// membership is NOT included here — callers handle it via the
    /// `contact_group_name` field on [`MatrixRow`]).
    async fn contact_group_ids_for_contact(
        &self,
        contact_id: Uuid,
    ) -> Result<HashSet<Uuid>, Self::Error>;

    /// IDs of every contact in the wallet (ignoring `is_deleted` — this
    /// query feeds `permitted_contacts_for_action` whose callers need to
    /// see DELETE events for contacts the user had access to).
    async fn all_contact_ids_in_wallet(
        &self,
        wallet_id: Uuid,
    ) -> Result<HashSet<Uuid>, Self::Error>;

    /// IDs of every contact in the given contact_group via
    /// `contact_group_members`. Empty if the group is empty or doesn't exist.
    async fn contact_ids_in_group(
        &self,
        contact_group_id: Uuid,
    ) -> Result<HashSet<Uuid>, Self::Error>;
}

/// Resolve every action the user is allowed to perform on the given
/// resource. Pure Rust over the [`PermissionStore`] reads.
///
/// Owners short-circuit to [`Action::all`]. Non-owners go through the
/// 3-state matrix: a row applies to the query if its contact_group covers
/// the resource (see module-level docs); among applicable rows, deny wins.
pub async fn resolve_actions<S: PermissionStore + Sync>(
    store: &S,
    ctx: &PermissionContext,
    resource: &Resource,
) -> Result<HashSet<Action>, S::Error> {
    if store
        .is_wallet_owner(ctx.wallet_id, ctx.user_id)
        .await?
    {
        return Ok(Action::all().iter().copied().collect());
    }

    let ug_ids = store
        .user_group_ids_for_user(ctx.wallet_id, ctx.user_id)
        .await?;
    if ug_ids.is_empty() {
        return Ok(HashSet::new());
    }
    let rows = store
        .matrix_rows_for_user_groups(ctx.wallet_id, &ug_ids)
        .await?;

    // Determine which contact_groups apply to this resource. The match
    // here encodes the wildcard rules from the module-level docs:
    //   - Specific contact: applicable cg = the cgs that contain it,
    //     plus the system 'all_contacts' (which always covers everything).
    //   - AllContacts (wildcard query): every cg applies.
    //   - Anything else (Wallet, Transaction, etc.): only 'all_contacts'
    //     applies. The matrix model only scopes by contact-group; for
    //     non-contact resources, only the wallet-wide all_contacts row
    //     can grant.
    let scope = applicable_scope_for(store, resource).await?;

    let mut allowed = HashSet::new();
    let mut denied = HashSet::new();
    for row in rows {
        if !scope.row_applies(&row) {
            continue;
        }
        if let Some(action) = Action::from_str(&row.action) {
            if row.is_deny {
                denied.insert(action);
            } else {
                allowed.insert(action);
            }
        }
    }
    Ok(allowed.difference(&denied).copied().collect())
}

/// Return the set of contact IDs the user has permission to perform
/// `action_name` on. Used by the server's `filter_readable_events` to
/// gate which events a user sees; could also drive SDK UX ("which
/// contacts can I delete?").
///
/// Same 3-state allow/deny resolution as [`resolve_actions`], but the
/// output is contacts rather than actions.
pub async fn permitted_contacts_for_action<S: PermissionStore + Sync>(
    store: &S,
    ctx: &PermissionContext,
    action_name: &str,
) -> Result<HashSet<Uuid>, S::Error> {
    let ug_ids = store
        .user_group_ids_for_user(ctx.wallet_id, ctx.user_id)
        .await?;
    if ug_ids.is_empty() {
        return Ok(HashSet::new());
    }
    let rows = store
        .matrix_rows_for_user_groups(ctx.wallet_id, &ug_ids)
        .await?;

    let mut allowed: HashSet<Uuid> = HashSet::new();
    let mut denied: HashSet<Uuid> = HashSet::new();

    for row in rows {
        if row.action != action_name {
            continue;
        }
        let contacts_in_row_scope = if row.contact_group_name == "all_contacts" {
            store.all_contact_ids_in_wallet(ctx.wallet_id).await?
        } else {
            store.contact_ids_in_group(row.contact_group_id).await?
        };
        let target = if row.is_deny { &mut denied } else { &mut allowed };
        target.extend(contacts_in_row_scope);
    }

    Ok(allowed.difference(&denied).copied().collect())
}

// ---------- internal helpers ----------

enum Scope {
    /// AllContacts wildcard query — every matrix row applies.
    AnyContactGroup,
    /// Non-contact resource — only the system `all_contacts` row applies.
    OnlyAllContacts,
    /// Specific contact — applicable if cg is `all_contacts` OR contains the contact.
    SpecificContactOrAllContacts(HashSet<Uuid>),
}

impl Scope {
    fn row_applies(&self, row: &MatrixRow) -> bool {
        let is_all_contacts = row.contact_group_name == "all_contacts";
        match self {
            Scope::AnyContactGroup => true,
            Scope::OnlyAllContacts => is_all_contacts,
            Scope::SpecificContactOrAllContacts(cgs) => {
                is_all_contacts || cgs.contains(&row.contact_group_id)
            }
        }
    }
}

async fn applicable_scope_for<S: PermissionStore + Sync>(
    store: &S,
    resource: &Resource,
) -> Result<Scope, S::Error> {
    match resource {
        Resource::AllContacts => Ok(Scope::AnyContactGroup),
        Resource::Contact(id) => {
            let cgs = store.contact_group_ids_for_contact(*id).await?;
            Ok(Scope::SpecificContactOrAllContacts(cgs))
        }
        // Wallet, Transaction, ContactGroup, UserGroup, AllTransactions,
        // AllUserGroups all fall through to "only all_contacts row matters."
        // The matrix model scopes permissions by contact-group only.
        _ => Ok(Scope::OnlyAllContacts),
    }
}
