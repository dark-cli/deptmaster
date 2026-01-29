// Utility to set admin panel password
// Usage: cargo run --bin set_admin_password -- <username> <password>

use bcrypt::{hash, DEFAULT_COST};
use std::env;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let args: Vec<String> = env::args().collect();
    
    if args.len() < 3 {
        eprintln!("Usage: cargo run --bin set_admin_password -- <username> <password>");
        eprintln!("Example: cargo run --bin set_admin_password -- admin admin123");
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

    // Check if admin exists
    let admin_exists: bool = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM admin_users WHERE username = $1)"
    )
    .bind(username)
    .fetch_one(&pool)
    .await?;

    if admin_exists {
        // Update existing admin
        sqlx::query("UPDATE admin_users SET password_hash = $1, is_active = true WHERE username = $2")
            .bind(&password_hash)
            .bind(username)
            .execute(&pool)
            .await?;
        
        println!("✅ Admin password updated for user: {}", username);
    } else {
        // Create new admin
        use uuid::Uuid;
        use chrono::Utc;
        
        let admin_id = Uuid::new_v4();
        let email = format!("{}@debitum.local", username);
        
        sqlx::query(
            "INSERT INTO admin_users (id, username, password_hash, email, is_active, created_at) 
             VALUES ($1, $2, $3, $4, true, $5)"
        )
        .bind(&admin_id)
        .bind(username)
        .bind(&password_hash)
        .bind(&email)
        .bind(Utc::now())
        .execute(&pool)
        .await?;
        
        println!("✅ Admin user created: {}", username);
    }

    println!("📧 Username: {}", username);
    println!("🔑 Password: {}", password);
    println!("\nYou can now login to the admin panel with these credentials.");

    Ok(())
}
