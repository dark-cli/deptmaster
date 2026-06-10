//! Field-patch structs for partial updates. `Some(v)` means "set this
//! field to v"; `None` means "leave existing value untouched." Server
//! emits SQL with `COALESCE($new, existing)`; SDK does field-by-field
//! merging against the in-memory value. Either way, the wire interpretation
//! of `Option<T>` here is "patch semantics", not "nullable column."

#[derive(Debug, Clone, Default)]
pub struct ContactPatch {
    pub name: Option<String>,
    pub username: Option<String>,
    pub phone: Option<String>,
    pub email: Option<String>,
    pub notes: Option<String>,
    pub group_ids: Option<Vec<uuid::Uuid>>,
}

#[derive(Debug, Clone, Default)]
pub struct TransactionPatch {
    pub contact_id: Option<uuid::Uuid>,
    pub amount: Option<i64>,
    pub direction: Option<String>,
    pub transaction_type: Option<String>,
    pub currency: Option<String>,
    pub description: Option<String>,
    pub transaction_date: Option<String>,
    pub due_date: Option<String>,
}
