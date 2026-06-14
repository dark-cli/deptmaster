//! Regression tests for `UserEventHash::calculate_and_store`.
//!
//! The history of this code in one paragraph: the original version was
//! a chain-MD5 done in three separate SQL statements, which lost
//! updates under concurrent folds. The first fix collapsed it into one
//! atomic UPSERT with `hash = md5(user_event_hashes.hash || $3::text)`,
//! eliminating the lost-update race. But a deeper issue remained:
//! chain-MD5 is order-sensitive, and the order in which two concurrent
//! folds acquire the row lock is non-deterministic, while the client
//! always folds events in `created_at ASC` (the pull's natural order).
//! Server fold-order and client fold-order can disagree, producing a
//! permanent server↔client hash divergence loop. The fix is to use
//! an ORDER-INDEPENDENT hash: XOR-of-MD5(event_id). Commutative, so
//! any fold order produces the same final hash. Migration 032
//! recomputes existing rows in-place using XOR over user_readable_events.
//!
//! These tests call `UserEventHash::calculate_and_store` directly so
//! we exercise the exact race window without the FK plumbing of
//! `add_readable_event_impl`. The (wallet, user) keys come from
//! create_test_user / create_test_wallet because user_event_hashes
//! has FKs into those tables.

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

    let stored_hash: String = sqlx::query_scalar(
        "SELECT hash FROM user_event_hashes WHERE wallet_id = $1 AND user_id = $2",
    )
    .bind(wallet_id)
    .bind(user_id)
    .fetch_one(&pool)
    .await
    .expect("read stored hash");

    // Under XOR-of-MD5, the stored hash must equal the bytewise XOR of
    // md5(event_id::text) over every event_id we folded — regardless
    // of the order Postgres processed the concurrent UPSERTs. If
    // anything was lost or counted twice, the XOR won't match the
    // reference.
    //
    // Reference: ask Postgres to compute the same XOR aggregate over
    // user_readable_events the migration would compute on a fresh
    // recomputation. We didn't insert anything into
    // user_readable_events here (we call calculate_and_store directly),
    // so we compute the reference straight from event_ids.
    let reference_hash = xor_md5_reference(&event_ids);
    assert_eq!(
        stored_hash, reference_hash,
        "stored hash {} doesn't match the XOR-of-MD5(event_id) reference {}. \
         Either a fold was lost (race) or the calculate_and_store SQL is \
         computing something other than XOR.",
        stored_hash, reference_hash,
    );

    // Cleanup.
    sqlx::query("DELETE FROM user_event_hashes WHERE wallet_id = $1 AND user_id = $2")
        .bind(wallet_id)
        .bind(user_id)
        .execute(&pool)
        .await
        .expect("cleanup");
}

/// Serial baseline: single-threaded folds in a fixed order should
/// match a hand-computed XOR-of-MD5(event_id). If THIS fails, the SQL
/// inside calculate_and_store isn't actually computing XOR.
#[tokio::test]
async fn serial_calculate_and_store_matches_xor_reference() {
    let pool = test_helpers::setup_test_db().await;
    let user_id = test_helpers::create_test_user(&pool).await;
    let wallet_id = test_helpers::create_test_wallet(&pool, "hash-xor-serial-test").await;

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

    let reference = xor_md5_reference(&event_ids);
    assert_eq!(stored, reference, "serial folds don't match XOR-of-MD5 reference");

    // XOR is its own inverse: re-folding the same events cancels them.
    // This is the property that lets the server safely re-process
    // duplicate events without producing a wrong hash.
    for eid in &event_ids {
        UserEventHash::calculate_and_store(&pool, wallet_id, user_id, *eid)
            .await
            .expect("re-fold");
    }
    let after_double_fold: String = sqlx::query_scalar(
        "SELECT hash FROM user_event_hashes WHERE wallet_id = $1 AND user_id = $2",
    )
    .bind(wallet_id)
    .bind(user_id)
    .fetch_one(&pool)
    .await
    .expect("read");
    assert_eq!(
        after_double_fold, "00000000000000000000000000000000",
        "XOR is its own inverse — folding the same event twice should cancel it",
    );

    sqlx::query("DELETE FROM user_event_hashes WHERE wallet_id = $1 AND user_id = $2")
        .bind(wallet_id)
        .bind(user_id)
        .execute(&pool)
        .await
        .expect("cleanup");
}

/// Pure-Rust reference: XOR-of-MD5(event_id) over a set of event_ids.
/// The order of event_ids in the slice doesn't matter for the result.
fn xor_md5_reference(event_ids: &[Uuid]) -> String {
    use md5::{Digest, Md5}; // from md-5 crate
    let mut acc = [0u8; 16];
    for eid in event_ids {
        let digest = Md5::digest(eid.to_string().as_bytes());
        for (a, d) in acc.iter_mut().zip(digest.iter()) {
            *a ^= *d;
        }
    }
    acc.iter().map(|b| format!("{:02x}", b)).collect()
}
