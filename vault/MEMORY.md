# Vault Index

Quick links to project documentation and references.

## Setup & Operations

- [Database Setup](database-setup.md) — Docker management, connection strings, quick start
- [Reading Guide](reading-guide.md) — Where to start learning the codebase

## Architecture & Design

- [Architecture](architecture.md) — High-level system design, event sourcing, sync protocol
- [Sync Architecture Deep Dive](sync-handler-deep-dive.md) — Detailed sync API implementation
- [UNDO Event Client Optimization](undo_event-client-optimization.md) — Delete unsync'd events instead of undoing
- [Permission System](permission-system-deep-dive.md) — User groups, contact groups, permission matrix
- [Middleware Architecture](middleware-architecture.md) — Auth, wallet context, rate limiting

## Client (Flutter UI + Rust core)

- [Client Overview](06-client/00-overview.md) — Module map for Rust core + Flutter layer
- [Client Refactoring Plan](06-client/00-refactoring-plan.md) — Active plan: discovery → divide → fix
- [Client Design Notes](06-client/01-design-notes.md) — Decisions on permissions, notifications, cache conflict, shared types
- [Shared Domain Crate Proposal](06-client/02-shared-domain-crate.md) — Extract event/permission/projection types
- [API Contract Audit](06-client/03-api-contract-audit.md) — Push payload mismatch (now fixed)
- [Test Baseline 2026-06-08](06-client/04-test-baseline-2026-06-08.md) — 5/40 pass after contract+signup+middleware fixes; failure clusters

## Database

- [Migration Guide](migration-guide.md) — All 21 migrations organized by phase
- [Migration Guidelines](migration-guidelines.md) — Standards for creating new migrations

## Implementation Plans

- [Database Crate Separation](database-crate-separation.md) — Extract database into `crates/debitum_db`
- [Sync Refactoring Plan](sync-refactoring-plan.md) — Phase 1-3 plan for modularizing sync.rs

## Status & Tracking

- [Backend TODO](backend-todo.md) — Backend development roadmap (phases 1-8, architecture work)
- [Client TODO](client-todo.md) — Frontend/Mobile development tasks (Flutter, Rust bridge, UI)
- [Current State](current-state.md) — Latest codebase snapshot
- [Merged Features](merged-features.md) — Feature branches integrated into main

