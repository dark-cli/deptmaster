# Debitum Frontend (Dioxus)

Google-free frontend for Debitum, ported from the Flutter mobile app. Built with [Dioxus](https://dioxuslabs.com/) and Rust.

## Run (default: web – no system libs)

By default the app runs in the **browser** so you don’t need any native libraries (no libxdo, webkit, etc.):

```bash
# One-time: Dioxus CLI and wasm-bindgen (needed for dx serve)
cargo install dioxus-cli wasm-bindgen-cli

# Run dev server (opens in browser)
cargo run
```

If you see **"failed to find intrinsics to enable clone_ref"**, dx runs cargo from a temp dir and doesn't forward env. **Reliable fix (one-time):** wrap your system cargo so every build gets the wasm flags:

```bash
./install-cargo-wasm-wrapper.sh
```

Then run `dx serve` or `./serve.sh` as usual. To undo later: `mv ~/.cargo/bin/cargo.real ~/.cargo/bin/cargo`. Alternatively try `./serve.sh` (prepends a cargo wrapper to PATH; only works if dx looks up `cargo` via PATH). If you see **"Failed to write executable"** or **"No such file or directory"**, ensure `wasm-bindgen-cli` is on your `PATH`.

## Run as native desktop (optional)

For a native window (e.g. phone-sized 390×844), use the desktop feature. On Linux this needs extra system libraries:

```bash
# Fedora: install deps
sudo dnf install webkit2gtk4.1-devel libsoup3-devel javascriptcoregtk4.1-devel libxdo-devel

# Run desktop app
cargo run --features desktop
```

**If you see a Gdk “Protocol error” or other display glitches on Wayland**, run with X11:

```bash
GDK_BACKEND=x11 cargo run --features desktop
```

On Debian/Ubuntu:

```bash
sudo apt install libwebkit2gtk-4.1-dev libsoup-3.0-dev libjavascriptcoregtk-4.1-dev libxdo-dev
cargo run --features desktop
```

### macOS / Windows

Dioxus desktop uses the system WebView; no extra system packages are typically needed.

## Project layout

- `src/models/` – Contact, Transaction, Event, Wallet (ported from Flutter)
- `src/state_builder.rs` – Pure rebuild of app state from events (syncing/rebuild logic)
- `src/event_store.rs` – In-memory event store (replaces Hive)
- `src/theme.rs` – Colors and spacing (Material 3–style)
- `src/widgets/` – GradientBackground, GradientCard
- `src/screens/` – Login, Backend setup, Home (Dashboard, Contacts, Transactions)
- `tests/` – State builder and event store tests (run with `cargo test`)

## Tests (backend syncing / rebuild logic)

Run the app’s sync/rebuild tests (no mobile, no emulator):

```bash
cargo test -- --test-threads=1
```

(Single-threaded so the in-memory event store is not shared across tests.)

These tests cover:

- `state_builder` – Building state from events (contacts, transactions, balances, UNDO)
- `event_store` – Append, list, filter events

## Backend

Point the app at your Debitum API (Backend setup screen or env). Default: `http://127.0.0.1:8000`.

## License

Same as the main Debitum project.
