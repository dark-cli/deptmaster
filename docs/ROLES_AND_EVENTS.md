# Roles and events

## Wallet roles

- **owner** – Created the wallet (or was granted owner). Full access: manage members, groups, permission matrix. Multiple owners allowed.
- **admin** – *Not* a wallet role here; see "Web admin" below.
- **member** – Default when adding a user. Starts with read-only permission for the all_users group; change role later on the member if needed.

When **adding a user** to a wallet you only specify their **username** (lookup by email). They are added as **member**; promote to owner/admin later via "Change role" on the member.

## Web admin (global)

The **admin** (web admin / `admin_users` table) can view and manage users, groups, and wallets. They **must not** create contact/transaction events; events are created only by wallet members. (Enforcement can be added in create_contact, create_transaction, post_sync_events.)

## Events are immutable

**No one** may modify or delete events. Events are append-only. The only way to "reset" is a server/database reset. This is by design for audit and sync.

## TODO

- **Invites** – Add an invites flow (invite link / email) so members can be added without the inviter knowing their username/email upfront.
- **Username on users** – Currently add-member looks up by email; consider adding a proper username column to `users_projection` and support invite-by-username.
