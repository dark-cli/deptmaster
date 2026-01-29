// Security headers middleware
// Adds security headers like HSTS, CSP, X-Frame-Options, etc.

use axum::{
    extract::Request,
    middleware::Next,
    response::Response,
};
use axum::http::HeaderValue;

pub async fn security_headers_middleware(
    req: Request,
    next: Next,
) -> Response {
    let mut response = next.run(req).await;
    let headers = response.headers_mut();
    
    // X-Content-Type-Options: Prevent MIME type sniffing
    headers.insert(
        axum::http::HeaderName::from_static("x-content-type-options"),
        HeaderValue::from_static("nosniff")
    );
    
    // X-Frame-Options: Prevent clickjacking
    headers.insert(
        axum::http::HeaderName::from_static("x-frame-options"),
        HeaderValue::from_static("DENY")
    );
    
    // X-XSS-Protection: Enable XSS filter (legacy, but still useful)
    headers.insert(
        axum::http::HeaderName::from_static("x-xss-protection"),
        HeaderValue::from_static("1; mode=block")
    );
    
    // Content-Security-Policy: Restrict resource loading
    // Allow same-origin and inline scripts/styles for admin page
    headers.insert(
        axum::http::HeaderName::from_static("content-security-policy"),
        HeaderValue::from_static(
            "default-src 'self'; script-src 'self' 'unsafe-inline' https://cdn.jsdelivr.net; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self' https://cdn.jsdelivr.net;"
        )
    );
    
    // Referrer-Policy: Control referrer information
    headers.insert(
        axum::http::HeaderName::from_static("referrer-policy"),
        HeaderValue::from_static("strict-origin-when-cross-origin")
    );
    
    // Permissions-Policy: Restrict browser features
    headers.insert(
        axum::http::HeaderName::from_static("permissions-policy"),
        HeaderValue::from_static("geolocation=(), microphone=(), camera=()")
    );
    
    // Note: Strict-Transport-Security (HSTS) should only be added when HTTPS is enabled
    // This should be done conditionally based on config, but for now we'll skip it
    // to avoid issues in development
    
    response
}
