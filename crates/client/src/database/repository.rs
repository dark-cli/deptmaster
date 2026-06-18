//! Database repository: SQLite queries and mutations with typed error handling.

use crate::database::models::StoredEvent;
use crate::types::error::ClientError;
use crate::types::models::{Contact, Transaction};
use crate::rust_log;
use once_cell::sync::Lazy;
use rusqlite::{params, Connection};
use std::path::Path;
use std::sync::Mutex;

struct StorageState {
    path: String,
    conn: Connection,
}

static STORAGE: Lazy<Mutex<Option<StorageState>>> = Lazy::new(|| Mutex::new(None));

/// True if init() has been called successfully (process-wide).
pub fn is_ready() -> bool {
    STORAGE.lock().unwrap().is_some()
}

pub fn init(path: &str) -> Result<(), ClientError> {
    let path_obj = Path::new(path);
    let db_path = path_obj.join("debitum.db");
    let path_key = db_path.to_string_lossy().to_string();
    {
        let guard = STORAGE.lock().unwrap();
        if let Some(ref s) = *guard {
            if s.path == path_key {
                return Ok(());
            }
        }
    }
    std::fs::create_dir_all(path_obj).map_err(|e| ClientError::Storage(e.to_string()))?;
    rust_log!(
        "[debitum_rs] database::storage::init path={:?} db={:?}",
        path,
        db_path
    );
    let conn = Connection::open(&db_path).map_err(|e| ClientError::Storage(e.to_string()))?;
    create_tables(&conn)?;
    {
        let mut guard = STORAGE.lock().unwrap();
        *guard = Some(StorageState {
            path: path_key,
            conn,
        });
    }
    rust_log!("[debitum_rs] database::storage::init OK");
    Ok(())
}

fn create_tables(conn: &Connection) -> Result<(), ClientError> {
    conn.execute_batch("PRAGMA foreign_keys = ON;")
        .map_err(|e| ClientError::Storage(e.to_string()))?;

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

        CREATE TABLE IF NOT EXISTS user_groups (
            id TEXT PRIMARY KEY,
            wallet_id TEXT NOT NULL,
            name TEXT NOT NULL,
            is_system INTEGER NOT NULL DEFAULT 0,
            UNIQUE(wallet_id, name)
        );
        CREATE INDEX IF NOT EXISTS idx_user_groups_wallet ON user_groups(wallet_id);

        CREATE TABLE IF NOT EXISTS user_group_members (
            user_id TEXT NOT NULL,
            user_group_id TEXT NOT NULL REFERENCES user_groups(id) ON DELETE CASCADE,
            PRIMARY KEY (user_id, user_group_id)
        );
        CREATE INDEX IF NOT EXISTS idx_user_group_members_group ON user_group_members(user_group_id);

        CREATE TABLE IF NOT EXISTS contact_groups (
            id TEXT PRIMARY KEY,
            wallet_id TEXT NOT NULL,
            name TEXT NOT NULL,
            is_system INTEGER NOT NULL DEFAULT 0,
            UNIQUE(wallet_id, name)
        );
        CREATE INDEX IF NOT EXISTS idx_contact_groups_wallet ON contact_groups(wallet_id);

        CREATE TABLE IF NOT EXISTS contact_group_members (
            contact_id TEXT NOT NULL,
            contact_group_id TEXT NOT NULL REFERENCES contact_groups(id) ON DELETE CASCADE,
            PRIMARY KEY (contact_id, contact_group_id)
        );
        CREATE INDEX IF NOT EXISTS idx_contact_group_members_group ON contact_group_members(contact_group_id);

        CREATE TABLE IF NOT EXISTS group_permission_matrix (
            user_group_id TEXT NOT NULL REFERENCES user_groups(id) ON DELETE CASCADE,
            contact_group_id TEXT NOT NULL REFERENCES contact_groups(id) ON DELETE CASCADE,
            action TEXT NOT NULL,
            is_deny INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY (user_group_id, contact_group_id, action, is_deny)
        );
        CREATE INDEX IF NOT EXISTS idx_group_permission_matrix_scope ON group_permission_matrix(contact_group_id);

        CREATE TABLE IF NOT EXISTS wallet_users (
            wallet_id TEXT NOT NULL,
            user_id TEXT NOT NULL,
            role TEXT NOT NULL,
            PRIMARY KEY (wallet_id, user_id)
        );

        CREATE TABLE IF NOT EXISTS wallet_owners (
            wallet_id TEXT NOT NULL,
            user_id TEXT NOT NULL,
            PRIMARY KEY (wallet_id, user_id)
        );
        CREATE INDEX IF NOT EXISTS idx_wallet_owners_user ON wallet_owners(user_id);

        CREATE TABLE IF NOT EXISTS contacts (
            id TEXT PRIMARY KEY,
            wallet_id TEXT NOT NULL,
            name TEXT NOT NULL,
            username TEXT,
            phone TEXT,
            email TEXT,
            notes TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            is_synced INTEGER NOT NULL DEFAULT 1,
            is_deleted INTEGER NOT NULL DEFAULT 0
        );
        CREATE INDEX IF NOT EXISTS idx_contacts_wallet ON contacts(wallet_id) WHERE is_deleted = 0;

        CREATE TABLE IF NOT EXISTS transactions (
            id TEXT PRIMARY KEY,
            wallet_id TEXT NOT NULL,
            contact_id TEXT NOT NULL,
            type TEXT NOT NULL DEFAULT 'money',
            direction TEXT NOT NULL DEFAULT 'owed',
            amount INTEGER NOT NULL DEFAULT 0,
            currency TEXT NOT NULL DEFAULT 'IQD',
            description TEXT,
            transaction_date TEXT NOT NULL,
            due_date TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            is_synced INTEGER NOT NULL DEFAULT 1,
            is_deleted INTEGER NOT NULL DEFAULT 0
        );
        CREATE INDEX IF NOT EXISTS idx_transactions_wallet ON transactions(wallet_id) WHERE is_deleted = 0;
        CREATE INDEX IF NOT EXISTS idx_transactions_contact ON transactions(contact_id) WHERE is_deleted = 0;

        CREATE TABLE IF NOT EXISTS projection_snapshots (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            wallet_id TEXT NOT NULL,
            snapshot_index INTEGER NOT NULL,
            last_event_id TEXT NOT NULL,
            event_count INTEGER NOT NULL,
            contacts_snapshot TEXT NOT NULL,
            transactions_snapshot TEXT NOT NULL,
            created_at TEXT NOT NULL,
            UNIQUE(wallet_id, snapshot_index)
        );
        CREATE INDEX IF NOT EXISTS idx_projection_snapshots_wallet_index
            ON projection_snapshots(wallet_id, snapshot_index DESC);
        CREATE INDEX IF NOT EXISTS idx_projection_snapshots_event_id
            ON projection_snapshots(last_event_id);
        "#,
    )
    .map_err(|e| ClientError::Storage(e.to_string()))?;
    Ok(())
}

pub fn with_db<F, T>(f: F) -> Result<T, ClientError>
where
    F: FnOnce(&Connection) -> Result<T, rusqlite::Error>,
{
    let guard = STORAGE.lock().unwrap();
    let state = guard
        .as_ref()
        .ok_or(ClientError::Storage("Storage not initialized".to_string()))?;
    f(&state.conn).map_err(|e| ClientError::Storage(e.to_string()))
}

// Config
pub fn config_get(key: &str) -> Result<Option<String>, ClientError> {
    with_db(|conn| {
        let mut stmt = conn.prepare("SELECT value FROM config WHERE key = ?1")?;
        let mut rows = stmt.query(params![key])?;
        if let Some(row) = rows.next()? {
            return Ok(Some(row.get(0)?));
        }
        Ok(None)
    })
}

pub fn config_set(key: &str, value: &str) -> Result<(), ClientError> {
    with_db(|conn| {
        conn.execute(
            "INSERT INTO config (key, value) VALUES (?1, ?2) ON CONFLICT(key) DO UPDATE SET value = ?2",
            params![key, value],
        )?;
        Ok(())
    })
}

pub fn config_remove(key: &str) -> Result<(), ClientError> {
    with_db(|conn| {
        conn.execute("DELETE FROM config WHERE key = ?1", params![key])?;
        Ok(())
    })
}

pub fn clear_all() -> Result<(), ClientError> {
    with_db(|conn| {
        conn.execute_batch(
            r#"
            DELETE FROM events;
            DELETE FROM contacts;
            DELETE FROM transactions;
            DELETE FROM wallet_users;
            DELETE FROM wallet_owners;
            DELETE FROM user_groups;
            DELETE FROM contact_groups;
            DELETE FROM projection_snapshots;
            DELETE FROM config;
            "#,
        )?;
        Ok(())
    })
}

pub fn clear_wallet(wallet_id: &str) -> Result<(), ClientError> {
    let last_sync_key = format!("last_sync_timestamp_{}", wallet_id);
    let server_hash_key = format!("server_hash_{}", wallet_id);
    with_db(|conn| {
        conn.execute(
            "DELETE FROM events WHERE wallet_id = ?1",
            params![wallet_id],
        )?;
        conn.execute(
            "DELETE FROM contacts WHERE wallet_id = ?1",
            params![wallet_id],
        )?;
        conn.execute(
            "DELETE FROM transactions WHERE wallet_id = ?1",
            params![wallet_id],
        )?;
        conn.execute(
            "DELETE FROM wallet_users WHERE wallet_id = ?1",
            params![wallet_id],
        )?;
        conn.execute(
            "DELETE FROM wallet_owners WHERE wallet_id = ?1",
            params![wallet_id],
        )?;
        conn.execute(
            "DELETE FROM user_groups WHERE wallet_id = ?1",
            params![wallet_id],
        )?;
        conn.execute(
            "DELETE FROM contact_groups WHERE wallet_id = ?1",
            params![wallet_id],
        )?;
        conn.execute(
            "DELETE FROM projection_snapshots WHERE wallet_id = ?1",
            params![wallet_id],
        )?;
        conn.execute("DELETE FROM config WHERE key = ?1", params![last_sync_key])?;
        conn.execute(
            "DELETE FROM config WHERE key = ?1",
            params![server_hash_key],
        )?;
        Ok(())
    })
}

// Events
pub fn events_insert(e: &StoredEvent) -> Result<(), ClientError> {
    rust_log!(
        "[debitum_rs] database::storage::events_insert wallet_id={} aggregate={}/{} event_type={} id={}",
        e.wallet_id,
        e.aggregate_type,
        e.aggregate_id,
        e.event_type,
        e.id
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

pub fn events_update_event_data(event_id: &str, event_data_json: &str) -> Result<(), ClientError> {
    with_db(|conn| {
        conn.execute(
            "UPDATE events SET event_data = ?1 WHERE id = ?2",
            params![event_data_json, event_id],
        )?;
        Ok(())
    })
}

pub fn events_get_all(wallet_id: &str) -> Result<Vec<StoredEvent>, ClientError> {
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
    rust_log!(
        "[debitum_rs] database::storage::events_get_all wallet_id={} -> {} events",
        wallet_id,
        events.len()
    );
    if events.is_empty() {
        if let Ok(()) = with_db(|conn| {
            let mut stmt =
                conn.prepare("SELECT wallet_id, COUNT(*) FROM events GROUP BY wallet_id")?;
            let rows = stmt.query_map([], |row| {
                Ok((row.get::<_, String>(0)?, row.get::<_, i64>(1)?))
            })?;
            for row in rows {
                let (w, c) = row?;
                rust_log!("[debitum_rs]   events in DB: wallet_id={} count={}", w, c);
            }
            Ok(())
        }) {}
    }
    Ok(events)
}

pub fn events_get_unsynced(wallet_id: &str) -> Result<Vec<StoredEvent>, ClientError> {
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

pub fn events_mark_synced(ids: &[String]) -> Result<(), ClientError> {
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

pub fn events_delete_unsynced(wallet_id: &str) -> Result<u64, ClientError> {
    with_db(|conn| {
        let affected = conn.execute(
            "DELETE FROM events WHERE wallet_id = ?1 AND synced = 0",
            params![wallet_id],
        )?;
        Ok(affected as u64)
    })
}

pub fn events_delete_all_for_wallet(wallet_id: &str) -> Result<(), ClientError> {
    with_db(|conn| {
        conn.execute(
            "DELETE FROM events WHERE wallet_id = ?1",
            params![wallet_id],
        )?;
        conn.execute(
            "DELETE FROM contacts WHERE wallet_id = ?1",
            params![wallet_id],
        )?;
        conn.execute(
            "DELETE FROM transactions WHERE wallet_id = ?1",
            params![wallet_id],
        )?;
        conn.execute(
            "DELETE FROM wallet_users WHERE wallet_id = ?1",
            params![wallet_id],
        )?;
        conn.execute(
            "DELETE FROM wallet_owners WHERE wallet_id = ?1",
            params![wallet_id],
        )?;
        conn.execute(
            "DELETE FROM user_groups WHERE wallet_id = ?1",
            params![wallet_id],
        )?;
        conn.execute(
            "DELETE FROM contact_groups WHERE wallet_id = ?1",
            params![wallet_id],
        )?;
        conn.execute(
            "DELETE FROM projection_snapshots WHERE wallet_id = ?1",
            params![wallet_id],
        )?;
        Ok(())
    })
}

pub fn events_count(wallet_id: &str) -> Result<i64, ClientError> {
    with_db(|conn| {
        let count: i64 = conn.query_row(
            "SELECT COUNT(*) FROM events WHERE wallet_id = ?1",
            params![wallet_id],
            |row| row.get(0),
        )?;
        Ok(count)
    })
}

pub fn events_get_for_aggregate(
    wallet_id: &str,
    aggregate_type: &str,
    aggregate_id: &str,
) -> Result<Vec<StoredEvent>, ClientError> {
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

pub fn load_contacts_from_tables(wallet_id: &str) -> Result<Vec<Contact>, ClientError> {
    with_db(|conn| {
        let mut stmt = conn.prepare(
            r#"
            SELECT c.id, c.name, c.username, c.phone, c.email, c.notes,
                   c.created_at, c.updated_at, c.is_synced, c.wallet_id,
                   COALESCE(
                     (SELECT SUM(
                                CASE t.direction
                                    WHEN 'owed' THEN  t.amount
                                    WHEN 'lent' THEN -t.amount
                                    ELSE              t.amount
                                END
                            )
                        FROM transactions t
                       WHERE t.contact_id = c.id AND t.is_deleted = 0), 0
                   ) AS balance
              FROM contacts c
             WHERE c.wallet_id = ?1 AND c.is_deleted = 0
             ORDER BY c.name COLLATE NOCASE
            "#,
        )?;
        let rows = stmt.query_map(params![wallet_id], |r| {
            Ok(Contact {
                id: r.get::<_, String>(0)?,
                name: r.get::<_, String>(1)?,
                username: r.get::<_, Option<String>>(2)?,
                phone: r.get::<_, Option<String>>(3)?,
                email: r.get::<_, Option<String>>(4)?,
                notes: r.get::<_, Option<String>>(5)?,
                created_at: r.get::<_, String>(6)?,
                updated_at: r.get::<_, String>(7)?,
                is_synced: r.get::<_, i32>(8)? != 0,
                balance: r.get::<_, i64>(10)?,
                wallet_id: r.get::<_, Option<String>>(9)?,
            })
        })?;
        let mut out = Vec::new();
        for row in rows {
            out.push(row?);
        }
        Ok(out)
    })
}

pub fn load_transactions_from_tables(wallet_id: &str) -> Result<Vec<Transaction>, ClientError> {
    with_db(|conn| {
        let mut stmt = conn.prepare(
            r#"
            SELECT id, contact_id, type, direction, amount, currency, description,
                   transaction_date, due_date, created_at, updated_at, is_synced, wallet_id
              FROM transactions
             WHERE wallet_id = ?1 AND is_deleted = 0
             ORDER BY transaction_date DESC, created_at DESC
            "#,
        )?;
        let rows = stmt.query_map(params![wallet_id], |r| {
            let type_str: String = r.get(2)?;
            let direction_str: String = r.get(3)?;
            let currency_str: String = r.get(5)?;
            let type_ = domain::TransactionType::from_str(&type_str)
                .unwrap_or(domain::TransactionType::Money)
                .into();
            let direction = domain::TransactionDirection::from_str(&direction_str)
                .unwrap_or(domain::TransactionDirection::Owed)
                .into();
            let currency = domain::Currency::from_str(&currency_str)
                .map(crate::types::models::Currency::from)
                .unwrap_or(crate::types::models::Currency::IQD);
            Ok(Transaction {
                id: r.get::<_, String>(0)?,
                contact_id: r.get::<_, String>(1)?,
                type_,
                direction,
                amount: r.get::<_, i64>(4)?,
                currency,
                description: r.get::<_, Option<String>>(6)?,
                transaction_date: r.get::<_, String>(7)?,
                due_date: r.get::<_, Option<String>>(8)?,
                image_paths: Vec::new(),
                created_at: r.get::<_, String>(9)?,
                updated_at: r.get::<_, String>(10)?,
                is_synced: r.get::<_, i32>(11)? != 0,
                wallet_id: r.get::<_, Option<String>>(12)?,
            })
        })?;
        let mut out = Vec::new();
        for row in rows {
            out.push(row?);
        }
        Ok(out)
    })
}
