use std::env;

#[derive(Clone)]
pub struct Config {
    pub database_url: String,
    pub redis_url: String,
    pub port: u16,
    pub jwt_secret: String,
    pub jwt_expiration: u64,
    pub allowed_origins: Vec<String>,
    pub enable_tls: bool,
    pub tls_cert_path: Option<String>,
    pub tls_key_path: Option<String>,
    pub rate_limit_requests: u32,
    pub rate_limit_window: u64,
}

impl Config {
    pub fn from_env() -> anyhow::Result<Self> {
        let allowed_origins = env::var("ALLOWED_ORIGINS")
            .unwrap_or_else(|_| "*".to_string())
            .split(',')
            .map(|s| s.trim().to_string())
            .collect();

        Ok(Self {
            database_url: env::var("DATABASE_URL")
                .unwrap_or_else(|_| "postgresql://debt_tracker:dev_password@localhost:5432/debt_tracker".to_string()),
            redis_url: env::var("REDIS_URL")
                .unwrap_or_else(|_| "redis://localhost:6379".to_string()),
            port: env::var("PORT")
                .unwrap_or_else(|_| "8000".to_string())
                .parse()
                .unwrap_or(8000),
            jwt_secret: env::var("JWT_SECRET")
                .unwrap_or_else(|_| "your-secret-key-change-in-production".to_string()),
            jwt_expiration: env::var("JWT_EXPIRATION")
                .unwrap_or_else(|_| "3600".to_string())
                .parse()
                .unwrap_or(3600),
            allowed_origins,
            enable_tls: env::var("ENABLE_TLS")
                .unwrap_or_else(|_| "false".to_string())
                .parse()
                .unwrap_or(false),
            tls_cert_path: env::var("TLS_CERT_PATH").ok(),
            tls_key_path: env::var("TLS_KEY_PATH").ok(),
            rate_limit_requests: env::var("RATE_LIMIT_REQUESTS")
                .unwrap_or_else(|_| "100".to_string())
                .parse()
                .unwrap_or(100),
            rate_limit_window: env::var("RATE_LIMIT_WINDOW")
                .unwrap_or_else(|_| "60".to_string())
                .parse()
                .unwrap_or(60),
        })
    }

    pub fn validate(&self) -> anyhow::Result<()> {
        // Check if we're in production mode
        let is_production = env::var("ENVIRONMENT")
            .unwrap_or_else(|_| "development".to_string())
            .to_lowercase() == "production";
        
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
            tracing::warn!("⚠️  JWT_SECRET is less than 32 characters. Use a stronger secret in production!");
        }

        // Validate TLS config if enabled
        if self.enable_tls {
            if self.tls_cert_path.is_none() || self.tls_key_path.is_none() {
                return Err(anyhow::anyhow!("TLS enabled but TLS_CERT_PATH or TLS_KEY_PATH not set"));
            }
        }

        // Validate database URL and check for TLS
        if should_warn && !self.database_url.contains("sslmode") {
            tracing::warn!("⚠️  Database URL does not specify sslmode. For production, use sslmode=require");
        } else if should_warn && self.database_url.contains("sslmode=disable") {
            tracing::warn!("⚠️  Database connection is using sslmode=disable. This is insecure for production!");
        }

        // Validate rate limiting settings
        if self.rate_limit_requests == 0 {
            return Err(anyhow::anyhow!("RATE_LIMIT_REQUESTS cannot be 0"));
        }
        if self.rate_limit_window == 0 {
            return Err(anyhow::anyhow!("RATE_LIMIT_WINDOW cannot be 0"));
        }

        // Validate CORS settings
        if should_warn && self.allowed_origins.contains(&"*".to_string()) {
            tracing::warn!("⚠️  CORS is set to allow all origins (*). This is insecure for production!");
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
        self.database_url.contains("sslmode=require") || 
        self.database_url.contains("sslmode=prefer") ||
        self.database_url.contains("sslmode=verify-full") ||
        self.database_url.contains("sslmode=verify-ca")
    }
}
