# Debitum

Self-hostable debt tracker. Built end-to-end in Rust — server and client share the same event-application code, the same permission resolver, the same snapshot logic. One rulebook, two engines.

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)

---

## Why Debitum

**Most debt trackers are a hosted SaaS reading your contacts and spending habits.** Debitum is the opposite: you run the server, you own the database, the mobile app talks directly to it. No analytics SDK, no third-party data brokers, no upsells. GPL-licensed.

**Most apps drift between client and server.** When the server says you can edit a contact but the client thinks you can't, that's a class of bug we structurally can't have — both sides import the same `applier`, `resolver`, and `snapshots` Rust crates and call the same functions. Identical rules, two storage engines.

**Most apps lose your edits when the network blinks.** Debitum is offline-first: every change is an immutable event, queued in local SQLite, pushed to the server when reachable. The server is the source of truth; the client is a fast local cache. Undo is built in.

---

## What it does

- **Track debts** between people and groups, multi-currency built in
- **Multi-wallet** — separate debt books with separate members and permissions (housemates, business, family — each isolated)
- **Multi-user wallets** with a 3-state permission matrix (allow / deny / unset, deny wins). Owners, admins, members — admins can't escalate themselves, owners are explicit
- **Real-time sync** — WebSocket push when someone else on the wallet makes a change
- **5-second UNDO** — for create / update / delete on contacts and transactions
- **Full audit trail** — every state change is an event in the log, queryable forever
- **Snapshot rotation** — efficient state rebuilds even with large event histories

---

## Architecture, briefly

```
                    ┌────────────────────────────────┐
                    │   crates/core/  (shared rules) │
                    │ ┌──────────┬─────────────────┐ │
                    │ │ domain   │ DomainEvent     │ │ ← 28 typed event variants
                    │ │ applier  │ Projection      │ │ ← event-application dispatch
                    │ │ resolver │ PermissionStore │ │ ← 3-state permission matrix
                    │ │ snapshots│ SnapshotStore   │ │ ← rotation + UNDO predicates
                    │ └──────────┴─────────────────┘ │
                    └───────────────┬────────────────┘
                                    │
                  ┌─────────────────┴─────────────────┐
                  │                                   │
        ┌─────────▼─────────┐               ┌─────────▼─────────┐
        │   crates/server   │               │   crates/client   │
        │  axum + sqlx + PG │ ◄── sync ──►  │  rusqlite + FRB   │
        │   (authoritative) │               │   (offline-first) │
        └─────────┬─────────┘               └─────────┬─────────┘
                  │                                   │
            Postgres DB                       SQLite (local)
                                                      │
                                                      ▼
                                              ┌──────────────┐
                                              │   mobile/    │
                                              │   Flutter UI │
                                              └──────────────┘
```

The four `core/*` crates have **zero storage-engine dependencies**. They define traits — `Projection`, `PermissionStore`, `SnapshotStore` — and the rules that operate over them. Server implements those traits against sqlx + Postgres. Client implements them against rusqlite + SQLite. The rules are written once and run on both sides.

**Authority is one-sided by design.** The server is the only place permissions are enforced. The client's local `can_perform` answers via the same resolver code, but only as a UX hint — every write still goes through the server, which can reject it.

---

## Self-host

### Prerequisites

- Rust 1.75+ (`rustup install stable`)
- Postgres 14+ (docker-compose provided)
- Flutter 3.5+ — only if you want to build the mobile app
- `cargo-nextest` for fast test runs (`cargo install cargo-nextest --locked`)

### Run it

```bash
git clone https://github.com/<your-fork>/deptmaster.git
cd deptmaster

# 1. Bring up Postgres + run migrations
./scripts/manage.sh setup-db

# 2. Start the server (http://localhost:8000 by default)
./scripts/manage.sh start-server

# 3. (optional) Build + install the mobile app
./scripts/manage.sh run-flutter-app linux   # or: android
```

That's it. The server is a single static binary. Backup is `pg_dump`. Logs are stdout. There is no "cloud service" anywhere — point your devices at your server, done.

### Production deploy

Single Rust binary + Postgres. Reverse-proxy with whatever you already use (Caddy, nginx, Traefik). Enable TLS at the proxy. The server speaks HTTP/1.1 and WebSocket over the same port.

---

## Repository layout

```
deptmaster/
├── crates/
│   ├── core/              ← shared rules (Rust, no storage engine)
│   │   ├── domain/        DomainEvent, EventData, typed IDs
│   │   ├── applier/       Projection trait + apply() dispatch
│   │   ├── resolver/      PermissionStore + permission rules
│   │   └── snapshots/     SnapshotStore + rotation + UNDO predicates
│   ├── server/            ← Postgres backend (sqlx + axum)
│   └── client/            ← Rust client lib for Flutter (FRB + rusqlite)
├── mobile/                ← Flutter app (Dart)
├── scripts/               ← manage.sh, codegen-rust-bridge.sh, setup
├── vault/                 ← documentation (Obsidian-flavored markdown)
└── LICENSE                GPLv3
```

---

## Testing

```bash
# Server unit + repository tests
cargo nextest run -p server

# Core rules (domain, applier, resolver, snapshots)
cargo nextest run -p domain -p applier -p resolver -p snapshots

# Client integration tests (runs against a live server)
./scripts/manage.sh test-integration
```

Current status: **47/47 client integration tests + 63/63 server tests pass.**

---

## Documentation

The `vault/` directory is the documentation home — written in Obsidian-flavored markdown but readable on plain GitHub.

Start here:

- [vault/00-getting-started/](vault/00-getting-started/) — system overview, core concepts, architecture
- [vault/01-events/](vault/01-events/) — what events are, the type-driven dispatch
- [vault/02-projections/](vault/02-projections/) — how state is computed from events
- [vault/03-snapshots/](vault/03-snapshots/) — snapshot rotation + UNDO
- [vault/04-permissions-and-undo/](vault/04-permissions-and-undo/) — the permission matrix
- [vault/06-client/](vault/06-client/) — client architecture + design decisions
- [vault/99-reference/01-glossary.md](vault/99-reference/01-glossary.md) — terms

---

## Contributing

This is a self-hostable open-source project under GPLv3. PRs welcome — see the vault docs for architectural context before sending big changes. Tests must pass (`cargo nextest run --workspace`).

---

## License

[GPLv3](LICENSE). Self-host freely. If you fork it commercially, your fork is GPL too.
