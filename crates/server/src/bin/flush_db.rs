// Utility to completely reset database to zero state
// Usage: cargo run --bin flush_db -- --confirm
// This will DROP all tables and re-run migrations to rebuild from scratch

use std::env;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let args: Vec<String> = env::args().collect();

    // Check for confirmation flag
    let has_confirm = args.iter().any(|arg| arg == "--confirm");

    if !has_confirm {
        eprintln!("⚠️  WARNING: This will COMPLETELY RESET the database!");
        eprintln!("   - All tables will be DROPPED");
        eprintln!("   - All data will be DELETED");
        eprintln!("   - Database will be rebuilt to zero state");
        eprintln!();
        eprintln!("Usage: cargo run --bin flush_db -- --confirm");
        eprintln!("\nExample:");
        eprintln!("  cargo run --bin flush_db -- --confirm");
        std::process::exit(1);
    }

    // Load environment variables
    dotenv::dotenv().ok();

    let database_url = env::var("DATABASE_URL").unwrap_or_else(|_| {
        "postgresql://debt_tracker:dev_password@localhost:5432/debt_tracker".to_string()
    });

    println!("🔗 Connecting to database...");
    let pool = sqlx::PgPool::connect(&database_url).await?;

    println!("🗑️  Dropping ALL database objects...");

    // Drop everything in the public schema
    sqlx::query(
        "DO $$ DECLARE r RECORD;
         BEGIN
           -- Drop all tables (CASCADE handles foreign keys and dependencies)
           FOR r IN (SELECT tablename FROM pg_tables WHERE schemaname = 'public') LOOP
             EXECUTE 'DROP TABLE IF EXISTS \"' || r.tablename || '\" CASCADE';
           END LOOP;

           -- Drop all sequences
           FOR r IN (SELECT sequencename FROM pg_sequences WHERE schemaname = 'public') LOOP
             EXECUTE 'DROP SEQUENCE IF EXISTS \"' || r.sequencename || '\" CASCADE';
           END LOOP;

           -- Drop all views
           FOR r IN (SELECT viewname FROM pg_views WHERE schemaname = 'public') LOOP
             EXECUTE 'DROP VIEW IF EXISTS \"' || r.viewname || '\" CASCADE';
           END LOOP;

           -- Drop all functions
           FOR r IN (SELECT routines.routine_name FROM information_schema.routines WHERE routines.routine_schema = 'public') LOOP
             EXECUTE 'DROP FUNCTION IF EXISTS \"' || r.routine_name || '\" CASCADE';
           END LOOP;

           -- Drop all types
           FOR r IN (SELECT typname FROM pg_type WHERE typnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')) LOOP
             EXECUTE 'DROP TYPE IF EXISTS \"' || r.typname || '\" CASCADE';
           END LOOP;
         END $$;"
    )
    .execute(&pool)
    .await?;

    println!("  ✓ All database objects dropped");

    println!("\n✅ Database completely nuked!");
    println!("📭 All tables, sequences, views, functions, types deleted");
    println!("🗑️  Database is now completely empty");

    Ok(())
}
