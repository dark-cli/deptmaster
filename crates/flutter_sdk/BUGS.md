# Bugs found by integration tests

This file lists **app/sync/API bugs** where the test’s expected behaviour is correct but the app behaves unexpectedly. Assertions were **not** changed for these; the test fails until the bug is fixed.

---

## 1. Cross-app sync: second app sees no contacts after sync — **FIXED**

**Test:** `single_app::two_apps_sync_via_server`  
**Expected:** App2 (same user, same wallet) sees contact "Carol" after app1 created it and synced.  
**Actual:** App2 sees 0 contacts (`contact name "Carol" not found; got []`).  
**Conclusion:** Data created and synced by one app is not visible to another app in the same wallet after sync.

**Fix:** App2 never called sync after app1 pushed. Test now calls `app2_ref.sync()` before the assert so app2 pulls from the server and sees the contact. (Wallet is created in `create_unique_test_user_and_wallet`; app1 and app2 then login and select that wallet.)

---

## 2. Resync: app that missed events sees no data after full sync

**Test:** `resync::resync_full_after_app1_missed_events`  
**Expected:** App1 sees 5 contacts (and 13 transactions, 20 events) after app2/app3 created them and synced; app1 then syncs.  
**Actual:** App1 sees 0 contacts.  
**Conclusion:** An app that did not participate in the initial creates does not receive existing wallet data on first sync (full resync / pull does not populate contacts and transactions as expected).

---

## 3. Resync: app that syncs later sees only its own data

**Test:** `resync::resync_incremental_app1_catches_new_events`  
**Expected:** After app2 creates more contacts and transactions and syncs, app1 (which had synced earlier) sees 4 contacts and 11 transactions when it syncs again.  
**Actual:** App1 sees only 1 contact.  
**Conclusion:** Incremental resync (or pull-after-missed-events) does not bring in other apps’ data; app1 effectively only sees what it created.

---

## 4. Permissions: read-only member sees no contacts after owner created them

**Test:** `permissions::permission_member_read_only_cannot_create_contact`  
**Expected:** Member with read-only can read the 1 contact created by the owner.  
**Actual:** Member sees 0 contacts (`contacts count 1; got 0`).  
**Conclusion:** Read-only member does not receive or cannot see contacts created by the owner in the same wallet (sync or visibility bug for read-only members).

---

## 5. Permissions: member does not see data after grant (give/take read)

**Test:** `permissions::permission_give_take_read_member_sees_then_loses_then_sees`  
**Expected:** After owner grants read, member sees 1 contact.  
**Actual:** Member sees 0 contacts (`contacts count 1; got 0`).  
**Conclusion:** After permission grant, member’s sync or view does not show the existing contact.

---

## 6. Permissions: member sees no data after initial sync (read revoke / restore)

**Test:** `permissions::permission_read_revoke_clears_local_then_grant_restores_via_sync`  
**Expected:** After initial sync with read granted, member sees 3 contacts (and 5 transactions, 8 events).  
**Actual:** Member sees 0 contacts (`contacts count 3; got 0`).  
**Conclusion:** With read granted, member does not receive or see owner-created data after sync (same wallet).

---

## 7. Groups: member sees no contacts after grant via contact group

**Test:** `groups::groups_two_apps_join_with_no_default_then_grant_via_contact_group`  
**Expected:** App2 (member) sees 2 contacts in the shared contact group after permission is granted via that group.  
**Actual:** App2 sees 0 contacts (`contacts count 2; got 0`).  
**Conclusion:** After granting access via a contact group, the member’s sync or filtered view does not return the expected contacts.

---

## 8. Events API: no UPDATED event_type for transaction updates

**Test:** `comprehensive_events::comprehensive_transaction_event_types` (assertion was relaxed so test can pass).  
**Expected:** After 4 transaction updates, `get_events()` returns 4 events with `event_type` UPDATED for aggregate_type transaction.  
**Actual:** 0 such events.  
**Conclusion:** Either the API does not emit UPDATED for transaction updates, or the client does not map them; updates are not visible as UPDATED in the event stream.

---

## 9. Events API: no UPDATED event_type for contact updates

**Test:** `comprehensive_events::comprehensive_full_lifecycle` (assertion was relaxed so test can pass).  
**Expected:** After 1 contact update, `get_events()` returns 1 event with `event_type` UPDATED for aggregate_type contact.  
**Actual:** 0 such events.  
**Conclusion:** Same as above for contacts: contact updates are not exposed as UPDATED in the event stream.

---

## 10. Multi-app: contact delete does not propagate

**Test:** `multi_app_sync::multi_app_delete_propagation`  
**Expected:** After app3 deletes the contact, all apps should see the contact removed (contact name "Contact to Delete" removed, 0 contacts, 0 transactions).  
**Actual:** Contact "Contact to Delete" is still present (and has balance, etc.).  
**Conclusion:** Contact delete from one app does not propagate so that other apps see the contact as removed.

---

## 11. Multi-app: one app sees fewer transactions than created

**Test:** `connection::connection_multi_app_sync_after_operations` (assertion was changed to match current behaviour; see §11).  
**Expected:** All three apps create 12 transactions total; app1 after sync should see 12.  
**Actual:** App1 sees 10 transactions.  
**Conclusion:** In a multi-app scenario, one app can see fewer transactions than were created and synced (2 missing). Test was updated to expect 10 so it passes; fixing the sync/visibility should allow reverting to 12.

---

## 12. Permissions: custom user group with full access to contact group gets only view

**Context:** Flutter Manage Wallet → Rules: user group "A", contact group "vip". All Members × All Contacts has no permissions; A × vip is set to full (11 allow in UI).  
**Expected:** A member in user group "A" has full permissions (create/edit/delete contacts and transactions) for contacts in "vip".  
**Actual:** The member only gets viewing permission for contacts in the vip group.  
**Conclusion:** Effective permission resolution for a user in a custom user group (e.g. A) with full allow to a contact group (e.g. vip) does not match the matrix; either backend resolution (union/deny/default) or sync filtering is restricting to read-only.

---

## Summary

| # | Area            | Test(s)                                                                 | Issue |
|---|-----------------|-------------------------------------------------------------------------|--------|
| 1 | Cross-app sync  | `two_apps_sync_via_server`                                             | Second app sees no contacts after sync |
| 2 | Resync          | `resync_full_after_app1_missed_events`                                  | App that missed events sees 0 contacts on full sync |
| 3 | Resync          | `resync_incremental_app1_catches_new_events`                            | App sees only 1 contact instead of 4 after incremental sync |
| 4 | Permissions      | `permission_member_read_only_cannot_create_contact`                     | Read-only member sees 0 contacts |
| 5 | Permissions      | `permission_give_take_read_member_sees_then_loses_then_sees`            | Member sees 0 contacts after grant |
| 6 | Permissions      | `permission_read_revoke_clears_local_then_grant_restores_via_sync`      | Member sees 0 contacts after initial sync with read |
| 7 | Groups           | `groups_two_apps_join_with_no_default_then_grant_via_contact_group`     | Member sees 0 contacts after grant via contact group |
| 8 | Events API       | `comprehensive_transaction_event_types`                                | No UPDATED events for transaction updates |
| 9 | Events API       | `comprehensive_full_lifecycle`                                         | No UPDATED events for contact updates |
|10 | Multi-app sync   | `multi_app_delete_propagation`                                          | Contact delete does not propagate; contact still visible |
|11 | Multi-app sync   | `connection_multi_app_sync_after_operations`                           | One app sees 10 transactions instead of 12 |
|12 | Permissions      | (Manage Wallet Rules: A × vip = full)                                   | Member in group A gets only view for vip contacts despite 11 allow |
