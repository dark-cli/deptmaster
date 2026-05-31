use thiserror::Error;

#[derive(Error, Debug)]
pub enum DbError {
    #[error("Not found: {0}")]
    NotFound(String),

    #[error("Duplicate key: {0}")]
    DuplicateKey(String),

    #[error("Constraint violation: {0}")]
    ConstraintViolation(String),

    #[error("Database error: {0}")]
    QueryError(String),

    #[error("Serialization error: {0}")]
    SerializationError(String),

    #[error("Permission resolution error: {0}")]
    PermissionResolution(String),
}

impl From<sqlx::Error> for DbError {
    fn from(err: sqlx::Error) -> Self {
        match err {
            sqlx::Error::RowNotFound => DbError::NotFound("Row not found".to_string()),
            sqlx::Error::Database(db_err) => {
                let msg = db_err.message().to_string();
                let code = db_err.code().map(|c| c.as_ref().to_string());
                match code.as_deref() {
                    Some("23505") => DbError::DuplicateKey(msg),
                    Some("23503") => DbError::ConstraintViolation(msg),
                    _ => DbError::QueryError(msg),
                }
            }
            sqlx::Error::Decode(e) => DbError::SerializationError(e.to_string()),
            other => DbError::QueryError(other.to_string()),
        }
    }
}
