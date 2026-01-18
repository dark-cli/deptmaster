# Balance-Based Debt System

## ✅ Updated: Net Balance Per Contact

The system now tracks **net balance** per contact instead of individual transaction settlement status.

## How It Works

### Net Balance Calculation

For each contact, the balance is calculated as:
- **Positive balance** = They owe you money
- **Negative balance** = You owe them money  
- **Zero balance** = Settled (all debts balanced out)

```
Balance = SUM(
  IF direction = 'lent' THEN +amount
  IF direction = 'owed' THEN -amount
)
```

### Example

Contact: John
- Transaction 1: You lent $100 → +$100
- Transaction 2: You owe $50 → -$50
- Transaction 3: You lent $30 → +$30
- **Net Balance: +$80** (John owes you $80)

## Changes Made

### ✅ Removed
- `is_settled` field from transactions
- `settled_at` field from transactions
- "Status" column from transactions table in admin panel

### ✅ Added
- `balance` field in contact API responses
- Balance calculation in contacts query (computed from all transactions)
- Balance display in admin panel contacts table

## API Changes

### Contacts Endpoint
```json
{
  "id": "uuid",
  "name": "John",
  "balance": 8000,  // ← NEW: Net balance in cents
  "email": "...",
  "phone": "..."
}
```

### Transactions Endpoint
```json
{
  "id": "uuid",
  "contact_id": "uuid",
  "type": "money",
  "direction": "lent",
  "amount": 10000,
  "transaction_date": "2026-01-15"
  // ← Removed: is_settled
}
```

## Admin Panel

### Contacts Table
Now shows:
- **Balance** column with color-coded badges:
  - 🟢 Green: "They owe $X" (positive balance)
  - 🔴 Red: "You owe $X" (negative balance)
  - 🔵 Blue: "Settled" (zero balance)

### Transactions Table
- Removed "Status" column
- Shows all transactions (they all contribute to the net balance)

## Why This Makes Sense

In real debt management:
- You don't pay back individual transactions
- You care about the **total** you owe or are owed
- Multiple transactions accumulate into one balance
- When balance reaches zero, you're settled

## Your Data

All your 249 transactions now contribute to net balances per contact. Check the admin panel to see the balances!

🌐 **View at**: http://localhost:8000/admin
