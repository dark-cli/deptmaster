use uuid::Uuid;
use sqlx::Row;
use crate::AppState;
use crate::services::snapshots;
use crate::database::repository::Database;

/// Projections: Handles all projection-related operations (rebuilds, snapshots, etc.)
/// Consolidates projection logic into a single model for consistency and testability
pub struct Projections;

impl Projections {
    /// Rebuild projections from all events in the database for a specific wallet
    /// Implements the optimized algorithm:
    /// 1. Create projection after any new event
    /// 2. Stack of snapshots (push after every 10 events or after UNDO event)
    /// 3. If UNDO event: find undone event position, find snapshot before it, create cleaned event list
    /// 4. Pass cleaned event list + snapshot to builder
    /// 5. Builder creates new snapshot, make it current projection, save to stack
    pub async fn rebuild_projections_from_events(
        state: &AppState,
        wallet_id: Uuid,
    ) -> Result<(), sqlx::Error> {
        tracing::info!("Rebuilding projections from events for wallet {}...", wallet_id);

        // Get user ID (for this wallet, get the first user who has access)
        let user_id = sqlx::query_scalar::<_, Uuid>(
            "SELECT user_id FROM wallet_users WHERE wallet_id = $1 LIMIT 1"
        )
        .bind(wallet_id)
        .fetch_one(&*state.db_pool)
        .await?;

        // Get all events for this wallet ordered by timestamp (chronological order)
        let events = sqlx::query(
            r#"
            SELECT event_id, aggregate_type, aggregate_id, event_type, event_data, created_at, id
            FROM events
            WHERE wallet_id = $1
            ORDER BY created_at ASC
            "#
        )
        .bind(wallet_id)
        .fetch_all(&*state.db_pool)
        .await?;

        // Get event count and last event info
        let event_count = events.len() as i64;
        let last_event_uuid = events.last().map(|row| row.get::<Uuid, _>("event_id"));
        let last_event_db_id = events.last().and_then(|row| row.get::<Option<i64>, _>("id"));

        // Build a map of event_id (UUID) -> position (1-based index) for fast lookup
        let mut event_id_to_position: std::collections::HashMap<Uuid, i64> = std::collections::HashMap::new();
        for (index, row) in events.iter().enumerate() {
            let event_id: Uuid = row.get("event_id");
            event_id_to_position.insert(event_id, (index + 1) as i64);
        }

        // Check for UNDO events
        let has_undo_events = events.iter().any(|row| {
            let event_type: String = row.get("event_type");
            event_type == "UNDO"
        });

        let used_snapshot = if has_undo_events {
            // Step 3: If UNDO event exists, find undone event positions
            let mut undone_event_positions = Vec::new();
            let mut undone_event_ids = std::collections::HashSet::new();

            for row in &events {
                let event_type: String = row.get("event_type");
                if event_type == "UNDO" {
                    let event_data: serde_json::Value = row.get("event_data");
                    if let Some(undone_id_str) = event_data.get("undone_event_id").and_then(|v| v.as_str()) {
                        if let Ok(undone_id) = uuid::Uuid::parse_str(undone_id_str) {
                            undone_event_ids.insert(undone_id);
                            // Find the undone event's position using the map (fast lookup by ID)
                            if let Some(position) = event_id_to_position.get(&undone_id) {
                                undone_event_positions.push(*position);
                            }
                        }
                    }
                }
            }

            // Find the minimum undone event position (earliest undone event)
            let min_undone_position = undone_event_positions.iter().min().copied();

            // Step 4: Search snapshot stack for snapshot with event_count < undone_event_count (wallet-scoped)
            let snapshot = if let Some(target_count) = min_undone_position {
                snapshots::get_snapshot_before_event_count(
                    &*state.db_pool,
                    target_count,
                    wallet_id,
                ).await.ok().flatten()
            } else {
                None
            };

            // Step 5: Create cleaned event list (remove UNDO and undone events)
            let cleaned_events: Vec<_> = events.iter()
                .filter(|row| {
                    let event_id: Uuid = row.get("event_id");
                    let event_type: String = row.get("event_type");

                    // Skip UNDO events
                    if event_type == "UNDO" {
                        return false;
                    }

                    // Skip undone events
                    if undone_event_ids.contains(&event_id) {
                        return false;
                    }

                    true
                })
                .map(|row| row as &sqlx::postgres::PgRow)
                .collect();

            // Step 6: Use snapshot if found, otherwise use full cleaned event list
            if let Some(snapshot) = snapshot {
                // Restore from snapshot (pass undone_event_ids to filter them out)
                let db = Database::new((*state.db_pool).clone());
                if db.restore_projections_from_snapshot(&snapshot, user_id, wallet_id, &undone_event_ids).await.is_ok() {
                    // Get events after the snapshot (from cleaned events)
                    let snapshot_last_db_id = snapshot.last_event_id;
                    let events_after_snapshot: Vec<_> = cleaned_events.iter()
                        .filter(|row| {
                            let event_db_id: Option<i64> = row.get("id");
                            event_db_id.map_or(false, |id| id > snapshot_last_db_id)
                        })
                        .copied()
                        .collect();

                    if !events_after_snapshot.is_empty() {
                        // Apply cleaned events after snapshot
                        let mut empty_undone_set = std::collections::HashSet::new();
                        let db = Database::new((*state.db_pool).clone());
                        if db.apply_events_to_projections_impl(&events_after_snapshot, user_id, wallet_id, &mut empty_undone_set).await.is_ok() {
                            tracing::info!("Used snapshot optimization with UNDO: {} events after snapshot", events_after_snapshot.len());
                            true
                        } else {
                            false
                        }
                    } else {
                        true
                    }
                } else {
                    false
                }
            } else {
                // No snapshot, apply all cleaned events
                let db = Database::new((*state.db_pool).clone());
                let mut undone_set = undone_event_ids.clone();
                if db.apply_events_to_projections_impl(&cleaned_events, user_id, wallet_id, &mut undone_set).await.is_ok() {
                    tracing::info!("Applied {} cleaned events after UNDO (no snapshot available)", cleaned_events.len());
                    true
                } else {
                    false
                }
            }
        } else {
            // No UNDO events - use snapshot optimization if available
            if let Some(last_id) = last_event_db_id {
                tracing::info!("Attempting snapshot optimization: last_event_db_id={:?}", last_id);
                if let Ok(Some(snapshot)) = snapshots::get_snapshot_before_event(
                    &*state.db_pool,
                    last_id,
                    wallet_id,
                ).await {
                    tracing::info!("Found snapshot: last_event_id={}, event_count={}", snapshot.last_event_id, snapshot.event_count);
                    // Get events after the snapshot
                    let snapshot_last_db_id = snapshot.last_event_id;
                    let events_after_snapshot: Vec<_> = events.iter()
                        .filter(|row| {
                            let event_db_id: Option<i64> = row.get("id");
                            event_db_id.map_or(false, |id| id > snapshot_last_db_id)
                        })
                        .map(|row| row as &sqlx::postgres::PgRow)
                        .collect();

                    if !events_after_snapshot.is_empty() {
                        // Collect undone event IDs from all events (even if no UNDO in current set,
                        // snapshot might contain items undone by previous UNDO events)
                        let mut undone_event_ids = std::collections::HashSet::new();
                        for row in &events {
                            let event_type: String = row.get("event_type");
                            if event_type == "UNDO" {
                                let event_data: serde_json::Value = row.get("event_data");
                                if let Some(undone_id_str) = event_data.get("undone_event_id").and_then(|v| v.as_str()) {
                                    if let Ok(undone_id) = uuid::Uuid::parse_str(undone_id_str) {
                                        undone_event_ids.insert(undone_id);
                                    }
                                }
                            }
                        }

                        // Restore projections from snapshot (filter out undone events)
                        let db = Database::new((*state.db_pool).clone());
                        if db.restore_projections_from_snapshot(&snapshot, user_id, wallet_id, &undone_event_ids).await.is_ok() {
                            // Apply events after snapshot
                            let mut empty_undone_set = std::collections::HashSet::new();
                            if db.apply_events_to_projections_impl(&events_after_snapshot, user_id, wallet_id, &mut empty_undone_set).await.is_ok() {
                                tracing::info!("Used snapshot for optimization: {} events after snapshot", events_after_snapshot.len());
                                true
                            } else {
                                false
                            }
                        } else {
                            false
                        }
                    } else {
                        // No new events, snapshot is current - just restore it
                        // Still need to check for undone events in case snapshot contains undone items
                        let mut undone_event_ids = std::collections::HashSet::new();
                        for row in &events {
                            let event_type: String = row.get("event_type");
                            if event_type == "UNDO" {
                                let event_data: serde_json::Value = row.get("event_data");
                                if let Some(undone_id_str) = event_data.get("undone_event_id").and_then(|v| v.as_str()) {
                                    if let Ok(undone_id) = uuid::Uuid::parse_str(undone_id_str) {
                                        undone_event_ids.insert(undone_id);
                                    }
                                }
                            }
                        }
                        let db = Database::new((*state.db_pool).clone());
                        db.restore_projections_from_snapshot(&snapshot, user_id, wallet_id, &undone_event_ids).await.is_ok()
                    }
                } else {
                    tracing::info!("Snapshot not found or failed to restore");
                    false
                }
            } else {
                tracing::info!("No last_event_db_id, skipping snapshot optimization");
                false
            }
        };

        // If snapshot optimization failed or not used, do full rebuild
        if !used_snapshot {
            tracing::warn!("Snapshot optimization failed or not available, performing full rebuild");
            // Clear existing projections for this wallet (delete transactions first due to foreign key constraints)
            sqlx::query("DELETE FROM transactions_projection WHERE wallet_id = $1")
                .bind(wallet_id)
                .execute(&*state.db_pool)
                .await?;

            sqlx::query("DELETE FROM contacts_projection WHERE wallet_id = $1")
                .bind(wallet_id)
                .execute(&*state.db_pool)
                .await?;

            // Collect undone event IDs if UNDO events exist
            let mut undone_event_ids: std::collections::HashSet<Uuid> = std::collections::HashSet::new();
            if has_undo_events {
                for row in &events {
                    let event_type: String = row.get("event_type");
                    if event_type == "UNDO" {
                        let event_data: serde_json::Value = row.get("event_data");
                        if let Some(undone_id_str) = event_data.get("undone_event_id").and_then(|v| v.as_str()) {
                            if let Ok(undone_id) = uuid::Uuid::parse_str(undone_id_str) {
                                undone_event_ids.insert(undone_id);
                            }
                        }
                    }
                }
            }

            // Apply all events to rebuild
            let filtered: Vec<_> = events.iter()
                .filter(|row| {
                    let event_type: String = row.get("event_type");

                    // Skip UNDO events
                    if event_type == "UNDO" {
                        return false;
                    }

                    true
                })
                .map(|row| row as &sqlx::postgres::PgRow)
                .collect();

            tracing::info!("After filtering: {} events to process (from {} total)", filtered.len(), events.len());

            let rows_to_apply: Vec<_> = filtered.iter().map(|row| *row).collect();
            let db = Database::new((*state.db_pool).clone());
            db.apply_events_to_projections_impl(&rows_to_apply, user_id, wallet_id, &mut undone_event_ids).await?;
        }

        tracing::info!("Projection rebuild completed for wallet {}", wallet_id);
        Ok(())
    }
}
