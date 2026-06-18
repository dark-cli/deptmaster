//! The three system-managed groups that exist in every wallet: two user
//! groups (`all_users`, `__owners__`) and one contact group
//! (`all_contacts`). These names appear in event payloads, applier rules
//! ("a new contact joins `all_contacts`"), the resolver's wildcard logic,
//! and the wallet-initialization flow. Carrying them as `&str` everywhere
//! is exactly the kind of string-in-logic violation the typed-domain rule
//! forbids — this enum is the single source of truth.

use std::fmt;

/// Which kind of group a [`SystemGroup`] is. Lets callers reject e.g.
/// "add `all_contacts` to a user_group slot" at the type level.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum SystemGroupKind {
    UserGroup,
    ContactGroup,
}

/// Wallet-scoped system groups. Each one is seeded on wallet creation and
/// referenced by *name* in events (so the wallet's `Uuid` for the row can
/// vary across rebuilds, but the identity stays constant).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum SystemGroup {
    /// User group containing every member of the wallet. Receives the
    /// default read grants (`contact:read`, `transaction:read`) on
    /// [`SystemGroup::AllContacts`].
    AllUsers,
    /// User group containing every wallet owner. Granted all actions on
    /// [`SystemGroup::AllContacts`] at wallet creation time.
    Owners,
    /// Contact group containing every contact in the wallet — the
    /// resolver treats it as a wildcard scope when computing reach.
    AllContacts,
}

impl SystemGroup {
    /// Database / wire-format name. Matches `user_groups.name` /
    /// `contact_groups.name` in the system rows.
    pub fn as_str(&self) -> &'static str {
        match self {
            SystemGroup::AllUsers => "all_users",
            SystemGroup::Owners => "__owners__",
            SystemGroup::AllContacts => "all_contacts",
        }
    }

    /// Parse a name back into a [`SystemGroup`]. Returns `None` for
    /// non-system names (custom user/contact groups).
    pub fn from_str(s: &str) -> Option<Self> {
        match s {
            "all_users" => Some(SystemGroup::AllUsers),
            "__owners__" => Some(SystemGroup::Owners),
            "all_contacts" => Some(SystemGroup::AllContacts),
            _ => None,
        }
    }

    /// Which group kind this is. Used at the type boundary when handing
    /// a [`SystemGroup`] to code that only accepts one kind.
    pub fn kind(&self) -> SystemGroupKind {
        match self {
            SystemGroup::AllUsers | SystemGroup::Owners => SystemGroupKind::UserGroup,
            SystemGroup::AllContacts => SystemGroupKind::ContactGroup,
        }
    }

    /// Every variant. Useful for wallet initialization (`for g in
    /// SystemGroup::all() { seed g }`) and exhaustive tests.
    pub fn all() -> &'static [SystemGroup] {
        &[
            SystemGroup::AllUsers,
            SystemGroup::Owners,
            SystemGroup::AllContacts,
        ]
    }
}

impl fmt::Display for SystemGroup {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.as_str())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn roundtrip_as_str_from_str() {
        for g in SystemGroup::all() {
            assert_eq!(SystemGroup::from_str(g.as_str()), Some(*g));
        }
    }

    #[test]
    fn from_str_rejects_custom_names() {
        assert_eq!(SystemGroup::from_str("Team 1"), None);
        assert_eq!(SystemGroup::from_str(""), None);
        assert_eq!(SystemGroup::from_str("owners"), None); // missing __
    }

    #[test]
    fn kinds_are_correct() {
        assert_eq!(SystemGroup::AllUsers.kind(), SystemGroupKind::UserGroup);
        assert_eq!(SystemGroup::Owners.kind(), SystemGroupKind::UserGroup);
        assert_eq!(
            SystemGroup::AllContacts.kind(),
            SystemGroupKind::ContactGroup
        );
    }
}
