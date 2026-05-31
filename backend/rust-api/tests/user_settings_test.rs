use debt_tracker_api::database::models::UserSettings;
use debt_tracker_api::database::repository::{Database, DatabaseRepository};

mod test_helpers;
use test_helpers::*;

#[tokio::test]
async fn test_create_and_retrieve_user_settings() {
    let pool = setup_test_db().await;
    let db = Database::new(pool.clone());
    let user_id = create_test_user(&pool).await;

    // Create user settings
    let settings = UserSettings {
        user_id,
        dark_mode: true,
        default_direction: "give".to_string(),
        flip_colors: false,
        due_date_enabled: true,
        default_due_date_days: 30,
        default_due_date_switch: false,
        created_at: chrono::Local::now().naive_local(),
        updated_at: chrono::Local::now().naive_local(),
    };

    db.upsert_user_settings(user_id, &settings)
        .await
        .expect("Failed to upsert settings");

    // Retrieve and verify
    let retrieved = db
        .get_user_settings(user_id)
        .await
        .expect("Failed to get settings");
    assert!(retrieved.is_some());
    let retrieved_settings = retrieved.unwrap();
    assert_eq!(retrieved_settings.user_id, user_id);
    assert_eq!(retrieved_settings.dark_mode, true);
    assert_eq!(retrieved_settings.default_direction, "give");
    assert_eq!(retrieved_settings.flip_colors, false);
    assert_eq!(retrieved_settings.due_date_enabled, true);
    assert_eq!(retrieved_settings.default_due_date_days, 30);
}

#[tokio::test]
async fn test_update_user_settings() {
    let pool = setup_test_db().await;
    let db = Database::new(pool.clone());
    let user_id = create_test_user(&pool).await;

    // Create initial settings
    let initial_settings = UserSettings {
        user_id,
        dark_mode: true,
        default_direction: "give".to_string(),
        flip_colors: false,
        due_date_enabled: false,
        default_due_date_days: 30,
        default_due_date_switch: false,
        created_at: chrono::Local::now().naive_local(),
        updated_at: chrono::Local::now().naive_local(),
    };

    db.upsert_user_settings(user_id, &initial_settings)
        .await
        .expect("Failed to upsert initial settings");

    // Update settings
    let updated_settings = UserSettings {
        user_id,
        dark_mode: false,
        default_direction: "take".to_string(),
        flip_colors: true,
        due_date_enabled: true,
        default_due_date_days: 45,
        default_due_date_switch: true,
        created_at: initial_settings.created_at,
        updated_at: chrono::Local::now().naive_local(),
    };

    db.upsert_user_settings(user_id, &updated_settings)
        .await
        .expect("Failed to update settings");

    // Verify updates
    let retrieved = db
        .get_user_settings(user_id)
        .await
        .expect("Failed to get settings");
    assert!(retrieved.is_some());
    let retrieved_settings = retrieved.unwrap();
    assert_eq!(retrieved_settings.dark_mode, false);
    assert_eq!(retrieved_settings.default_direction, "take");
    assert_eq!(retrieved_settings.flip_colors, true);
    assert_eq!(retrieved_settings.due_date_enabled, true);
    assert_eq!(retrieved_settings.default_due_date_days, 45);
    assert_eq!(retrieved_settings.default_due_date_switch, true);
}

#[tokio::test]
async fn test_upsert_individual_setting() {
    let pool = setup_test_db().await;
    let db = Database::new(pool.clone());
    let user_id = create_test_user(&pool).await;

    // Upsert individual setting (should create with defaults)
    db.upsert_user_setting(user_id, "dark_mode", "false")
        .await
        .expect("Failed to upsert setting");

    // Verify
    let retrieved = db
        .get_user_settings(user_id)
        .await
        .expect("Failed to get settings");
    assert!(retrieved.is_some());
    let retrieved_settings = retrieved.unwrap();
    assert_eq!(retrieved_settings.dark_mode, false);
    // Other fields should have defaults
    assert_eq!(retrieved_settings.default_direction, "give");
    assert_eq!(retrieved_settings.flip_colors, false);

    // Update another setting
    db.upsert_user_setting(user_id, "default_direction", "take")
        .await
        .expect("Failed to update setting");

    // Verify both are persisted
    let retrieved = db
        .get_user_settings(user_id)
        .await
        .expect("Failed to get settings");
    let settings = retrieved.unwrap();
    assert_eq!(settings.dark_mode, false);
    assert_eq!(settings.default_direction, "take");
}

#[tokio::test]
async fn test_get_user_settings_all_key_value_format() {
    let pool = setup_test_db().await;
    let db = Database::new(pool.clone());
    let user_id = create_test_user(&pool).await;

    // Create settings
    let settings = UserSettings {
        user_id,
        dark_mode: true,
        default_direction: "give".to_string(),
        flip_colors: false,
        due_date_enabled: true,
        default_due_date_days: 30,
        default_due_date_switch: false,
        created_at: chrono::Local::now().naive_local(),
        updated_at: chrono::Local::now().naive_local(),
    };

    db.upsert_user_settings(user_id, &settings)
        .await
        .expect("Failed to upsert settings");

    // Get as key-value pairs (backwards compatibility format)
    let pairs = db
        .get_user_settings_all(user_id)
        .await
        .expect("Failed to get all settings");
    assert!(!pairs.is_empty());

    // Verify expected keys are present
    let keys: Vec<String> = pairs.iter().map(|(k, _)| k.clone()).collect();
    assert!(keys.contains(&"dark_mode".to_string()));
    assert!(keys.contains(&"default_direction".to_string()));
    assert!(keys.contains(&"flip_colors".to_string()));

    // Verify values
    let map: std::collections::HashMap<String, Option<String>> = pairs.into_iter().collect();
    assert_eq!(
        map.get("dark_mode")
            .and_then(|v| v.as_ref())
            .map(|s| s.as_str()),
        Some("true")
    );
    assert_eq!(
        map.get("default_direction")
            .and_then(|v| v.as_ref())
            .map(|s| s.as_str()),
        Some("give")
    );
}

#[tokio::test]
async fn test_user_settings_not_found() {
    let pool = setup_test_db().await;
    let db = Database::new(pool.clone());
    use uuid::Uuid;
    let non_existent_user_id = Uuid::new_v4();

    // Try to get settings for non-existent user
    let retrieved = db
        .get_user_settings(non_existent_user_id)
        .await
        .expect("Failed to query settings");
    assert!(retrieved.is_none());
}

#[test]
fn test_user_settings_defaults() {
    let user_settings = UserSettings::default();
    assert_eq!(user_settings.dark_mode, true);
    assert_eq!(user_settings.default_direction, "give");
    assert_eq!(user_settings.flip_colors, false);
    assert_eq!(user_settings.due_date_enabled, false);
    assert_eq!(user_settings.default_due_date_days, 30);
    assert_eq!(user_settings.default_due_date_switch, false);
}
