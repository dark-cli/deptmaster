# Team Events Walkthrough

**Main question this file answers:** How do I add Team events from start to finish?

---

## Overview

Similar to User Events Walkthrough but for Team aggregate.

**Status:** TODO - Use User Events Walkthrough as template.

## Key Differences from User Events

Teams involve group operations:
- TeamCreated
- TeamMemberAdded
- TeamMemberRemoved
- TeamNameUpdated

Tables needed:
- `teams` (team metadata)
- `team_members` (who is in team)

Use the User Events Walkthrough as your template, adapting:
1. Event variants (TeamCreated, TeamMemberAdded, etc.)
2. Table structure (teams + team_members)
3. Handler logic
4. Tests

---

See: [01-user-events-walkthrough.md](01-user-events-walkthrough.md) for the complete walkthrough pattern.

Next: [03-expense-events-walkthrough.md](03-expense-events-walkthrough.md) — Add Expense events following the same pattern
