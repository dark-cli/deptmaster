# Chapter 08: Wallet Handler Refactoring

This chapter documents the wallets.rs 2.0 refactoring: rebuilding the wallet CRUD handler following the sync.rs 2.0 golden standard.

## Files

- **[01-wallets-2-0-refactoring-plan.md](01-wallets-2-0-refactoring-plan.md)** — Complete refactoring strategy for wallets.rs
  - Core architecture issues (string handling, duplicate helpers)
  - 6 priority endpoints to refactor
  - Implementation strategy (4 phases)
  - Type-safety principles for CRUD operations
  - Success criteria and testing strategy

## Context

wallets.rs is a CRUD handler (2,423 lines) that manages wallet operations:
- Wallet creation, retrieval, deletion
- User management (add, remove, update roles)
- Permission initialization
- WebSocket broadcasts

**Key difference from sync.rs:**
- sync.rs: Event-based (uses PermissionModel API for filtering)
- wallets.rs: Traditional CRUD (uses WalletRole enum for access control)

## Architecture Principles

1. **Type-Safe Roles:** WalletRole enum instead of strings throughout
2. **Validate at Boundary:** Request deserializers enforce role enum
3. **Pattern Matching:** Use Rust's type system, not string comparisons
4. **Clean Separation:** Handlers orchestrate, database layer executes
5. **No Duplication:** Reuse WalletRole helper methods, don't recreate logic

## Golden Standard

Follows patterns established in sync.rs 2.0:
- ✅ Type validation at deserialization boundary
- ✅ No string literals in business logic
- ✅ Pattern matching on types instead of strings
- ✅ Thin orchestration layer (handler focus: what calls what)
- ✅ Business logic in repository/service layer (where it belongs)

## Success Metrics

- Reduce from 2,423 to ~1,800 lines (26% reduction)
- Zero string-based role comparisons in logic
- Compile-time type safety for all role operations
- All tests passing, API responses unchanged
