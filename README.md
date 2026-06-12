# Debitum

A self-hosted debt tracker. You run the server, your devices sync to it. Built in Rust with a Flutter mobile UI.

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)

---

## What it does

- Track debts between people in any currency
- Organize debts into separate books ("wallets"), each with its own members and permissions
- Multi-user wallets with a fine-grained permission system (per-action, per-group of contacts, allow/deny)
- Real-time sync across devices over WebSocket
- 5-second undo on create / update / delete
- Works offline; syncs back when you reconnect
- Complete history of every change

---

## Install

You need Docker and Rust. Flutter is only needed if you want to build the mobile app.

```bash
git clone <your-fork-of-this-repo>
cd deptmaster

# Start Postgres + run migrations
./scripts/manage.sh setup-db

# Start the server (defaults to http://localhost:8000)
./scripts/manage.sh start-server

# Build and run the mobile app (optional)
./scripts/manage.sh run-flutter-app linux   # or: android
```

For production, put the server binary behind a reverse proxy (Caddy, nginx, Traefik) with TLS. Server is a single static binary; backups are `pg_dump`.

---

## How it works

### Event sourcing

The database stores the history of every change as immutable events ("Alice borrowed $50 from Bob", "Alice paid Bob $20"), not the current balance. Balances are computed by replaying the events. This is what gives Debitum its undo, its audit trail, and clean multi-device sync.

### Shared Rust between server and client

The interesting part is that the server (Rust + Postgres) and the mobile-app's data layer (Rust + SQLite, exposed to Flutter via FFI) **import the same Rust crates** for:

- the event types and how to apply them (`crates/core/applier`)
- the permission rules (`crates/core/resolver`)
- the snapshot / rebuild logic (`crates/core/snapshots`)

Each side implements three storage adapter traits against its own database engine, but the rules above those traits are written once. The server is authoritative — the client's local permission checks are UX hints (greying out buttons), every write still goes through the server.

---

## Repository layout

```
crates/
├── core/             shared Rust (no storage engine)
│   ├── domain        event types, IDs
│   ├── applier       event-application dispatch
│   ├── resolver      permission resolution
│   └── snapshots     snapshot rotation
├── server            Postgres backend (sqlx + axum)
└── client            client-side Rust for the Flutter app (rusqlite + FRB)

mobile/               Flutter UI (Dart)
scripts/              manage.sh, FRB codegen, setup
vault/                full documentation
docker-compose.yml    Postgres
```

---

## Testing

```bash
cargo nextest run --workspace                # unit + repository tests
./scripts/manage.sh test-integration         # client integration tests (needs a running server)
```

Current status: 47/47 client integration tests + 63/63 server tests pass.

---

## Documentation

Full docs live in [`vault/`](vault/). Start with [`vault/00-getting-started/`](vault/00-getting-started/). The [glossary](vault/99-reference/01-glossary.md) defines all internal terms.

---

## Status

Pre-1.0. Server and client sync engine are stable. The Flutter UI runs on Android and Linux desktop; iOS is not tested yet. A web frontend is planned.

---

## License

[GPLv3](LICENSE). Free to use, modify, and distribute under the same license.
