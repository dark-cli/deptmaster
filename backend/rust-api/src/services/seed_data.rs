use sqlx::PgPool;
use uuid::Uuid;
use chrono::Utc;

pub async fn seed_dummy_data(pool: &PgPool) -> anyhow::Result<()> {
    // Check if data already exists
    let count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM users_projection")
        .fetch_one(pool)
        .await?;

    if count > 0 {
        tracing::info!("Database already has data, skipping seed");
        return Ok(());
    }

    tracing::info!("Creating default user 'max'...");

    // Create default user "max" with password "1234"
    let user_id = Uuid::new_v4();
    sqlx::query(
        r#"
        INSERT INTO users_projection (id, email, password_hash, created_at, last_event_id)
        VALUES ($1, $2, $3, $4, 0)
        "#
    )
    .bind(&user_id)
    .bind("max")  // Email/username is "max"
    .bind("$2b$12$MzvHQ6CeZgenzzwkEV2WeeDQscVKQed1kTh8NxB7w2bXCXe2qFjxK") // bcrypt hash for "1234"
    .bind(Utc::now())
    .execute(pool)
    .await?;

    tracing::info!("Default user 'max' created successfully");
    
    // Don't seed dummy data - user will import their own data
    return Ok(());

    // Create contacts
    let contacts = vec![
        ("John Doe", Some("+1234567890"), Some("john@example.com")),
        ("Jane Smith", Some("+0987654321"), Some("jane@example.com")),
        ("Bob Johnson", Some("+1122334455"), None),
        ("Alice Williams", None, Some("alice@example.com")),
    ];

    let mut contact_ids = Vec::new();
    for (name, phone, email) in contacts {
        let contact_id = Uuid::new_v4();
        contact_ids.push(contact_id);

        // Create event
        sqlx::query(
            r#"
            INSERT INTO events (user_id, aggregate_type, aggregate_id, event_type, event_version, event_data, created_at)
            VALUES ($1, 'contact', $2, 'CONTACT_CREATED', 1, $3, $4)
            "#
        )
        .bind(&user_id)
        .bind(&contact_id)
        .bind(serde_json::json!({
            "name": name,
            "phone": phone,
            "email": email,
            "notes": null
        }))
        .bind(Utc::now())
        .execute(pool)
        .await?;

        // Create projection
        sqlx::query(
            r#"
            INSERT INTO contacts_projection (id, user_id, name, phone, email, is_deleted, created_at, updated_at, last_event_id)
            VALUES ($1, $2, $3, $4, $5, false, $6, $6, (SELECT MAX(id) FROM events))
            "#
        )
        .bind(&contact_id)
        .bind(&user_id)
        .bind(name)
        .bind(phone)
        .bind(email)
        .bind(Utc::now())
        .execute(pool)
        .await?;
    }

    // Create transactions
    let transactions = vec![
        (0, 0, "money", "owed", 5000, "Lunch payment"),
        (0, 1, "money", "lent", 2500, "Coffee"),
        (1, 0, "money", "owed", 10000, "Concert tickets"),
        (2, 0, "item", "lent", 1, "Book: The Rust Programming Language"),
        (3, 0, "item", "owed", 2, "DVDs: Movie collection"),
        (1, 0, "money", "lent", 7500, "Dinner"),
    ];

    for (idx, (contact_idx, _direction_idx, txn_type, direction, amount, description)) in transactions.iter().enumerate() {
        let transaction_id = Uuid::new_v4();
        let contact_id = contact_ids[*contact_idx];
        let transaction_date = Utc::now().date_naive() - chrono::Duration::days((transactions.len() - idx) as i64);

        // Create event
        sqlx::query(
            r#"
            INSERT INTO events (user_id, aggregate_type, aggregate_id, event_type, event_version, event_data, created_at)
            VALUES ($1, 'transaction', $2, 'TRANSACTION_CREATED', 1, $3, $4)
            "#
        )
        .bind(&user_id)
        .bind(&transaction_id)
        .bind(serde_json::json!({
            "contact_id": contact_id,
            "type": *txn_type,
            "direction": *direction,
            "amount": *amount,
            "currency": "USD",
            "description": *description,
            "transaction_date": transaction_date
        }))
        .bind(Utc::now())
        .execute(pool)
        .await?;

        // Create projection
        sqlx::query(
            r#"
            INSERT INTO transactions_projection (id, user_id, contact_id, type, direction, amount, currency, description, transaction_date, is_deleted, created_at, updated_at, last_event_id)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, false, $10, $10, (SELECT MAX(id) FROM events))
            "#
        )
        .bind(&transaction_id)
        .bind(&user_id)
        .bind(&contact_id)
        .bind(*txn_type)
        .bind(*direction)
        .bind(*amount)
        .bind("USD")
        .bind(*description)
        .bind(transaction_date)
        .bind(Utc::now())
        .execute(pool)
        .await?;
    }

    tracing::info!("Dummy data seeded successfully");
    Ok(())
}
