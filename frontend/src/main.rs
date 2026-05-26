//! Debitum frontend - Dioxus app (Google-free).
//! Default: web (cargo run). Desktop: cargo run --features desktop.

#[cfg(feature = "desktop")]
fn main() {
    use dioxus::prelude::*;
    use debitum_frontend::app::App;
    launch(App);
}

#[cfg(all(feature = "web", not(feature = "desktop")))]
fn main() {
    // Force wasm build without reference-types so wasm-bindgen doesn't fail with
    // "failed to find intrinsics to enable clone_ref" (Rust 1.82+ default).
    // Run via shell so RUSTFLAGS is set in the same process as dx (dx may not
    // forward env to its cargo child when it spawns the build).
    let rustflags = std::env::var("RUSTFLAGS").unwrap_or_default();
    let rustflags = if rustflags.is_empty() {
        "-C target-feature=-reference-types".to_string()
    } else {
        format!("{} -C target-feature=-reference-types", rustflags)
    };
    let status = std::process::Command::new("sh")
        .args(["-c", &format!("export RUSTFLAGS='{}'; exec dx serve", rustflags.replace('\'', "'\"'\"'"))])
        .status();
    match status {
        Ok(s) => std::process::exit(s.code().unwrap_or(1)),
        Err(e) => {
            eprintln!("Could not run 'dx serve': {}", e);
            eprintln!("Install the Dioxus CLI: cargo install dioxus-cli");
            eprintln!("Or run directly: RUSTFLAGS='-C target-feature=-reference-types' dx serve");
            std::process::exit(1);
        }
    }
}
