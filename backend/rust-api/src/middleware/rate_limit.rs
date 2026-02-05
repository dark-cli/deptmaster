use axum::{
    extract::{Request, State},
    http::StatusCode,
    middleware::Next,
    response::Response,
};
use std::{
    collections::HashMap,
    sync::Arc,
    time::{Duration, Instant},
};
use tokio::sync::RwLock;

#[derive(Clone)]
struct RateLimitEntry {
    count: u32,
    reset_at: Instant,
}

#[derive(Clone)]
pub struct RateLimiter {
    // Map of IP address -> rate limit entry
    limits: Arc<RwLock<HashMap<String, RateLimitEntry>>>,
    max_requests: u32,
    window_seconds: u64,
    // Separate rate limiter for authenticated users (higher limits)
    auth_limits: Arc<RwLock<HashMap<String, RateLimitEntry>>>,
    auth_max_requests: u32,
}

impl RateLimiter {
    pub fn new(max_requests: u32, window_seconds: u64) -> Self {
        Self {
            limits: Arc::new(RwLock::new(HashMap::new())),
            max_requests,
            window_seconds,
            auth_limits: Arc::new(RwLock::new(HashMap::new())),
            auth_max_requests: max_requests.saturating_mul(5), // Authenticated users get 5x the limit; 0 when disabled
        }
    }

    /// When 0, rate limiting is disabled (useful for local dev/testing).
    pub fn is_disabled(&self) -> bool {
        self.max_requests == 0
    }
    
    pub async fn check_limit_auth(&self, key: &str) -> Result<(), StatusCode> {
        let mut limits = self.auth_limits.write().await;
        let now = Instant::now();

        // Clean up old entries periodically
        if limits.len() > 10000 {
            limits.retain(|_, entry| entry.reset_at > now);
        }

        let entry = limits.get_mut(key);

        match entry {
            Some(entry) => {
                if entry.reset_at <= now {
                    entry.count = 1;
                    entry.reset_at = now + Duration::from_secs(self.window_seconds);
                    return Ok(());
                }

                if entry.count >= self.auth_max_requests {
                    return Err(StatusCode::TOO_MANY_REQUESTS);
                }

                entry.count += 1;
                Ok(())
            }
            None => {
                limits.insert(
                    key.to_string(),
                    RateLimitEntry {
                        count: 1,
                        reset_at: now + Duration::from_secs(self.window_seconds),
                    },
                );
                Ok(())
            }
        }
    }

    pub async fn check_limit(&self, key: &str) -> Result<(), StatusCode> {
        let mut limits = self.limits.write().await;
        let now = Instant::now();

        // Clean up old entries periodically (simple cleanup)
        if limits.len() > 10000 {
            limits.retain(|_, entry| entry.reset_at > now);
        }

        let entry = limits.get_mut(key);

        match entry {
            Some(entry) => {
                // Check if window has expired
                if entry.reset_at <= now {
                    // Reset the window
                    entry.count = 1;
                    entry.reset_at = now + Duration::from_secs(self.window_seconds);
                    return Ok(());
                }

                // Check if limit exceeded
                if entry.count >= self.max_requests {
                    return Err(StatusCode::TOO_MANY_REQUESTS);
                }

                // Increment count
                entry.count += 1;
                Ok(())
            }
            None => {
                // First request from this IP
                limits.insert(
                    key.to_string(),
                    RateLimitEntry {
                        count: 1,
                        reset_at: now + Duration::from_secs(self.window_seconds),
                    },
                );
                Ok(())
            }
        }
    }
}

// Extract IP address from request
fn extract_ip(req: &Request) -> String {
    // Try to get real IP from X-Forwarded-For or X-Real-IP headers (for reverse proxy)
    if let Some(forwarded_for) = req.headers().get("x-forwarded-for") {
        if let Ok(ip) = forwarded_for.to_str() {
            // Take the first IP if there are multiple
            return ip.split(',').next().unwrap_or("unknown").trim().to_string();
        }
    }

    if let Some(real_ip) = req.headers().get("x-real-ip") {
        if let Ok(ip) = real_ip.to_str() {
            return ip.to_string();
        }
    }

    // Fallback to connection info (if available)
    // For now, use a default since we don't have direct access to connection info
    "unknown".to_string()
}

pub async fn rate_limit_middleware(
    State(rate_limiter): State<RateLimiter>,
    req: Request,
    next: Next,
) -> Result<Response, StatusCode> {
    if rate_limiter.is_disabled() {
        return Ok(next.run(req).await);
    }
    let path = req.uri().path();
    
    // Skip rate limiting for health checks, WebSocket upgrades, and static admin page
    // The admin page is static HTML and shouldn't be rate limited
    if path == "/health" || path == "/ws" || path == "/admin" {
        return Ok(next.run(req).await);
    }
    
    // Extract IP address
    let ip = extract_ip(&req);
    
    // For authenticated requests, use a more lenient rate limit
    // Check if request has Authorization header (authenticated user)
    let is_authenticated = req.headers().get("authorization").is_some();
    
    // Use different rate limits: authenticated users get higher limits
    // This prevents legitimate users from hitting limits while still protecting against abuse
    if is_authenticated {
        // Authenticated users: use higher limits (5x default)
        rate_limiter.check_limit_auth(&ip).await?;
    } else {
        // Unauthenticated requests: use default rate limit
        rate_limiter.check_limit(&ip).await?;
    }

    // Continue with request
    Ok(next.run(req).await)
}
