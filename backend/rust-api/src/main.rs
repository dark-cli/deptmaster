use axum::{
    Router,
    routing::{get, post, put, delete},
};
use std::sync::Arc;
use tokio::signal;
use tracing::{info, error};

mod config;
mod handlers;
mod models;
mod services;
mod background;
mod database;
mod utils;
mod websocket;
// app_state module removed - AppState defined directly in main.rs

use config::Config;
use database::DatabasePool;
use websocket::BroadcastChannel;
use handlers::admin::rebuild_projections;

// Define AppState in main.rs (not in shared app_state.rs to avoid library build issues)
#[derive(Clone)]
pub struct AppState {
    pub db_pool: DatabasePool,
    pub config: Arc<Config>,
    pub broadcast_tx: BroadcastChannel,
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // Load environment variables
    dotenv::dotenv().ok();

    // Initialize tracing
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "debt_tracker_api=debug,tower_http=debug".into())
        )
        .init();

    info!("Starting Debt Tracker API server...");

    // Load configuration
    let config = Arc::new(Config::from_env()?);
    info!("Configuration loaded");

    // Initialize database pool
    let db_pool = database::new_pool(&config.database_url).await?;
    info!("Database connection pool created");

    // Seed dummy data if database is empty
    services::seed_data::seed_dummy_data(&db_pool).await?;

    // Initialize background scheduler (starts automatically)
    let scheduler = Arc::new(
        background::scheduler::BackgroundScheduler::new(
            db_pool.clone(),
            config.clone(),
        ).await?
    );
    info!("Background scheduler started");

    // Create WebSocket broadcast channel for real-time updates
    let broadcast_tx = websocket::create_broadcast_channel();
    info!("WebSocket broadcast channel created");

    // Build application state
    let app_state = AppState {
        db_pool: db_pool.clone(),
        config: config.clone(),
        broadcast_tx: broadcast_tx.clone(),
    };

    // Build API routes
    let app = Router::new()
        .route("/", get(|| async { axum::response::Redirect::permanent("/admin") }))
        .route("/health", get(health_check))
        .route("/admin", get(handlers::admin_panel))
        .route("/api/admin/events", get(handlers::get_events))
        .route("/api/admin/events/latest", get(handlers::get_latest_event_id))
        .route("/api/admin/events/backfill-transactions", post(handlers::backfill_transaction_events))
        .route("/api/admin/contacts", get(handlers::get_contacts))
        .route("/api/admin/transactions", get(handlers::get_admin_transactions))
        .route("/api/admin/projections/status", get(handlers::get_projection_status))
        .route("/api/admin/total-debt", get(handlers::get_total_debt))
        .route("/api/admin/projections/rebuild", axum::routing::post(rebuild_projections))
        .route("/api/contacts", post(handlers::create_contact))
        .route("/api/contacts/:id", put(handlers::update_contact))
        .route("/api/contacts/:id", delete(handlers::delete_contact))
        .route("/api/transactions", get(handlers::get_transactions))
        .route("/api/transactions", post(handlers::create_transaction))
        .route("/api/transactions/:id", put(handlers::update_transaction))
        .route("/api/transactions/:id", delete(handlers::delete_transaction))
        .route("/api/settings", get(handlers::get_settings))
        .route("/api/settings/:key", axum::routing::put(handlers::update_setting))
        .route("/api/auth/login", post(handlers::login))
        .route("/api/sync/hash", get(handlers::get_sync_hash))
        .route("/api/sync/events", get(handlers::get_sync_events))
        .route("/api/sync/events", post(handlers::post_sync_events))
        .route("/ws", get(websocket::websocket_handler))
        .layer(tower_http::cors::CorsLayer::permissive())
        .layer(tower_http::trace::TraceLayer::new_for_http())
        .with_state(app_state);

    // Start server
    let addr = format!("0.0.0.0:{}", config.port);
    let listener = tokio::net::TcpListener::bind(&addr).await?;
    info!("Server listening on http://{}", addr);

    // Graceful shutdown
    tokio::select! {
        result = axum::serve(listener, app) => {
            if let Err(e) = result {
                error!("Server error: {}", e);
            }
        }
        _ = shutdown_signal() => {
            info!("Shutting down gracefully...");
            scheduler.shutdown().await;
        }
    }

    Ok(())
}

async fn health_check() -> &'static str {
    "OK"
}

async fn shutdown_signal() {
    let ctrl_c = async {
        signal::ctrl_c()
            .await
            .expect("failed to install Ctrl+C handler");
    };

    #[cfg(unix)]
    let terminate = async {
        signal::unix::signal(signal::unix::SignalKind::terminate())
            .expect("failed to install signal handler")
            .recv()
            .await;
    };

    #[cfg(not(unix))]
    let terminate = std::future::pending::<()>();

    tokio::select! {
        _ = ctrl_c => {},
        _ = terminate => {},
    }

    tracing::info!("Shutdown signal received");
}
