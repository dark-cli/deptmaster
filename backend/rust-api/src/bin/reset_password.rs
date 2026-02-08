// Utility to reset user password or create admin user
// Usage: cargo run --bin reset_password -- <username> <new_password>

use bcrypt::{hash, DEFAULT_COST};
use std::env;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let args: Vec<String> = env::args().collect();
    
    if args.len() < 3 {
        eprintln!("Usage: cargo run --bin reset_password -- <username> <new_password>");
        eprintln!("Example: cargo run --bin reset_password -- admin admin123");
        std::process::exit(1);
    }

    let username = &args[1];
    let password = &args[2];

    if password.len() < 8 {
        eprintln!("Error: Password must be at least 8 characters");
        std::process::exit(1);
    }

    // Load environment variables
    dotenv::dotenv().ok();
    
    let database_url = env::var("DATABASE_URL")
        .unwrap_or_else(|_| "postgresql://debt_tracker:dev_password@localhost:5432/debt_tracker".to_string());

    let pool = sqlx::PgPool::connect(&database_url).await?;

    // Hash password
    let password_hash = hash(password, DEFAULT_COST)?;

    // Check if user exists
    let user_exists: bool = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM users_projection WHERE username = $1)"
    )
    .bind(username)
    .fetch_one(&pool)
    .await?;

    if user_exists {
        // Update existing user
        sqlx::query("UPDATE users_projection SET password_hash = $1 WHERE username = $2")
            .bind(&password_hash)
            .bind(username)
            .execute(&pool)
            .await?;
        
        println!("✅ Password updated for user: {}", username);
    } else {
        // Create new user
        use uuid::Uuid;
        use chrono::Utc;
        
        let user_id = Uuid::new_v4();
        sqlx::query(
            "INSERT INTO users_projection (id, username, password_hash, created_at, last_event_id) 
             VALUES ($1, $2, $3, $4, 0)"
        )
        .bind(&user_id)
        .bind(username)
        .bind(&password_hash)
        .bind(Utc::now())
        .execute(&pool)
        .await?;
        
        println!("✅ User created: {}", username);
    }

    println!("📧 Username: {}", username);
    println!("🔑 Password: {}", password);
    println!("\nYou can now login with these credentials.");

    Ok(())
}
