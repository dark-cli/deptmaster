# Permission Defaults and Scoped Access

**Main question this file answers:** What are the default permissions when a wallet is created? How do the three permission states work? How do you achieve scoped access where teams can only see their assigned contacts?

---

## The Three Permission States

Every permission can be in one of **three states**:

| State | Symbol | Meaning | Resolution Behavior |
|-------|--------|---------|----------------------|
| **Allow** | `:a` | Permission is **granted** | User CAN perform the action |
| **Deny** | `:d` | Permission is **explicitly denied** | User CANNOT perform the action (deny wins over allow) |
| **Unset** | `:-` | Permission is **not configured** | User needs explicit allow from another group; unset doesn't block |

### Key Concept: "Unset" is NOT Deny

⚠️ **Important:** Unset (`:−`) is **NOT the same as** Deny (`:d`)

- **Unset** means "no decision made" — check other groups
- **Deny** means "explicitly blocked" — prevents action even if another group allows it

---

## Default Permissions: What Happens When a Wallet is Created

When a wallet is created, the system automatically grants **default permissions**:

### Step 1: System Creates Default Groups
```sql
CREATE:
  - all_users       (automatically includes all members)
  - all_contacts    (automatically includes all contacts)
  - __owners__      (includes the wallet owner)
```

### Step 2: System Grants Default Permissions

The default permission matrix is initialized with:

```
all_users → all_contacts:
  C: r:a c:- w:- d:-    (Read ALLOWED, create/write/delete UNSET)
  T: r:a c:- w:- d:- x:- (Read ALLOWED, others UNSET)
```

**This means:** By default, ALL members can **READ** all contacts and transactions.

### Step 3: Owners Get Full Access

```
__owners__ → all_contacts:
  C: r:a c:a w:a d:a    (All actions ALLOWED)
  T: r:a c:a w:a d:a x:a (All actions ALLOWED)
```

**This means:** The wallet owner can do everything.

---

## How the Permission Resolution Works

When checking if a user can perform an action, the system:

1. Collects ALL groups the user belongs to
2. Checks the permission matrix for each group
3. Applies the rule: **DENY wins over ALLOW** (if any group denies, it's denied)

### Example: Member in Two Groups

Suppose Alice belongs to:
- `all_users` (default group, has r:a on all_contacts)
- `team1` (custom group, has r:a on projecta only)

For each contact:
- **Contact in projecta:** ✅ ALLOWED (via team1)
- **Contact NOT in projecta:** ✅ ALLOWED (via all_users default read)

**Problem:** Alice sees both projecta AND non-projecta contacts (not what we want for scoped access!)

---

## How to Achieve Scoped Access

To make teams see ONLY their assigned contacts (e.g., team1 sees only projecta):

### Option 1: Unset the Default Read Permission ✅ RECOMMENDED

```
all_users → all_contacts:
  C: r:- c:- w:- d:-    (Read UNSET, not denied)
  T: r:- c:- w:- d:- x:- (Read UNSET)

team1 → projecta:
  C: r:a c:- w:- d:-    (Read ALLOWED on projecta only)
  T: r:a c:- w:- d:- x:-

team2 → projectb:
  C: r:a c:- w:- d:-    (Read ALLOWED on projectb only)
  T: r:a c:- w:- d:- x:-
```

**Result:**
- member1 (in team1): sees ONLY projecta contacts (2 contacts: Alice, Bob)
- member2 (in team2): sees ONLY projectb contacts (1 contact: Charlie)
- No default read access to fall back on

### Option 2: Deny the Default Read Permission

```
all_users → all_contacts:
  C: r:d c:- w:- d:-    (Read DENIED for all)
  T: r:d c:- w:- d:- x:- (Read DENIED)
```

⚠️ **Warning:** This creates conflicts if you also grant reads to specific groups. The deny will block even scoped grants (known bug in complex scenarios).

### Option 3: Don't Grant any Default Permission (Start Empty)

Never set `all_users → all_contacts` at all. Users have zero access unless explicitly granted.

---

## Step-by-Step: Implementing Scoped Access

### In EventGenerator Test Format:

```bash
# Step 1: Unset the default read permission
"owner: permission set all_users all_contacts \"C: r:- c:- w:- d:-, T: r:- c:- w:- d:- x:-\""

# Step 2: Create teams
"owner: user-group create \"Team1\" team1"
"owner: user-group create \"Team2\" team2"

# Step 3: Create contact groups
"owner: contact-group create \"ProjectA\" projecta"
"owner: contact-group create \"ProjectB\" projectb"

# Step 4: Add members to teams
"owner: group-member add team1 member1"
"owner: group-member add team2 member2"

# Step 5: Add contacts to project groups
"owner: group-member add projecta alice"
"owner: group-member add projectb charlie"

# Step 6: Grant scoped access
"owner: permission set team1 projecta \"C: r:a c:- w:- d:-, T: r:a c:- w:- d:- x:-\""
"owner: permission set team2 projectb \"C: r:a c:- w:- d:-, T: r:a c:- w:- d:- x:-\""

# Result: member1 sees 2 contacts, member2 sees 1 contact
"member1: assert contacts count 2"
"member2: assert contacts count 1"
```

---

## Permission State Summary Table

| Scenario | Default | Action | Scoped Allow | Result | Use Case |
|----------|---------|--------|--------------|--------|----------|
| Global access | r:a | (none) | r:a | ✅ Can read all | Public data, general access |
| Scoped access | r:- | (unset) | r:a | ✅ Can read scoped only | Teams see their projects |
| Scoped with deny | r:d | (denied) | r:a | ❌ Conflict (deny wins) | Not recommended |
| No default | (no rule) | (none) | r:a | ✅ Can read scoped only | Most restrictive |

---

## Key Takeaway

**To enable scoped access:**

1. **Change the default:** Set `all_users → all_contacts` to **UNSET** (`r:-`)
   - This removes the default read-everything permission
   
2. **Add scoped grants:** Create team-specific permissions
   - `team1 → projecta: r:a` (read projecta only)
   - `team2 → projectb: r:a` (read projectb only)

3. **Result:** Members see ONLY what they're explicitly granted
   - No fallback to default all-access
   - Scoped permissions take full effect

---

## Testing Checklist

- [ ] Default `all_users → all_contacts` is understood (r:a by default)
- [ ] Three permission states are clear (a, d, -)
- [ ] Scoped access working: team sees only their contacts
- [ ] Deny overrides allow: tested and confirmed
- [ ] Permission changes trigger resync: hash mismatch detected
- [ ] Unset vs deny are distinguished in tests
