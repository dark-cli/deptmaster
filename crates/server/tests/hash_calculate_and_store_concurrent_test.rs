//! Regression test for the lost-update race in
//! `UserEventHash::calculate_and_store`.
//!
//! Before the fix, the function did:
//!   SELECT current_hash
//!   md5(current_hash || event_id)
//!   UPSERT user_event_hashes
//! as THREE separate statements. Two concurrent calls folding
//! different event_ids into the same (wallet, user) row would both
//! observe the pre-write hash, both compute new hashes off that
//! pre-write value, and the second UPSERT would clobber the first.
//! One event's fold was permanently lost — but the event itself was
//! still in `user_readable_events`, so the next client pull diverged
//! (server's hash != fold-of-events-returned). Clients then went
//! into a `hash diverged → events_delete_all_for_wallet → full-pull`
//! loop on every action.
//!
//! After the fix, calculate_and_store is a single
//! `INSERT ... ON CONFLICT DO UPDATE SET hash = md5(... || $3::text)`
//! statement. Postgres takes a row lock on the conflicting row so
//! concurrent statements serialize: each fold sees the prior fold's
//! result.
//!
//! These tests call `UserEventHash::calculate_and_store` directly so
//! we exercise the exact race window without the FK plumbing of
//! `add_readable_event_impl`. The (wallet, user) keys are random UUIDs
//! — `user_event_hashes` has no FK on those columns, so no fixture
//! setup is needed.

mod test_helpers;

use uuid::Uuid;

use server::database::repository::hash::UserEventHash;

#[tokio::test]
async fn concurrent_calculate_and_store_does_not_lose_updates() {
    let pool = test_helpers::setup_test_db().await;

    let user_id = test_helpers::create_test_user(&pool).await;
    let wallet_id = test_helpers::create_test_wallet(&pool, "hash-divergence-test").await;

    // Clean slate on the user_event_hashes row.
    sqlx::query("DELETE FROM user_event_hashes WHERE wallet_id = $1 AND user_id = $2")
        .bind(wallet_id)
        .bind(user_id)
        .execute(&pool)
        .await
        .expect("pre-cleanup");

    let event_ids: Vec<Uuid> = (0..50).map(|_| Uuid::new_v4()).collect();

    // Fire all folds concurrently.
    let mut handles = Vec::with_capacity(event_ids.len());
    for eid in &event_ids {
        let pool = pool.clone();
        let eid = *eid;
        handles.push(tokio::spawn(async move {
            UserEventHash::calculate_and_store(&pool, wallet_id, user_id, eid).await
        }));
    }
    let mut returned_hashes = Vec::with_capacity(event_ids.len());
    for h in handles {
        returned_hashes.push(h.await.expect("task join").expect("calculate_and_store"));
    }

    // Pre-fix bug signature: with three separate SQL statements, all
    // concurrent callers read current_hash = "" (no row yet), each
    // computes md5("" || X_i), each UPSERTs with its own computed
    // hash via `hash = EXCLUDED.hash`. The LAST writer wins; the
    // stored hash represents ONE fold step, not 50.
    //
    // So: with the buggy code, the stored hash equals md5("" || X_i)
    // for some single i. With the fixed code, the stored hash equals
    // a full N-step chain — vanishingly unlikely to equal any single
    // md5("" || X_i) by coincidence (2^-128 collision).
    let stored_hash: String = sqlx::query_scalar(
        "SELECT hash FROM user_event_hashes WHERE wallet_id = $1 AND user_id = $2",
    )
    .bind(wallet_id)
    .bind(user_id)
    .fetch_one(&pool)
    .await
    .expect("read stored hash");

    let mut single_step_hashes = Vec::with_capacity(event_ids.len());
    for eid in &event_ids {
        let input = format!("{}", eid);
        let h: String = sqlx::query_scalar("SELECT md5($1::text)")
            .bind(&input)
            .fetch_one(&pool)
            .await
            .expect("md5");
        single_step_hashes.push(h);
    }
    assert!(
        !single_step_hashes.contains(&stored_hash),
        "stored_hash {} equals md5(\"\" || some single event_id), which means N-1 \
         folds were lost: the concurrent UPSERTs all read the empty pre-write \
         hash, each computed their own single-step md5, and the last writer's \
         single-step value won. This is the lost-update race the fix targets.",
        stored_hash,
    );

    // Cleanup.
    sqlx::query("DELETE FROM user_event_hashes WHERE wallet_id = $1 AND user_id = $2")
        .bind(wallet_id)
        .bind(user_id)
        .execute(&pool)
        .await
        .expect("cleanup");
}

/// Serial baseline: prove that single-threaded folds match a
/// hand-computed md5 chain. If THIS fails, the SQL inside
/// calculate_and_store is wrong regardless of concurrency.
#[tokio::test]
async fn serial_calculate_and_store_matches_handfolded_chain() {
    let pool = test_helpers::setup_test_db().await;
    let user_id = test_helpers::create_test_user(&pool).await;
    let wallet_id = test_helpers::create_test_wallet(&pool, "hash-divergence-test").await;

    sqlx::query("DELETE FROM user_event_hashes WHERE wallet_id = $1 AND user_id = $2")
        .bind(wallet_id)
        .bind(user_id)
        .execute(&pool)
        .await
        .expect("pre-cleanup");

    let event_ids: Vec<Uuid> = (0..10).map(|_| Uuid::new_v4()).collect();

    for eid in &event_ids {
        UserEventHash::calculate_and_store(&pool, wallet_id, user_id, *eid)
            .await
            .expect("fold");
    }

    let stored: String = sqlx::query_scalar(
        "SELECT hash FROM user_event_hashes WHERE wallet_id = $1 AND user_id = $2",
    )
    .bind(wallet_id)
    .bind(user_id)
    .fetch_one(&pool)
    .await
    .expect("read");

    // Hand-fold the same chain through Postgres's md5 to remove any
    // ambiguity about which md5 implementation produces the truth.
    let mut acc = String::new();
    for eid in &event_ids {
        let input = format!("{}{}", acc, eid);
        let computed: String = sqlx::query_scalar("SELECT md5($1::text)")
            .bind(&input)
            .fetch_one(&pool)
            .await
            .expect("md5");
        acc = computed;
    }

    assert_eq!(
        stored, acc,
        "serial folds via calculate_and_store don't match hand-computed md5 chain",
    );

    sqlx::query("DELETE FROM user_event_hashes WHERE wallet_id = $1 AND user_id = $2")
        .bind(wallet_id)
        .bind(user_id)
        .execute(&pool)
        .await
        .expect("cleanup");
}
