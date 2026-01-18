# Pure Rust Backend Implementation Guide

This document provides implementation details for the pure Rust backend, including API server and background tasks.

## Architecture Overview

The backend is a single Rust application that runs:
1. **API Server** - REST API using Axum
2. **Background Tasks** - Scheduled jobs using Tokio and cron scheduler
3. **Event Processing** - Event sourcing and projection updates
4. **Sync Engine** - Multi-device synchronization

All in one process, one binary, one container.

## Project Structure

```
backend/rust-api/
├── Cargo.toml
├── Dockerfile
├── src/
│   ├── main.rs                 # Entry point (API + background tasks)
│   ├── config.rs               # Configuration management
│   ├── handlers/               # API route handlers
│   │   ├── mod.rs
│   │   ├── auth.rs
│   │   ├── contacts.rs
│   │   ├── transactions.rs
│   │   ├── sync.rs
│   │   └── reminders.rs
│   ├── models/                 # Data models
│   │   ├── mod.rs
│   │   ├── user.rs
│   │   ├── contact.rs
│   │   ├── transaction.rs
│   │   └── event.rs
│   ├── services/               # Business logic
│   │   ├── mod.rs
│   │   ├── auth_service.rs
│   │   ├── sync_service.rs
│   │   └── event_service.rs
│   ├── background/            # Background tasks
│   │   ├── mod.rs
│   │   ├── scheduler.rs        # Task scheduler
│   │   ├── notifications.rs    # Email/push notifications
│   │   ├── reminders.rs        # Reminder processing
│   │   └── cleanup.rs          # Maintenance tasks
│   ├── database/              # Database layer
│   │   ├── mod.rs
│   │   ├── pool.rs             # Connection pool
│   │   ├── events.rs           # Event store queries
│   │   └── projections.rs      # Projection queries
│   └── utils/                  # Utilities
│       ├── mod.rs
│       ├── encryption.rs
│       └── validation.rs
└── tests/
    ├── integration/
    └── unit/
```

## Cargo.toml

```toml
[package]
name = "debitum-api"
version = "0.1.0"
edition = "2021"

[dependencies]
# Web framework
axum = "0.7"
tokio = { version = "1", features = ["full"] }
tower = "0.4"
tower-http = { version = "0.5", features = ["cors", "trace", "compression"] }

# Database
sqlx = { version = "0.7", features = [
    "runtime-tokio-native-tls",
    "postgres",
    "chrono",
    "uuid",
    "json",
] }

# Serialization
serde = { version = "1", features = ["derive"] }
serde_json = "1"

# Async runtime
futures = "0.3"

# Background tasks
tokio-cron-scheduler = "0.9"

# Email
lettre = "0.11"

# HTTP client
reqwest = { version = "0.11", features = ["json"] }

# Configuration
config = "0.14"
dotenv = "0.15"

# Logging
tracing = "0.1"
tracing-subscriber = { version = "0.3", features = ["env-filter", "json"] }

# Authentication
jsonwebtoken = "9"
bcrypt = "0.15"
uuid = { version = "1", features = ["v4", "serde"] }

# Time handling
chrono = { version = "0.4", features = ["serde"] }

# Error handling
anyhow = "1"
thiserror = "1"

# Redis (optional, for distributed task queue)
redis = { version = "0.24", features = ["tokio-comp", "connection-manager"] }

# WebSocket
tokio-tungstenite = "0.21"
axum-extra = { version = "0.9", features = ["typed-header"] }

[dev-dependencies]
tokio-test = "0.4"
mockall = "0.12"

[profile.release]
opt-level = 3
lto = true
codegen-units = 1
```

## Main Application

```rust
// src/main.rs
use axum::{
    Router,
    routing::{get, post},
    extract::State,
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

use config::Config;
use database::DatabasePool;

#[derive(Clone)]
pub struct AppState {
    pub db_pool: DatabasePool,
    pub config: Arc<Config>,
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // Load environment variables
    dotenv::dotenv().ok();

    // Initialize tracing
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "debitum_api=debug,tower_http=debug".into())
        )
        .init();

    info!("Starting Debitum API server...");

    // Load configuration
    let config = Arc::new(Config::from_env()?);
    info!("Configuration loaded");

    // Initialize database pool
    let db_pool = DatabasePool::new(&config.database_url).await?;
    info!("Database connection pool created");

    // Initialize background scheduler
    let scheduler = Arc::new(
        background::scheduler::BackgroundScheduler::new(
            db_pool.clone(),
            config.clone(),
        ).await?
    );

    // Start background tasks
    scheduler.start().await?;
    info!("Background scheduler started");

    // Build application state
    let app_state = AppState {
        db_pool: db_pool.clone(),
        config: config.clone(),
    };

    // Build API routes
    let app = Router::new()
        .route("/health", get(health_check))
        .route("/api/auth/register", post(handlers::auth::register))
        .route("/api/auth/login", post(handlers::auth::login))
        .route("/api/contacts", get(handlers::contacts::list))
        .route("/api/contacts", post(handlers::contacts::create))
        .route("/api/contacts/:id", get(handlers::contacts::get))
        .route("/api/contacts/:id", post(handlers::contacts::update))
        .route("/api/contacts/:id", axum::routing::delete(handlers::contacts::delete))
        .route("/api/transactions", get(handlers::transactions::list))
        .route("/api/transactions", post(handlers::transactions::create))
        .route("/api/sync/push", post(handlers::sync::push))
        .route("/api/sync/pull", post(handlers::sync::pull))
        .route("/api/reminders", get(handlers::reminders::list))
        .route("/api/reminders", post(handlers::reminders::create))
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
```

## Background Scheduler

```rust
// src/background/scheduler.rs
use tokio_cron_scheduler::{Job, JobScheduler};
use tracing::{info, error};
use std::sync::Arc;
use crate::database::DatabasePool;
use crate::config::Config;

pub struct BackgroundScheduler {
    scheduler: JobScheduler,
    db_pool: DatabasePool,
    config: Arc<Config>,
}

impl BackgroundScheduler {
    pub async fn new(
        db_pool: DatabasePool,
        config: Arc<Config>,
    ) -> anyhow::Result<Self> {
        let scheduler = JobScheduler::new().await?;

        Ok(Self {
            scheduler,
            db_pool,
            config,
        })
    }

    pub async fn start(&self) -> anyhow::Result<()> {
        let db_pool = self.db_pool.clone();
        let config = self.config.clone();

        // Check and send reminders every 5 minutes
        self.scheduler
            .add(
                Job::new_async("0 */5 * * * *", move |_uuid, _l| {
                    let db_pool = db_pool.clone();
                    Box::pin(async move {
                        info!("Running reminder check job");
                        if let Err(e) = crate::background::reminders::check_and_send_reminders(&db_pool).await {
                            error!("Reminder check failed: {:?}", e);
                        }
                    })
                })?
            )
            .await?;

        // Daily cleanup at 2 AM
        let db_pool2 = self.db_pool.clone();
        self.scheduler
            .add(
                Job::new_async("0 0 2 * * *", move |_uuid, _l| {
                    let db_pool = db_pool2.clone();
                    Box::pin(async move {
                        info!("Running daily cleanup job");
                        if let Err(e) = crate::background::cleanup::run_cleanup(&db_pool).await {
                            error!("Cleanup failed: {:?}", e);
                        }
                    })
                })?
            )
            .await?;

        self.scheduler.start().await?;
        info!("Background scheduler started");

        Ok(())
    }

    pub async fn shutdown(&self) {
        self.scheduler.shutdown().await;
        info!("Background scheduler stopped");
    }
}
```

## Benefits of Pure Rust

1. **Single Language Stack**: Easier to maintain, no context switching
2. **Performance**: Zero-cost abstractions, no Python overhead
3. **Memory Safety**: Compile-time guarantees, fewer runtime errors
4. **Resource Efficiency**: Lower memory usage, faster execution
5. **Type Safety**: Compile-time checked, catches errors early
6. **Deployment Simplicity**: One binary, one container, easier scaling
7. **Shared Code**: Background tasks use same models/services as API
8. **No GIL**: Unlike Python, Rust has no Global Interpreter Lock
9. **Better Concurrency**: Tokio provides excellent async/await support
10. **Smaller Docker Images**: Single binary is much smaller than Python + dependencies

## Deployment

### Dockerfile

```dockerfile
# Build stage
FROM rust:1.75 as builder

WORKDIR /app

# Copy dependency files
COPY Cargo.toml Cargo.lock ./
COPY src ./src

# Build release binary
RUN cargo build --release

# Runtime stage
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y \
    ca-certificates \
    libssl3 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy binary from builder
COPY --from=builder /app/target/release/debitum-api /app/debitum-api

# Run the application
CMD ["./debitum-api"]
```

### Docker Compose

```yaml
services:
  api:
    build:
      context: ./backend/rust-api
      dockerfile: Dockerfile
    container_name: debitum_api
    environment:
      DATABASE_URL: postgresql://debitum:password@postgres:5432/debitum_prod
      REDIS_URL: redis://redis:6379
      PORT: 8000
      RUST_LOG: info
    ports:
      - "8000:8000"
    depends_on:
      - postgres
      - redis
    restart: unless-stopped
```

## Testing

```rust
// tests/integration/api_test.rs
use axum::http::StatusCode;
use axum_test::TestServer;

#[tokio::test]
async fn test_health_check() {
    let app = create_test_app().await;
    let server = TestServer::new(app).unwrap();

    let response = server.get("/health").await;

    response.assert_status(StatusCode::OK);
    response.assert_text("OK");
}
```

## Monitoring

Background tasks log their execution:
- Success: `info!("Reminder check completed: {} reminders sent", count)`
- Errors: `error!("Reminder check failed: {:?}", e)`

All logs go through tracing, which can be configured for:
- JSON output (for log aggregation)
- Structured logging
- Log levels per module

## Performance Considerations

1. **Connection Pooling**: Use SQLx connection pool (default: 10 connections)
2. **Async Everything**: All I/O is async using Tokio
3. **Background Task Isolation**: Tasks run in separate Tokio tasks
4. **Resource Limits**: Set appropriate limits in Docker/Kubernetes
5. **Monitoring**: Use metrics (Prometheus) to monitor task execution

## Next Steps

1. Implement event sourcing handlers
2. Add WebSocket support for real-time sync
3. Implement full-text search
4. Add metrics endpoint
5. Add integration tests
