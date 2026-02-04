// When building with desktop on Linux, check for libxdo and give a clear error if missing.

fn main() {
    let is_desktop = std::env::var("CARGO_FEATURE_DESKTOP").is_ok();
    let is_linux = std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("linux");
    if is_desktop && is_linux {
        check_libxdo();
    }
}

fn check_libxdo() {
    // pkg-config is the cleanest check; libxdo may not have .pc, so also try ldconfig
    let found = std::process::Command::new("pkg-config")
        .args(["--exists", "libxdo"])
        .status()
        .map(|s| s.success())
        .unwrap_or_else(|_| {
            let out = std::process::Command::new("ldconfig")
                .args(["-p"])
                .output();
            out.map(|o| String::from_utf8_lossy(&o.stdout).contains("libxdo"))
                .unwrap_or(false)
        });

    if !found {
        eprintln!();
        eprintln!("  error: desktop build on Linux requires libxdo.");
        eprintln!();
        eprintln!("  Install the development package, then run again:");
        eprintln!("    Fedora/RHEL:   sudo dnf install libxdo-devel");
        eprintln!("    Debian/Ubuntu: sudo apt install libxdo-dev");
        eprintln!();
        eprintln!("  Then: cargo run --features desktop");
        eprintln!();
        std::process::exit(1);
    }
}
