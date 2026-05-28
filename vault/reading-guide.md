---
tags:
  - guide
  - navigation
---

# Vault Reading Guide

**You do NOT need to read from the start.** Jump to what you need.

---

## Current Status

**CURRENT & AUTHORITATIVE:**
- ✅ [[permission-system-deep-dive.md]] (comprehensive permission system documentation)
- ✅ [[merged-features.md]] (what was integrated from feature/advanced-permissions-system)
- ✅ [[current-state.md]] (project state after merge)
- ✅ [[architecture.md]], [[sync-architecture.md]], [[decisions.md]] (design documentation)
- ✅ [[todos.md]] (work tracking)

---

## Quick Navigation

### For a 5-minute overview
- [[current-state.md]] — Project snapshot: architecture, completed work, remaining work

### For permission system details
- [[permission-system-deep-dive.md]] — Complete request flow, resolution algorithm, code examples, testing
- [[advanced-permissions-plan.md]] — Design decisions and action inventory

### For what was recently merged
- [[merged-features.md]] — 55 commits from feature/advanced-permissions-system: multi-wallet system, permission enforcement, mobile updates, testing
- [[todos.md]] → "COMPLETED - MERGED FROM feature/advanced-permissions-system" section

### For architecture & design
- [[architecture.md]] — System components, tech stack, data flow
- [[middleware-architecture.md]] — Complete middleware chain, responsibilities, current issues
- [[sync-architecture.md]] — Event sourcing, offline-first sync, REST vs WebSocket
- [[decisions.md]] — Design trade-offs and rationale

### For security, performance, deployment
- [[todos.md]] → "Code Cleanup & Technical Debt" section
  - Database/client connection security (TLS)
  - Rate limiting per-user vs per-IP
  - Unused dependencies (Lettre, Redis)
  - Production defaults hardening

### For mobile/client-core
- [[merged-features.md]] → "Client-Core Library" and "Mobile/Flutter Updates" sections
- [[todos.md]] → "Mobile (Flutter) - Client-Core Migration & Features" section

---

## Reading Paths by Role

### Backend Engineer (Rust)
1. current-state.md (overview)
2. architecture.md (system design)
3. permission-system-deep-dive.md (permission checks & enforcement)
4. advanced-permissions-plan.md (if you need design context)
5. todos.md → "Code Cleanup & Technical Debt" (next work items)

### Mobile Engineer (Flutter)
1. current-state.md (overview)
2. merged-features.md → "Client-Core Library" and "Mobile/Flutter Updates"
3. todos.md → "Mobile (Flutter) - Client-Core Migration & Features" (what's left)
4. permission-system-deep-dive.md (how permissions work in handlers)

### DevOps / Security
1. current-state.md (overview)
2. todos.md → "Code Cleanup & Technical Debt" → "Security Issues" (CRITICAL items marked)
3. todos.md → "Configuration & Documentation" (hardening guide)
4. architecture.md (component overview)

### New Team Member (First Time)
1. current-state.md (10 min overview)
2. merged-features.md (what was just built)
3. architecture.md (how everything fits together)
4. sync-architecture.md (understand offline-first strategy)
5. permission-system-deep-dive.md (permission layer details)
6. todos.md (see what's remaining)

---

## Files and Purpose

| File | Purpose | Length | Read Time |
|------|---------|--------|-----------|
| **current-state.md** | Project overview after merge | ~200 lines | 5 min |
| **permission-system-deep-dive.md** | Complete permission request flow, algorithm, code examples | ~250 lines | 15 min |
| **merged-features.md** | What was merged, breaking changes, migration path | ~140 lines | 10 min |
| **advanced-permissions-plan.md** | Permission design decisions and rationale | ~155 lines | 10 min |
| **architecture.md** | Tech stack, components, data flow | ~200 lines | 10 min |
| **sync-architecture.md** | Event sourcing, offline-first, sync strategy | ~130 lines | 8 min |
| **decisions.md** | Design trade-offs (REST vs WebSocket, event vs command, etc.) | ~250 lines | 15 min |
| **todos.md** | Completed, in-progress, and remaining work | ~290 lines | 15 min |

---

## Key Changes (Post-Merge)

- ✅ **Multi-wallet system**: Data now scoped to wallet_id (solves data isolation)
- ✅ **Group-based permissions**: Discord/Telegram style (user_group × contact_group → actions)
- ✅ **Permission matrix**: Granular access control (replaces simple admin/user)
- ✅ **Client-core library**: Flutter Rust Bridge integration (new architecture for mobile)
- ⚠️ **Remaining**: Group management UIs, dynamic groups, mobile client-core migration

---

## When to Read What

**"I just got here and need context"** → Start with current-state.md + merged-features.md

**"I need to implement permission checks"** → permission-system-deep-dive.md + code examples

**"I'm fixing a bug in X"** → Use todos.md to find related work, then read relevant architecture file

**"I'm deploying this"** → todos.md → "Security Issues" + "Configuration & Documentation" sections

**"I need to understand the design rationale"** → decisions.md + advanced-permissions-plan.md

**"What's left to do?"** → todos.md (organized by component and priority)
