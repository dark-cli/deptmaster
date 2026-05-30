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

        // Phase 1 optimization: Check if projections exist for this wallet
        // If they do, only load events after the last processed event
        let max_processed_id: Option<i64> = sqlx::query_scalar(
            "SELECT MAX(last_event_id) FROM (
                SELECT COALESCE(MAX(last_event_id), 0) as last_event_id FROM contacts_projection WHERE wallet_id = $1
                UNION ALL
                SELECT COALESCE(MAX(last_event_id), 0) as last_event_id FROM transactions_projection WHERE wallet_id = $1
            ) t"
        )
        .bind(wallet_id)
        .fetch_optional(&*state.db_pool)
        .await?
        .flatten();

        let has_existing_projections = max_processed_id.is_some() && max_processed_id != Some(0);

        // Get events for this wallet ordered by timestamp
        // If projections exist, load only new events (Phase 1 optimization)
        // If rebuilding from scratch, load all events
        let events = sqlx::query(
            r#"
            SELECT event_id, aggregate_type, aggregate_id, event_type, event_data, created_at, id
            FROM events
            WHERE wallet_id = $1 AND id > COALESCE($2, 0)
            ORDER BY created_at ASC
            "#
        )
        .bind(wallet_id)
        .bind(max_processed_id.unwrap_or(0))
        .fetch_all(&*state.db_pool)
        .await?;

        // Early return if no new events and projections already exist (Phase 1 optimization win)
        if events.is_empty() && has_existing_projections {
            tracing::info!("No new events since last projection update, skipping rebuild");
            return Ok(());
        }

        // Get last event info (used for snapshot lookup)
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

        // Clear projections and permission data if UNDO events exist (they require full rebuild)
        // or if doing full rebuild (checked later in snapshot path)
        if has_undo_events {
            tracing::info!("UNDO events detected, clearing projections for rebuild");

            // Find the actual wallet owner (role = 'owner')
            let owner_user_id: Option<Uuid> = sqlx::query_scalar(
                "SELECT user_id FROM wallet_users WHERE wallet_id = $1 AND role = 'owner' LIMIT 1"
            )
            .bind(wallet_id)
            .fetch_optional(&*state.db_pool)
            .await?;

            let owner_id = owner_user_id.unwrap_or(user_id); // Fallback to current user if no owner found

            // Clear existing projections
            sqlx::query("DELETE FROM transactions_projection WHERE wallet_id = $1")
                .bind(wallet_id)
                .execute(&*state.db_pool)
                .await?;

            sqlx::query("DELETE FROM contacts_projection WHERE wallet_id = $1")
                .bind(wallet_id)
                .execute(&*state.db_pool)
                .await?;

            // Clear permission-related data (but preserve the wallet owner)
            sqlx::query("DELETE FROM contact_group_members WHERE contact_group_id IN (SELECT id FROM contact_groups WHERE wallet_id = $1 AND is_system = false)")
                .bind(wallet_id)
                .execute(&*state.db_pool)
                .await?;

            sqlx::query("DELETE FROM contact_groups WHERE wallet_id = $1 AND is_system = false")
                .bind(wallet_id)
                .execute(&*state.db_pool)
                .await?;

            sqlx::query("DELETE FROM user_group_members WHERE user_group_id IN (SELECT id FROM user_groups WHERE wallet_id = $1 AND is_system = false)")
                .bind(wallet_id)
                .execute(&*state.db_pool)
                .await?;

            sqlx::query("DELETE FROM user_groups WHERE wallet_id = $1 AND is_system = false")
                .bind(wallet_id)
                .execute(&*state.db_pool)
                .await?;

            // Clear all non-owner wallet users (to rebuild permission state from events)
            sqlx::query("DELETE FROM wallet_users WHERE wallet_id = $1 AND user_id != $2")
                .bind(wallet_id)
                .bind(owner_id)
                .execute(&*state.db_pool)
                .await?;
        }

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
                        if db.apply_event_batch(&events_after_snapshot, user_id, wallet_id, &mut empty_undone_set).await.is_ok() {
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
                if db.apply_event_batch(&cleaned_events, user_id, wallet_id, &mut undone_set).await.is_ok() {
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
                            if db.apply_event_batch(&events_after_snapshot, user_id, wallet_id, &mut empty_undone_set).await.is_ok() {
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
            tracing::warn!("Snapshot optimization failed or not available, performing full rebuild with batch processing");

            // Clear existing projections and permission data for this wallet if not already cleared above
            if !has_undo_events {
                // Only clear if we haven't already done so in the UNDO block above

                // Find the actual wallet owner
                let owner_user_id: Option<Uuid> = sqlx::query_scalar(
                    "SELECT user_id FROM wallet_users WHERE wallet_id = $1 AND role = 'owner' LIMIT 1"
                )
                .bind(wallet_id)
                .fetch_optional(&*state.db_pool)
                .await?;

                let owner_id = owner_user_id.unwrap_or(user_id); // Fallback to current user if no owner found

                sqlx::query("DELETE FROM transactions_projection WHERE wallet_id = $1")
                    .bind(wallet_id)
                    .execute(&*state.db_pool)
                    .await?;

                sqlx::query("DELETE FROM contacts_projection WHERE wallet_id = $1")
                    .bind(wallet_id)
                    .execute(&*state.db_pool)
                    .await?;

                // Clear permission-related data (but preserve the wallet owner)
                sqlx::query("DELETE FROM contact_group_members WHERE contact_group_id IN (SELECT id FROM contact_groups WHERE wallet_id = $1 AND is_system = false)")
                    .bind(wallet_id)
                    .execute(&*state.db_pool)
                    .await?;

                sqlx::query("DELETE FROM contact_groups WHERE wallet_id = $1 AND is_system = false")
                    .bind(wallet_id)
                    .execute(&*state.db_pool)
                    .await?;

                sqlx::query("DELETE FROM user_group_members WHERE user_group_id IN (SELECT id FROM user_groups WHERE wallet_id = $1 AND is_system = false)")
                    .bind(wallet_id)
                    .execute(&*state.db_pool)
                    .await?;

                sqlx::query("DELETE FROM user_groups WHERE wallet_id = $1 AND is_system = false")
                    .bind(wallet_id)
                    .execute(&*state.db_pool)
                    .await?;

                sqlx::query("DELETE FROM wallet_users WHERE wallet_id = $1 AND user_id != $2")
                    .bind(wallet_id)
                    .bind(owner_id)
                    .execute(&*state.db_pool)
                    .await?;
            }

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

            // Phase 2 optimization: Batch process events to maintain bounded memory
            let batch_size = state.config.event_rebuild_batch_size;
            let mut offset = 0;
            let mut total_processed = 0;

            loop {
                // Load one batch at a time
                let batch = sqlx::query(
                    r#"
                    SELECT event_id, aggregate_type, aggregate_id, event_type, event_data, created_at, id
                    FROM events
                    WHERE wallet_id = $1 AND id > COALESCE($2, 0)
                    ORDER BY created_at ASC
                    LIMIT $3 OFFSET $4
                    "#
                )
                .bind(wallet_id)
                .bind(max_processed_id.unwrap_or(0))
                .bind(batch_size as i64)
                .bind(offset as i64)
                .fetch_all(&*state.db_pool)
                .await?;

                if batch.is_empty() {
                    break;
                }

                // Filter out UNDO events from this batch
                let filtered: Vec<_> = batch.iter()
                    .filter(|row| {
                        let event_type: String = row.get("event_type");
                        event_type != "UNDO"
                    })
                    .map(|row| row as &sqlx::postgres::PgRow)
                    .collect();

                if !filtered.is_empty() {
                    let db = Database::new((*state.db_pool).clone());
                    // Keep using the old apply_event_batch while we complete the type-driven migration
                    // TODO: Migrate to apply_event_batch_type_driven once all event handlers are complete
                    db.apply_event_batch(&filtered, user_id, wallet_id, &mut undone_event_ids).await?;
                    total_processed += filtered.len();
                    tracing::debug!("Processed batch of {} events (total: {})", filtered.len(), total_processed);
                }

                offset += batch.len();
            }

            tracing::info!("Completed full rebuild: processed {} events in batches of {}", total_processed, batch_size);
        }

        tracing::info!("Projection rebuild completed for wallet {}", wallet_id);
        Ok(())
    }
}
