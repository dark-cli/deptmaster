//! SQLite storage: config, events, projection state.
//! Thread-local so each thread (e.g. each integration test) has its own DB; Flutter uses a single thread.

use crate::models::{Contact, Transaction};
use crate::rust_log;
use rusqlite::{Connection, params};
use std::cell::RefCell;
use std::path::Path;

thread_local! {
    static DB: RefCell<Option<Connection>> = RefCell::new(None);
}

/// True if the current thread has called init() successfully.
pub fn is_ready() -> bool {
    DB.with(|cell| cell.borrow().is_some())
}

pub fn init(path: &str) -> Result<(), String> {
    let path_obj = Path::new(path);
    std::fs::create_dir_all(path_obj).map_err(|e| e.to_string())?;
    let db_path = path_obj.join("debitum.db");
    rust_log!("[debitum_rs] storage::init path={:?} db={:?}", path, db_path);
    let conn = Connection::open(&db_path).map_err(|e| e.to_string())?;
    create_tables(&conn)?;
    DB.with(|cell| *cell.borrow_mut() = Some(conn));
    rust_log!("[debitum_rs] storage::init OK");
    Ok(())
}

fn create_tables(conn: &Connection) -> Result<(), String> {
    conn.execute_batch(
        r#"
        CREATE TABLE IF NOT EXISTS config (key TEXT PRIMARY KEY, value TEXT);
        CREATE TABLE IF NOT EXISTS events (
            id TEXT PRIMARY KEY,
            wallet_id TEXT NOT NULL,
            aggregate_type TEXT NOT NULL,
            aggregate_id TEXT NOT NULL,
            event_type TEXT NOT NULL,
            event_data TEXT NOT NULL,
            timestamp TEXT NOT NULL,
            version INTEGER NOT NULL DEFAULT 1,
            synced INTEGER NOT NULL DEFAULT 0
        );
        CREATE INDEX IF NOT EXISTS idx_events_wallet ON events(wallet_id);
        CREATE INDEX IF NOT EXISTS idx_events_synced ON events(synced);
        CREATE TABLE IF NOT EXISTS state (
            wallet_id TEXT PRIMARY KEY,
            contacts_json TEXT NOT NULL,
            transactions_json TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );
        "#,
    )
    .map_err(|e| e.to_string())?;
    Ok(())
}

fn with_db<F, T>(f: F) -> Result<T, String>
where
    F: FnOnce(&Connection) -> Result<T, rusqlite::Error>,
{
    DB.with(|cell| {
        let borrow = cell.borrow();
        let conn = borrow.as_ref().ok_or("Storage not initialized")?;
        f(conn).map_err(|e| e.to_string())
    })
}

// Config
pub fn config_get(key: &str) -> Result<Option<String>, String> {
    with_db(|conn| {
        let mut stmt = conn.prepare("SELECT value FROM config WHERE key = ?1")?;
        let mut rows = stmt.query(params![key])?;
        if let Some(row) = rows.next()? {
            return Ok(Some(row.get(0)?));
        }
        Ok(None)
    })
}

pub fn config_set(key: &str, value: &str) -> Result<(), String> {
    with_db(|conn| {
        conn.execute(
            "INSERT INTO config (key, value) VALUES (?1, ?2) ON CONFLICT(key) DO UPDATE SET value = ?2",
            params![key, value],
        )?;
        Ok(())
    })
}

pub fn config_remove(key: &str) -> Result<(), String> {
    with_db(|conn| {
        conn.execute("DELETE FROM config WHERE key = ?1", params![key])?;
        Ok(())
    })
}

pub fn clear_all() -> Result<(), String> {
    with_db(|conn| {
        conn.execute_batch(
            r#"
            DELETE FROM events;
            DELETE FROM state;
            DELETE FROM config;
            "#,
        )?;
        Ok(())
    })
}

/// Clear all local data for a specific wallet (events, state, last_sync_timestamp).
/// Use when read permissions are revoked so client can resync from server.
pub fn clear_wallet(wallet_id: &str) -> Result<(), String> {
    let key = format!("last_sync_timestamp_{}", wallet_id);
    with_db(|conn| {
        conn.execute("DELETE FROM events WHERE wallet_id = ?1", params![wallet_id])?;
        conn.execute("DELETE FROM state WHERE wallet_id = ?1", params![wallet_id])?;
        conn.execute("DELETE FROM config WHERE key = ?1", params![key])?;
        Ok(())
    })
}

// Events
#[derive(Clone, Debug)]
pub struct StoredEvent {
    pub id: String,
    pub wallet_id: String,
    pub aggregate_type: String,
    pub aggregate_id: String,
    pub event_type: String,
    pub event_data: String,
    pub timestamp: String,
    pub version: i32,
    pub synced: bool,
}

pub fn events_insert(e: &StoredEvent) -> Result<(), String> {
    rust_log!(
        "[debitum_rs] storage::events_insert wallet_id={} aggregate={}/{} event_type={} id={}",
        e.wallet_id, e.aggregate_type, e.aggregate_id, e.event_type, e.id
    );
    with_db(|conn| {
        conn.execute(
            r#"
            INSERT OR IGNORE INTO events (id, wallet_id, aggregate_type, aggregate_id, event_type, event_data, timestamp, version, synced)
            VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)
            "#,
            params![e.id, e.wallet_id, e.aggregate_type, e.aggregate_id, e.event_type, e.event_data, e.timestamp, e.version, if e.synced { 1 } else { 0 }],
        )?;
        Ok(())
    })
}

/// Update event_data JSON for an event (e.g. to add total_debt after rebuild).
pub fn events_update_event_data(event_id: &str, event_data_json: &str) -> Result<(), String> {
    with_db(|conn| {
        conn.execute("UPDATE events SET event_data = ?1 WHERE id = ?2", params![event_data_json, event_id])?;
        Ok(())
    })
}

pub fn events_get_all(wallet_id: &str) -> Result<Vec<StoredEvent>, String> {
    let events = with_db(|conn| {
        let mut stmt = conn.prepare(
            "SELECT id, wallet_id, aggregate_type, aggregate_id, event_type, event_data, timestamp, version, synced FROM events WHERE wallet_id = ?1 ORDER BY timestamp ASC",
        )?;
        let rows = stmt.query_map(params![wallet_id], |row| {
            Ok(StoredEvent {
                id: row.get(0)?,
                wallet_id: row.get(1)?,
                aggregate_type: row.get(2)?,
                aggregate_id: row.get(3)?,
                event_type: row.get(4)?,
                event_data: row.get(5)?,
                timestamp: row.get(6)?,
                version: row.get(7)?,
                synced: row.get::<_, i32>(8)? != 0,
            })
        })?;
        rows.collect::<Result<Vec<_>, _>>()
    })?;
    rust_log!("[debitum_rs] storage::events_get_all wallet_id={} -> {} events", wallet_id, events.len());
    if events.is_empty() {
        if let Ok(()) = with_db(|conn| {
            let mut stmt = conn.prepare("SELECT wallet_id, COUNT(*) FROM events GROUP BY wallet_id")?;
            let rows = stmt.query_map([], |row| Ok((row.get::<_, String>(0)?, row.get::<_, i64>(1)?)))?;
            for row in rows {
                let (w, c) = row?;
                rust_log!("[debitum_rs]   events in DB: wallet_id={} count={}", w, c);
            }
            Ok(())
        }) {}
    }
    Ok(events)
}

pub fn events_get_unsynced(wallet_id: &str) -> Result<Vec<StoredEvent>, String> {
    with_db(|conn| {
        let mut stmt = conn.prepare(
            "SELECT id, wallet_id, aggregate_type, aggregate_id, event_type, event_data, timestamp, version, synced FROM events WHERE wallet_id = ?1 AND synced = 0 ORDER BY timestamp ASC",
        )?;
        let rows = stmt.query_map(params![wallet_id], |row| {
            Ok(StoredEvent {
                id: row.get(0)?,
                wallet_id: row.get(1)?,
                aggregate_type: row.get(2)?,
                aggregate_id: row.get(3)?,
                event_type: row.get(4)?,
                event_data: row.get(5)?,
                timestamp: row.get(6)?,
                version: row.get(7)?,
                synced: false,
            })
        })?;
        rows.collect::<Result<Vec<_>, _>>()
    })
}

pub fn events_mark_synced(ids: &[String]) -> Result<(), String> {
    if ids.is_empty() {
        return Ok(());
    }
    with_db(|conn| {
        for id in ids {
            conn.execute("UPDATE events SET synced = 1 WHERE id = ?1", params![id])?;
        }
        Ok(())
    })
}

/// Delete all unsynced (pending) events for a wallet.
pub fn events_delete_unsynced(wallet_id: &str) -> Result<u64, String> {
    with_db(|conn| {
        let affected = conn.execute(
            "DELETE FROM events WHERE wallet_id = ?1 AND synced = 0",
            params![wallet_id],
        )?;
        Ok(affected as u64)
    })
}

/// Delete all events for a wallet. Used on full pull so local state is replaced by server response (permission-filtered).
pub fn events_delete_all_for_wallet(wallet_id: &str) -> Result<(), String> {
    with_db(|conn| {
        conn.execute("DELETE FROM events WHERE wallet_id = ?1", params![wallet_id])?;
        Ok(())
    })
}

pub fn events_count(wallet_id: &str) -> Result<i64, String> {
    with_db(|conn| {
        let count: i64 = conn.query_row(
            "SELECT COUNT(*) FROM events WHERE wallet_id = ?1",
            params![wallet_id],
            |row| row.get(0),
        )?;
        Ok(count)
    })
}

/// Get all events for an aggregate, sorted by timestamp ascending (oldest first).
pub fn events_get_for_aggregate(
    wallet_id: &str,
    aggregate_type: &str,
    aggregate_id: &str,
) -> Result<Vec<StoredEvent>, String> {
    with_db(|conn| {
        let mut stmt = conn.prepare(
            "SELECT id, wallet_id, aggregate_type, aggregate_id, event_type, event_data, timestamp, version, synced FROM events WHERE wallet_id = ?1 AND aggregate_type = ?2 AND aggregate_id = ?3 ORDER BY timestamp ASC",
        )?;
        let rows = stmt.query_map(params![wallet_id, aggregate_type, aggregate_id], |row| {
            Ok(StoredEvent {
                id: row.get(0)?,
                wallet_id: row.get(1)?,
                aggregate_type: row.get(2)?,
                aggregate_id: row.get(3)?,
                event_type: row.get(4)?,
                event_data: row.get(5)?,
                timestamp: row.get(6)?,
                version: row.get(7)?,
                synced: row.get::<_, i32>(8)? != 0,
            })
        })?;
        rows.collect::<Result<Vec<_>, _>>()
    })
}

// State (projection cache)
pub fn state_save(wallet_id: &str, contacts: &[Contact], transactions: &[Transaction]) -> Result<(), String> {
    let contacts_json = serde_json::to_string(contacts).map_err(|e| e.to_string())?;
    let transactions_json = serde_json::to_string(transactions).map_err(|e| e.to_string())?;
    let updated_at = chrono::Utc::now().to_rfc3339();
    with_db(|conn| {
        conn.execute(
            r#"
            INSERT INTO state (wallet_id, contacts_json, transactions_json, updated_at) VALUES (?1, ?2, ?3, ?4)
            ON CONFLICT(wallet_id) DO UPDATE SET contacts_json = ?2, transactions_json = ?3, updated_at = ?4
            "#,
            params![wallet_id, contacts_json, transactions_json, updated_at],
        )?;
        Ok(())
    })
}

pub fn state_load(wallet_id: &str) -> Result<Option<(Vec<Contact>, Vec<Transaction>)>, String> {
    let pair = with_db(|conn| {
        let mut stmt = conn.prepare("SELECT contacts_json, transactions_json FROM state WHERE wallet_id = ?1")?;
        let mut rows = stmt.query(params![wallet_id])?;
        if let Some(row) = rows.next()? {
            let contacts_json: String = row.get(0)?;
            let transactions_json: String = row.get(1)?;
            return Ok(Some((contacts_json, transactions_json)));
        }
        Ok(None)
    })?;
    match pair {
        Some((contacts_json, transactions_json)) => {
            let contacts: Vec<Contact> = serde_json::from_str(&contacts_json).map_err(|e| e.to_string())?;
            let transactions: Vec<Transaction> = serde_json::from_str(&transactions_json).map_err(|e| e.to_string())?;
            Ok(Some((contacts, transactions)))
        }
        None => Ok(None),
    }
}
