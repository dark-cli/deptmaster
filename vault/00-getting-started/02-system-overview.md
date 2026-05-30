# System Overview

**Main question this file answers:** What does this system do at a high level?

---

## What is the Debt Tracker?

The debt tracker is a backend system that helps users track debts between people:
- "Alice owes Bob $50"
- "Charlie paid Alice $20"
- "Who has settled their debts?"

It stores this history and answers questions like:
- "How much does Alice owe Bob?"
- "What transactions happened last week?"
- "Who is in my permission group?"

## Why Use Event Sourcing?

Instead of storing just "Alice owes Bob $50", the system stores the **history of how we got there**:

```
Event 1: Alice borrowed $50 from Bob
Event 2: Alice paid Bob $20
Event 3: (Now we know: Alice owes Bob $30)
```

This has two huge benefits:

**Benefit 1: Complete Audit Trail**
- You can see exactly what happened and when
- You can't lose history (events are immutable)
- You can answer questions like "What was the balance on Tuesday?"

**Benefit 2: Rebuild State from Scratch**
- If a bug corrupts the current state, you can rebuild it from events
- Snapshots let you avoid reprocessing millions of events from the beginning

## The Three Core Pieces

### 1. Events (The History)

Events are immutable records: "something happened at this time."

Examples:
- `ContactCreated`: "Alice was added as a contact"
- `TransactionCreated`: "Alice borrowed $50 from Bob"
- `WalletUserAdded`: "Alice was added to my wallet with admin role"

Events are stored in the database forever. They never change (only UNDO events mark them as deleted).

### 2. Projections (The Current State)

Projections are materialized views—answers to "what is the current state?"

When you read "How much does Alice owe Bob?", we don't replay all events. Instead:
- We stored that answer in a table (`transactions_projection`)
- We just look it up

This is fast because we compute projections once when events arrive, not every time someone asks.

### 3. Snapshots (The Shortcut)

Snapshots solve a memory problem:

**Problem:** If a wallet has 1 million events, rebuilding projections from scratch means:
- Load 1 million events into RAM
- Process each one
- This takes too much memory

**Solution:** Save snapshots—"the state at this point in time"
- When you rebuild, start from the latest snapshot
- Only reprocess recent events
- This keeps memory bounded (5-10 MB instead of 1 GB)

## The Architecture

```
User syncs → Events arrive → Apply to projections → Store snapshot → Return current state
                    ↓
              (Immutable history)
                    ↓
        (Fast lookup answers)
                    ↓
         (Memory-efficient rebuilds)
```

## Why This Matters

1. **Reliability**: You can verify projections are correct by replaying events
2. **Scalability**: Snapshots let you handle millions of events without running out of memory
3. **Auditability**: Complete history of every change
4. **Type Safety**: Using Rust enums (not strings) prevents bugs

---

Next: [03-core-concepts.md](03-core-concepts.md) — Understand the core ideas more deeply
