/// Format permission actions in rwx-inspired notation
/// Format: "C: r:a c:a w:- d:- | T: r:a c:- w:- d:- x:-"
/// Where: a=allow, d=deny, -=unset

use std::collections::HashMap;

#[derive(Debug, Clone)]
pub struct PermissionVector {
    pub resource: String, // "C" for contacts, "T" for transactions
    pub permissions: HashMap<char, String>, // r, c, w, d, x -> a/d/-
}

impl PermissionVector {
    pub fn format(&self) -> String {
        let order = match self.resource.as_str() {
            "C" => vec!['r', 'c', 'w', 'd'],
            "T" => vec!['r', 'c', 'w', 'd', 'x'],
            _ => vec!['r', 'c', 'w', 'd'],
        };

        let perms = order
            .into_iter()
            .map(|key| {
                let state = self.permissions.get(&key).cloned().unwrap_or_else(|| "-".to_string());
                format!("{}:{}", key, state)
            })
            .collect::<Vec<_>>()
            .join(" ");

        format!("{}: {}", self.resource, perms)
    }
}

pub fn format_permission_matrix(
    allowed_actions: &[String],
    denied_actions: &[String],
) -> String {
    let mut vectors = Vec::new();

    // Contact permissions
    let mut contact_perms: HashMap<char, String> = HashMap::new();
    for action in allowed_actions {
        match action.as_str() {
            "contact:read" => contact_perms.insert('r', "a".to_string()),
            "contact:create" => contact_perms.insert('c', "a".to_string()),
            "contact:update" | "contact:edit" => contact_perms.insert('w', "a".to_string()),
            "contact:delete" => contact_perms.insert('d', "a".to_string()),
            _ => None,
        };
    }
    for action in denied_actions {
        match action.as_str() {
            "contact:read" => contact_perms.insert('r', "d".to_string()),
            "contact:create" => contact_perms.insert('c', "d".to_string()),
            "contact:update" | "contact:edit" => contact_perms.insert('w', "d".to_string()),
            "contact:delete" => contact_perms.insert('d', "d".to_string()),
            _ => None,
        };
    }

    if !contact_perms.is_empty() {
        vectors.push(PermissionVector {
            resource: "C".to_string(),
            permissions: contact_perms,
        });
    }

    // Transaction permissions
    let mut txn_perms: HashMap<char, String> = HashMap::new();
    for action in allowed_actions {
        match action.as_str() {
            "transaction:read" => txn_perms.insert('r', "a".to_string()),
            "transaction:create" => txn_perms.insert('c', "a".to_string()),
            "transaction:update" => txn_perms.insert('w', "a".to_string()),
            "transaction:delete" => txn_perms.insert('d', "a".to_string()),
            "transaction:close" => txn_perms.insert('x', "a".to_string()),
            _ => None,
        };
    }
    for action in denied_actions {
        match action.as_str() {
            "transaction:read" => txn_perms.insert('r', "d".to_string()),
            "transaction:create" => txn_perms.insert('c', "d".to_string()),
            "transaction:update" => txn_perms.insert('w', "d".to_string()),
            "transaction:delete" => txn_perms.insert('d', "d".to_string()),
            "transaction:close" => txn_perms.insert('x', "d".to_string()),
            _ => None,
        };
    }

    if !txn_perms.is_empty() {
        vectors.push(PermissionVector {
            resource: "T".to_string(),
            permissions: txn_perms,
        });
    }

    // Format as "C: r:a c:- w:a d:- | T: r:a c:- w:- d:- x:-"
    vectors
        .into_iter()
        .map(|v| v.format())
        .collect::<Vec<_>>()
        .join(" | ")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_format_full_contact_permissions() {
        let allowed = vec!["contact:read".to_string(), "contact:create".to_string()];
        let denied = vec!["contact:delete".to_string()];
        let result = format_permission_matrix(&allowed, &denied);
        assert!(result.contains("C: r:a c:a w:- d:d"));
    }

    #[test]
    fn test_format_transaction_permissions() {
        let allowed = vec![
            "transaction:read".to_string(),
            "transaction:create".to_string(),
        ];
        let denied = vec![];
        let result = format_permission_matrix(&allowed, &denied);
        assert!(result.contains("T: r:a c:a w:- d:- x:-"));
    }

    #[test]
    fn test_format_empty_permissions() {
        let allowed: Vec<String> = vec![];
        let denied: Vec<String> = vec![];
        let result = format_permission_matrix(&allowed, &denied);
        assert!(result.is_empty());
    }
}
