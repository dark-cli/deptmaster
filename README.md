# Debitum

**A debt tracker you run yourself.** Keep track of who owes whom — without handing your friends, your contacts, or your spending history to a cloud service.

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)

---

## What is it?

Debitum is an app for tracking debts between people. The classic use cases:

- **Roommates** splitting rent, groceries, utilities
- **Friends** keeping a running tab on who paid for dinners and trips
- **Families** managing shared expenses
- **Small businesses** tracking invoices and IOUs

You add people, log who owes what, and the app keeps the running balances. Standard stuff.

What makes Debitum different: **you host it yourself**, on your own server. Your data lives in your database. The mobile app talks directly to your server — no middleman, no analytics, no ads, no "free tier with usage limits."

---

## Features

### For users

- **Multi-currency** — track debts in any currency, no conversion gymnastics
- **Shared books with multiple people** — give a roommate access to the apartment book, keep your business book separate. Each book has its own members and permissions.
- **Granular permissions** — owners can do everything. Members can be granted view-only, edit-only, or full access to specific groups of contacts. Permissions can also be denied (e.g. "everyone can see contacts, except this group").
- **5-second undo** — accidentally deleted a transaction? Tap undo within 5 seconds.
- **Real-time updates** — when someone else makes a change, your app sees it within seconds (without polling).
- **Works offline** — the app keeps working when you have no signal. Changes sync back when you're online again.
- **Full history** — every change is logged forever. You can always see what happened, when, and who did it.

### For self-hosters

- **One Rust binary + one Postgres database.** Backups are `pg_dump`. Logs are stdout. No Redis, no message queue, no Kubernetes cluster.
- **Tiny resource footprint.** Idle memory in single-digit MBs.
- **Open source under GPLv3.** Fork it, audit it, change it.

### For developers

The whole stack is in Rust — both the server and the logic powering the mobile app. The mobile app's UI is Flutter, but everything underneath (data storage, sync, permission checks, business rules) is Rust code shared with the server. Same code, same behavior. The mobile app can't "drift" from what the server expects, because they're literally running the same functions.

---

## Try it

You need [Docker](https://docs.docker.com/get-docker/) and [Rust](https://rustup.rs/) installed. Optionally [Flutter](https://docs.flutter.dev/get-started/install) if you want to run the mobile app.

```bash
# 1. Get the code
git clone https://github.com/<your-fork>/deptmaster.git
cd deptmaster

# 2. Start Postgres + run migrations (one-time setup)
./scripts/manage.sh setup-db

# 3. Start the server
./scripts/manage.sh start-server
# server now listening on http://localhost:8000

# 4. (Optional) Build and run the mobile app
./scripts/manage.sh run-flutter-app linux   # or: android
```

That's it. Open the mobile app, sign up, you're in.

For production: put the server binary behind nginx / Caddy / Traefik, enable TLS at your proxy, point your phone at it. The server speaks HTTP and WebSocket over the same port.

---

## How it works (the short version)

Debitum uses an approach called **event sourcing**. Instead of storing "Alice currently owes Bob $30," the app stores the history of how we got there:

```
Day 1: Alice borrowed $50 from Bob       ← stored as an event
Day 2: Alice paid Bob $20                ← stored as an event
Today: balance is Alice owes Bob $30     ← computed from events
```

The events never change. The current balances are computed from the events whenever you ask. This is what gives Debitum its undo button, its complete audit trail, and its ability to sync cleanly across multiple devices without ever losing or duplicating a change.

**Behavior is consistent between the server and the mobile app** because they both use the exact same code to interpret events, check permissions, and compute balances. The server (Postgres) is the source of truth; the mobile app (local SQLite) is a fast cache. When you make a change, the app applies it locally first (so the UI is instant), then pushes it to the server. The server may reject it — for example if you don't have permission — and the app reflects that back to you.

For a deeper dive, see the [documentation](#documentation) below.

---

## Status

**Not 1.0 yet.** Core functionality works:

- Server (Rust + Postgres) — stable, 63/63 tests pass
- Mobile sync engine (Rust under Flutter) — stable, 47/47 integration tests pass
- Permission system, multi-wallet, real-time sync, undo, offline-first — all working
- Mobile UI — Flutter app works on Android + Linux desktop; iOS not tested yet
- Web frontend — planned

If you find a bug, please open an issue.

---

## Documentation

The `vault/` directory holds the full documentation. It's written for both newcomers and contributors.

Recommended reading order:

1. [vault/00-getting-started/](vault/00-getting-started/) — what the system does and how it's structured
2. [vault/01-events/](vault/01-events/) — events, the core concept
3. [vault/02-projections/](vault/02-projections/) — how the current state is computed
4. [vault/04-permissions-and-undo/](vault/04-permissions-and-undo/) — the permission model
5. [vault/06-client/](vault/06-client/) — how the mobile app works
6. [vault/99-reference/01-glossary.md](vault/99-reference/01-glossary.md) — terms

---

## Contributing

Bug reports, feature ideas, and pull requests welcome. Before sending a substantial PR, please open an issue first so we can discuss approach.

Running the test suite:

```bash
cargo nextest run --workspace                # everything
./scripts/manage.sh test-integration         # client integration tests (needs a running server)
```

Code style is enforced by `cargo fmt` and `cargo clippy`. Both must be clean before a PR is merged.

---

## License

[GPLv3](LICENSE).

You can run, fork, and modify Debitum freely, including commercially. If you distribute a modified version, you must release your modifications under GPLv3 too. (This is to keep the project — and any fork of it — free for everyone.)
