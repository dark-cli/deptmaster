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
mod middleware;
// app_state module removed - AppState defined directly in main.rs

use config::Config;
use database::DatabasePool;
use websocket::BroadcastChannel;
use handlers::admin::rebuild_projections;
use middleware::auth::auth_middleware;
use middleware::rate_limit::{RateLimiter, rate_limit_middleware};
use middleware::wallet_context::wallet_context_middleware;

// Define AppState in main.rs (not in shared app_state.rs to avoid library build issues)
#[derive(Clone)]
pub struct AppState {
    pub db_pool: DatabasePool,
    pub config: Arc<Config>,
    pub broadcast_tx: BroadcastChannel,
    pub rate_limiter: RateLimiter,
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
    config.validate()?;
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

    // Create rate limiter
    let rate_limiter = RateLimiter::new(
        config.rate_limit_requests,
        config.rate_limit_window,
    );
    if config.rate_limit_requests == 0 {
        info!("Rate limiter disabled (RATE_LIMIT_REQUESTS=0)");
    } else {
        info!("Rate limiter initialized: {} requests per {} seconds", config.rate_limit_requests, config.rate_limit_window);
    }

    // Build application state
    let app_state = AppState {
        db_pool: db_pool.clone(),
        config: config.clone(),
        broadcast_tx: broadcast_tx.clone(),
        rate_limiter: rate_limiter.clone(),
    };

    // Public routes (no authentication required)
    let public_routes = Router::new()
        .route("/health", get(health_check))
        .route("/api/auth/login", post(handlers::login)) // Regular user login
        .route("/api/auth/admin/login", post(handlers::admin_login)) // Admin login
        .route("/admin", get(handlers::admin_panel)) // Admin page HTML is public (login form)
        .route("/config.js", get(handlers::config_js)) // Admin config.js (optional, returns empty if not exists)
        .route("/favicon.ico", get(handlers::favicon)) // Favicon
        .route("/api/dev/clear-database", axum::routing::post(handlers::dev_clear_database)); // Dev-only: clears database (checks ENVIRONMENT internally)

    // Protected API routes that require wallet context
    let wallet_protected_routes = Router::new()
        .route("/api/contacts", get(handlers::get_contacts))
        .route("/api/contacts", post(handlers::create_contact))
        .route("/api/contacts/:id", put(handlers::update_contact))
        .route("/api/contacts/:id", delete(handlers::delete_contact))
        .route("/api/transactions", get(handlers::get_transactions))
        .route("/api/transactions", post(handlers::create_transaction))
        .route("/api/transactions/:id", put(handlers::update_transaction))
        .route("/api/transactions/:id", delete(handlers::delete_transaction))
        .route("/api/sync/hash", get(handlers::get_sync_hash))
        .route("/api/sync/events", get(handlers::get_sync_events))
        .route("/api/sync/events", post(handlers::post_sync_events))
        .layer(axum::middleware::from_fn_with_state(
            app_state.clone(),
            wallet_context_middleware,
        ))
        .layer(axum::middleware::from_fn_with_state(
            app_state.clone(),
            auth_middleware,
        ));

    // Protected API routes that don't require wallet context
    let protected_api_routes = Router::new()
        .route("/api/settings", get(handlers::get_settings))
        .route("/api/settings/:key", axum::routing::put(handlers::update_setting))
        .route("/api/auth/change-password", axum::routing::put(handlers::change_password))
        .route("/api/wallets", get(handlers::list_user_wallets).post(handlers::create_my_wallet))
        .route("/api/wallets/:id", get(handlers::get_wallet))
        .layer(axum::middleware::from_fn_with_state(
            app_state.clone(),
            auth_middleware,
        ));

    // Admin routes (require authentication)
    let admin_routes = Router::new()
        .route("/api/admin/events", get(handlers::get_events))
        .route("/api/admin/events/latest", get(handlers::get_latest_event_id))
        .route("/api/admin/events/backfill-transactions", post(handlers::backfill_transaction_events))
        .route("/api/admin/contacts", get(handlers::get_admin_contacts))
        .route("/api/admin/transactions", get(handlers::get_admin_transactions))
        .route("/api/admin/projections/status", get(handlers::get_projection_status))
        .route("/api/admin/total-debt", get(handlers::get_total_debt))
        .route("/api/admin/projections/rebuild", axum::routing::post(rebuild_projections))
        .route("/api/admin/users", get(handlers::get_users))
        .route("/api/admin/users", post(handlers::create_user))
        .route("/api/admin/users/:id", axum::routing::delete(handlers::delete_user))
        .route("/api/admin/users/:id/password", axum::routing::put(handlers::admin_change_password))
        .route("/api/admin/users/:id/login-logs", get(handlers::get_user_login_logs))
        .route("/api/admin/users/:id/backup", get(handlers::backup_user_data))
        .route("/api/admin/wallets", get(handlers::list_wallets))
        .route("/api/admin/wallets", post(handlers::create_wallet))
        .route("/api/admin/wallets/:id", get(handlers::get_wallet))
        .route("/api/admin/wallets/:id", axum::routing::put(handlers::update_wallet))
        .route("/api/admin/wallets/:id", axum::routing::delete(handlers::delete_wallet))
        .route("/api/admin/wallets/:id/users", get(handlers::list_wallet_users))
        .route("/api/admin/wallets/:id/users", post(handlers::add_user_to_wallet))
        .route("/api/admin/wallets/:id/users/:user_id", axum::routing::put(handlers::update_wallet_user))
        .route("/api/admin/wallets/:id/users/:user_id", axum::routing::delete(handlers::remove_user_from_wallet))
        .layer(axum::middleware::from_fn_with_state(
            app_state.clone(),
            auth_middleware,
        ));

    // WebSocket route (will add auth later)
    let ws_routes = Router::new()
        .route("/ws", get(websocket::websocket_handler));

    // Build complete app
    let app = Router::new()
        .route("/", get(|| async { axum::response::Redirect::permanent("/admin") }))
        .merge(public_routes)
        .merge(wallet_protected_routes)
        .merge(protected_api_routes)
        .merge(admin_routes)
        .merge(ws_routes)
        .layer(create_cors_layer(&config))
        .layer(axum::middleware::from_fn_with_state(
            rate_limiter.clone(),
            rate_limit_middleware,
        ))
        .layer(axum::middleware::from_fn(middleware::security_headers::security_headers_middleware))
        .layer(tower_http::trace::TraceLayer::new_for_http())
        .with_state(app_state);

    // Start server
    let addr = format!("0.0.0.0:{}", config.port);
    
    if config.enable_tls {
        // HTTPS mode - TLS configuration validation
        // NOTE: For production, we STRONGLY RECOMMEND using a reverse proxy (nginx/Caddy/Traefik)
        // Direct TLS in Axum 0.7 requires complex stream handling that is better handled by a reverse proxy.
        // Reverse proxies also provide automatic certificate renewal, better performance, and additional security features.
        
        let cert_path = config.tls_cert_path.as_ref().ok_or_else(|| {
            anyhow::anyhow!("TLS enabled but TLS_CERT_PATH not set")
        })?;
        let key_path = config.tls_key_path.as_ref().ok_or_else(|| {
            anyhow::anyhow!("TLS enabled but TLS_KEY_PATH not set")
        })?;

        // Validate certificate and key files exist and are readable
        let cert = std::fs::read(cert_path)
            .map_err(|e| anyhow::anyhow!("Failed to read certificate file {}: {}", cert_path, e))?;
        let key = std::fs::read(key_path)
            .map_err(|e| anyhow::anyhow!("Failed to read key file {}: {}", key_path, e))?;

        // Validate certificate and key can be parsed
        let mut cert_reader = std::io::BufReader::new(cert.as_slice());
        let cert_chains = rustls_pemfile::certs(&mut cert_reader)
            .map_err(|e| anyhow::anyhow!("Failed to parse certificate: {}", e))?;
        
        if cert_chains.is_empty() {
            return Err(anyhow::anyhow!("No certificates found in certificate file"));
        }
        
        let cert_chain: Vec<rustls::Certificate> = cert_chains
            .into_iter()
            .map(|cert_bytes| rustls::Certificate(cert_bytes))
            .collect();

        let mut key_reader = std::io::BufReader::new(key.as_slice());
        let key_chains = rustls_pemfile::pkcs8_private_keys(&mut key_reader)
            .map_err(|e| anyhow::anyhow!("Failed to parse private key: {}", e))?;
        
        let key_der = key_chains.into_iter().next()
            .ok_or_else(|| anyhow::anyhow!("No private key found in key file"))?;

        // Validate TLS config can be built
        let _tls_config = rustls::ServerConfig::builder()
            .with_safe_defaults()
            .with_no_client_auth()
            .with_single_cert(cert_chain, rustls::PrivateKey(key_der))
            .map_err(|e| anyhow::anyhow!("Failed to build TLS config: {}", e))?;

        // TLS configuration is valid, but we'll run on HTTP and recommend reverse proxy
        // This allows the server to start and be proxied by nginx/Caddy/etc.
        info!("✅ TLS configuration validated successfully");
        info!("⚠️  TLS is enabled but direct TLS serving is not implemented.");
        info!("⚠️  For production HTTPS, use a reverse proxy (nginx/Caddy/Traefik) in front of this server.");
        info!("⚠️  The server will run on HTTP and should be accessed through the reverse proxy.");
        info!("📖 See docs/SECURITY.md for reverse proxy configuration examples.");
    }
    
    // HTTP mode (default for development, or when TLS is handled by reverse proxy)
    let listener = tokio::net::TcpListener::bind(&addr).await?;
    if config.enable_tls {
        info!("Server listening on http://{} (TLS handled by reverse proxy)", addr);
    } else {
        info!("Server listening on http://{}", addr);
    }
    info!("Access the server at: http://localhost:{}", config.port);

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

fn create_cors_layer(config: &Config) -> tower_http::cors::CorsLayer {
    use tower_http::cors::CorsLayer;
    
    if config.allowed_origins.contains(&"*".to_string()) {
        // Development mode - allow all origins
        CorsLayer::permissive()
    } else {
        // Production mode - restrict to specific origins
        let origins: Vec<axum::http::HeaderValue> = config.allowed_origins
            .iter()
            .filter_map(|s| s.parse().ok())
            .collect();
        
        CorsLayer::new()
            .allow_origin(tower_http::cors::AllowOrigin::list(origins))
            .allow_methods([
                axum::http::Method::GET,
                axum::http::Method::POST,
                axum::http::Method::PUT,
                axum::http::Method::DELETE,
                axum::http::Method::OPTIONS,
            ])
            .allow_headers([
                axum::http::header::AUTHORIZATION,
                axum::http::header::CONTENT_TYPE,
            ])
            .allow_credentials(true)
    }
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
