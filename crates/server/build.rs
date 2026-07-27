use std::fs;
use std::path::Path;

fn main() {
    // Path to build number file (relative to workspace root)
    let build_number_file = Path::new("../..")
        .join(".build_number");

    // Read current build number
    let current_number = if build_number_file.exists() {
        fs::read_to_string(&build_number_file)
            .unwrap_or_else(|_| "0".to_string())
            .trim()
            .parse::<u64>()
            .unwrap_or(0)
    } else {
        0
    };

    // Increment build number
    let new_number = current_number + 1;

    // Write back the incremented number
    let _ = fs::write(&build_number_file, format!("{}\n", new_number));

    // Pass to compiler
    println!("cargo:rustc-env=BUILD_NUMBER={}", new_number);

    // Ensure rebuild on each invocation
    println!("cargo:rerun-if-changed=build.rs");
}
