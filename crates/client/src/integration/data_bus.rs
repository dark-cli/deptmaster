//! Reactive data-change bus.
//!
//! Single FFI export ([`data_change_stream`]) that Dart subscribes to
//! once at startup. Rust pushes a [`DataChangeEvent`] into it whenever
//! a projection table changes — local CRUD, sync pull, undo, etc.
//! Dart-side Riverpod providers listen to the stream and invalidate
//! themselves when their relevant [`DataChangeKind`] arrives.
//!
//! The emit side is `pub(crate)` so only this crate can fire events;
//! the subscribe side is `pub fn` so FRB exposes it to Dart.

use crate::frb_generated::StreamSink;
use flutter_rust_bridge::frb;
use once_cell::sync::Lazy;
use std::sync::Mutex;

/// Categories of data that providers can listen for. New variants are
/// safe to add — Dart providers ignore kinds they don't care about.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum DataChangeKind {
    /// Contacts changed in the given wallet.
    Contacts,
    /// Transactions changed in the given wallet.
    Transactions,
    /// Permission matrix / groups / wallet ownership changed.
    Permissions,
    /// Wallet membership (users in / out / role change) changed.
    WalletMembership,
    /// Wallet list (created / deleted / joined) changed.
    Wallets,
    /// The authenticated session changed (login or logout). Dart-side
    /// providers MUST invalidate their cached state on this kind:
    /// the local SQLite was wiped, so anything cached from the prior
    /// user is now stale and must not bleed across the user switch.
    /// `wallet_id` is always `None` for this kind.
    Session,
}

/// One data-change notification.
#[derive(Debug, Clone)]
pub struct DataChangeEvent {
    /// Wallet the change applies to. `None` for cross-wallet changes
    /// like wallet creation/deletion.
    pub wallet_id: Option<String>,
    pub kind: DataChangeKind,
}

static DATA_SINK: Lazy<Mutex<Option<StreamSink<DataChangeEvent>>>> = Lazy::new(|| Mutex::new(None));

/// Subscribe to data-change events. Dart calls this once at startup
/// and listens to the returned Stream for the app's lifetime. If
/// called more than once the previous sink is replaced — old
/// subscribers stop receiving events.
#[frb]
pub fn data_change_stream(sink: StreamSink<DataChangeEvent>) -> Result<(), String> {
    *DATA_SINK.lock().unwrap() = Some(sink);
    Ok(())
}

/// Push one event into the data-change stream. No-op if Dart hasn't
/// subscribed yet (legitimate during early startup) or if the send
/// fails (Dart dropped the Stream).
pub(crate) fn emit(kind: DataChangeKind, wallet_id: Option<String>) {
    if let Some(sink) = DATA_SINK.lock().unwrap().as_ref() {
        let _ = sink.add(DataChangeEvent { wallet_id, kind });
    }
}

/// Map an [`domain::AggregateType`] to the corresponding
/// [`DataChangeKind`]. Exhaustive — adding an `AggregateType` variant
/// fails compile here until handled.
pub(crate) fn kind_from_aggregate(aggregate: domain::AggregateType) -> DataChangeKind {
    match aggregate {
        domain::AggregateType::Contact => DataChangeKind::Contacts,
        domain::AggregateType::Transaction => DataChangeKind::Transactions,
        domain::AggregateType::Permission => DataChangeKind::Permissions,
    }
}
