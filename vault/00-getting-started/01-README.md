# Getting Started with the Debt Tracker

**Main question this file answers:** How do I start learning about this system?

---

## Welcome

This documentation guides you from knowing nothing about the debt tracker to understanding how it works, how to extend it, and how to run it in production.

## Reading Path

**Start here if you:**
- Have never seen this codebase before
- Want to understand how event sourcing works
- Need to add a new feature or fix a bug

**Follow this path in order:**

1. **Chapter 00: Getting Started** (you are here)
   - Read: 01-README.md → 02-system-overview.md → 03-core-concepts.md → 04-main-architecture.md → 05-key-tables.md
   - Time: ~45 minutes
   - After this: You understand what the system does and how pieces fit together

2. **Chapters 01-04: Core Concepts** (events, projections, snapshots, permissions)
   - Read in order: 01-events → 02-projections → 03-snapshots → 04-permissions-and-undo
   - Time: ~2 hours
   - After this: You understand how the system actually works

3. **Chapter 05: Implementation Patterns** (for developers)
   - Read: 05-implementation-patterns
   - Time: ~1 hour
   - After this: You can add new event types and extend the system

4. **Chapters 06-07: Advanced Topics** (optional, for deep dives)
   - Read as needed: 06-advanced-extensions, 07-advanced-topics
   - Time: ~2-3 hours
   - After this: You understand performance, memory, consistency, and advanced patterns

5. **Chapter 99: Reference** (always available)
   - Use glossary.md whenever you see a term you don't understand

## Quick Navigation

- **"What are events?"** → Chapter 01: Events
- **"What are projections?"** → Chapter 02: Projections
- **"Why snapshots?"** → Chapter 03: Snapshots
- **"How do I add a new event type?"** → Chapter 05: Implementation Patterns
- **"What does this term mean?"** → Chapter 99: Glossary

## The Big Picture (2-Minute Summary)

The debt tracker uses **event sourcing** to track who owes whom:

1. **Events** record what happened ("Alice borrowed $50 from Bob")
2. **Projections** show current state ("Alice owns Bob $30")
3. **Snapshots** speed up loading ("Here's the state as of Tuesday")

This gives us:
- Complete audit trail (you can see the entire history)
- Ability to rebuild state from scratch (if something breaks)
- Type safety (using Rust enums, not strings)
- Scalability (batch processing keeps memory bounded)

That's it. Everything else is details.

## Tags
`#event-sourcing` `#getting-started` `#overview` `#entry-point`

## See Also
- **First-time readers:** Start with [02-system-overview.md](02-system-overview.md)
- **Looking for specifics:** Use Quick Navigation above or check [99-reference/01-glossary.md](../99-reference/01-glossary.md)
- **Want to jump to code:** See [05-implementation-patterns/02-code-organization.md](../05-implementation-patterns/02-code-organization.md)
- **Need a quick reference:** [99-reference/01-glossary.md](../99-reference/01-glossary.md) - All terms defined

---

Next: [02-system-overview.md](02-system-overview.md)
