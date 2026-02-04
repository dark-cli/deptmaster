pub mod auth;
pub mod security_headers;
pub mod rate_limit;
pub mod wallet_context;

// Re-export for use in handlers and other modules
// Note: These are imported directly from submodules in most places,
// but kept here for convenience and potential future use
#[allow(unused_imports)]
pub use auth::{Claims, AuthUser};
#[allow(unused_imports)]
pub use rate_limit::RateLimiter;
#[allow(unused_imports)]
pub use wallet_context::{WalletContext, get_wallet_context, require_wallet_role};