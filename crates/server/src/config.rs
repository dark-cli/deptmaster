use std::env;

#[derive(Clone)]
pub struct Config {
    pub database_url: String,
    pub port: u16,
    pub jwt_secret: String,
    /// Access-token (JWT) lifetime in seconds. Short by design — clients
    /// trade their refresh token at `/api/auth/refresh` for a fresh
    /// access+refresh pair whenever the access token nears or hits expiry.
    pub jwt_expiration: u64,
    /// Refresh-token lifetime in seconds. Refresh tokens are rotated on
    /// every use (each refresh issues a new one and revokes the old),
    /// so the practical "stay logged in" window is the gap between any
    /// two app opens, not this number — but no refresh older than this
    /// is ever accepted.
    pub refresh_token_expiration: u64,
    pub allowed_origins: Vec<String>,
    pub enable_tls: bool,
    pub tls_cert_path: Option<String>,
    pub tls_key_path: Option<String>,
    pub rate_limit_requests: u32,
    pub rate_limit_window: u64,
    pub event_rebuild_batch_size: usize,
    pub max_snapshots_per_wallet: i64,
    pub snapshot_interval: i64,
}

impl Config {
    pub fn from_env() -> anyhow::Result<Self> {
        let allowed_origins = env::var("ALLOWED_ORIGINS")
            .unwrap_or_else(|_| "*".to_string())
            .split(',')
            .map(|s| s.trim().to_string())
            .collect();

        Ok(Self {
            database_url: env::var("DATABASE_URL").unwrap_or_else(|_| {
                "postgresql://debt_tracker:dev_password@localhost:5432/debt_tracker".to_string()
            }),
            port: env::var("PORT")
                .unwrap_or_else(|_| "8000".to_string())
                .parse()
                .unwrap_or(8000),
            jwt_secret: env::var("JWT_SECRET")
                .unwrap_or_else(|_| "your-secret-key-change-in-production".to_string()),
            // Default 15 minutes. Short access-token lifetime is the
            // whole point of the refresh-token pattern — a leaked token
            // is only useful for at most this many seconds.
            jwt_expiration: env::var("JWT_EXPIRATION")
                .unwrap_or_else(|_| "900".to_string())
                .parse()
                .unwrap_or(900),
            // Default 30 days.
            refresh_token_expiration: env::var("REFRESH_TOKEN_EXPIRATION")
                .unwrap_or_else(|_| "2592000".to_string())
                .parse()
                .unwrap_or(2592000),
            allowed_origins,
            enable_tls: env::var("ENABLE_TLS")
                .unwrap_or_else(|_| "false".to_string())
                .parse()
                .unwrap_or(false),
            tls_cert_path: env::var("TLS_CERT_PATH").ok(),
            tls_key_path: env::var("TLS_KEY_PATH").ok(),
            rate_limit_requests: env::var("RATE_LIMIT_REQUESTS")
                .unwrap_or_else(|_| "0".to_string())
                .parse()
                .unwrap_or(0),
            rate_limit_window: env::var("RATE_LIMIT_WINDOW")
                .unwrap_or_else(|_| "60".to_string())
                .parse()
                .unwrap_or(60),
            event_rebuild_batch_size: env::var("EVENT_REBUILD_BATCH_SIZE")
                .unwrap_or_else(|_| "1000".to_string())
                .parse()
                .unwrap_or(1000),
            max_snapshots_per_wallet: env::var("MAX_SNAPSHOTS_PER_WALLET")
                .unwrap_or_else(|_| "5".to_string())
                .parse()
                .unwrap_or(5),
            snapshot_interval: env::var("SNAPSHOT_INTERVAL")
                .unwrap_or_else(|_| "10".to_string())
                .parse()
                .unwrap_or(10),
        })
    }

    pub fn validate(&self) -> anyhow::Result<()> {
        // Check if we're in production mode
        let is_production = env::var("ENVIRONMENT")
            .unwrap_or_else(|_| "development".to_string())
            .to_lowercase()
            == "production";

        let show_dev_warnings = env::var("SHOW_DEV_WARNINGS")
            .unwrap_or_else(|_| "false".to_string())
            .parse()
            .unwrap_or(false);

        // Only show warnings in production or if explicitly enabled
        let should_warn = is_production || show_dev_warnings;

        // Warn if using default JWT secret
        if should_warn && self.jwt_secret == "your-secret-key-change-in-production" {
            tracing::warn!("⚠️  Using default JWT_SECRET! Change this in production!");
        }

        // Validate JWT secret strength
        if should_warn && self.jwt_secret.len() < 32 {
            tracing::warn!(
                "⚠️  JWT_SECRET is less than 32 characters. Use a stronger secret in production!"
            );
        }

        // Validate TLS config if enabled
        if self.enable_tls && (self.tls_cert_path.is_none() || self.tls_key_path.is_none()) {
            return Err(anyhow::anyhow!(
                "TLS enabled but TLS_CERT_PATH or TLS_KEY_PATH not set"
            ));
        }

        // Validate database URL and check for TLS
        if should_warn && !self.database_url.contains("sslmode") {
            tracing::warn!(
                "⚠️  Database URL does not specify sslmode. For production, use sslmode=require"
            );
        } else if should_warn && self.database_url.contains("sslmode=disable") {
            tracing::warn!("⚠️  Database connection is using sslmode=disable. This is insecure for production!");
        }

        // Validate rate limiting settings (0 = disabled, for local dev/testing)
        if self.rate_limit_requests > 0 && self.rate_limit_window == 0 {
            return Err(anyhow::anyhow!(
                "RATE_LIMIT_WINDOW must be > 0 when rate limiting is enabled"
            ));
        }

        // Validate CORS settings
        if should_warn && self.allowed_origins.contains(&"*".to_string()) {
            tracing::warn!(
                "⚠️  CORS is set to allow all origins (*). This is insecure for production!"
            );
        }

        // Validate JWT expiration
        if should_warn && self.jwt_expiration < 60 {
            tracing::warn!("⚠️  JWT_EXPIRATION is less than 60 seconds. This may cause frequent re-authentication.");
        }
        if should_warn && self.jwt_expiration > 86400 {
            tracing::warn!("⚠️  JWT_EXPIRATION is more than 24 hours. Consider shorter expiration for better security.");
        }

        Ok(())
    }

    // Check if database should use TLS
    pub fn database_requires_tls(&self) -> bool {
        // Check if DATABASE_URL contains sslmode=require or sslmode=prefer
        self.database_url.contains("sslmode=require")
            || self.database_url.contains("sslmode=prefer")
            || self.database_url.contains("sslmode=verify-full")
            || self.database_url.contains("sslmode=verify-ca")
    }
}
