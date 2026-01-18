# Transaction Status Explained

## What is Transaction Status?

**Transaction Status** indicates whether a debt transaction has been **settled** (paid/returned) or is still **pending** (outstanding).

## Status Values

### ✅ **Settled** (`is_settled = true`)
- The debt has been **paid back** (for money) or **returned** (for items)
- The transaction is **complete** and closed
- Has a `settled_at` timestamp showing when it was settled

### ⏳ **Pending** (`is_settled = false`)
- The debt is still **outstanding**
- Money hasn't been paid back yet
- Item hasn't been returned yet
- This is the **default** status for new transactions

## In Your Database

Your transactions use the `is_settled` boolean field:

```sql
is_settled BOOLEAN DEFAULT FALSE
settled_at TIMESTAMP  -- When it was settled (if settled)
```

## Your Current Data

From your imported Debitum data:
- **249 transactions** total
- **All are Pending** (`is_settled = false`)
  - 97 transactions where you **lent** money
  - 152 transactions where you **owe** money

## How It Works

### Creating a Transaction
When you create a new transaction, it starts as **Pending**:
```json
{
  "is_settled": false,
  "settled_at": null
}
```

### Settling a Transaction
When someone pays you back or returns an item, you mark it as settled:
```json
{
  "is_settled": true,
  "settled_at": "2026-01-18T10:30:00"
}
```

This creates a `TRANSACTION_SETTLED` event in the event store.

## In the Admin Panel

The admin panel shows status as:
- 🟢 **"Settled"** badge (green) - when `is_settled = true`
- 🟡 **"Pending"** badge (yellow) - when `is_settled = false`

## Example Use Cases

### Money Transaction
- **Pending**: "I lent $100 to John" → John hasn't paid back yet
- **Settled**: "I lent $100 to John" → John paid me back on Jan 15

### Item Transaction  
- **Pending**: "I borrowed John's book" → I haven't returned it yet
- **Settled**: "I borrowed John's book" → I returned it on Jan 15

## API Response

When you query transactions, you get:
```json
{
  "id": "uuid",
  "contact_id": "uuid",
  "type": "money",
  "direction": "lent",
  "amount": 10000,
  "is_settled": false,  // ← This is the status
  "transaction_date": "2026-01-15"
}
```

## Summary

**Transaction Status = Is the debt settled?**
- `is_settled = false` → **Pending** (still owes/borrowed)
- `is_settled = true` → **Settled** (paid back/returned)

This helps you track which debts are still outstanding vs. which ones have been resolved!
