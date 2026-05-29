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

        // Clear existing projections for this wallet
        sqlx::query("DELETE FROM transactions_projection WHERE wallet_id = $1")
            .bind(wallet_id)
            .execute(&*state.db_pool)
            .await?;

        sqlx::query("DELETE FROM contacts_projection WHERE wallet_id = $1")
            .bind(wallet_id)
            .execute(&*state.db_pool)
            .await?;

        // Collect undone event IDs from UNDO events
        let mut undone_event_ids: std::collections::HashSet<Uuid> = std::collections::HashSet::new();
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

        // Filter events: exclude UNDO and undone events
        let filtered: Vec<_> = events.iter()
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

        tracing::info!("After filtering: {} events to process (from {} total)", filtered.len(), events.len());

        let rows_to_apply: Vec<_> = filtered.iter().map(|row| *row).collect();
        let db = Database::new((*state.db_pool).clone());
        db.apply_events_to_projections_impl(&rows_to_apply, user_id, wallet_id, &mut undone_event_ids).await?;

        tracing::info!("Projection rebuild completed for wallet {}", wallet_id);
        Ok(())
    }
}
