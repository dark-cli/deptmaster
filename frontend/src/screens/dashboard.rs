use dioxus::prelude::*;
use crate::state_builder::AppState;
use crate::widgets::{GradientBackground, GradientCard};

#[component]
pub fn DashboardScreen(is_dark: bool, app_state: AppState) -> Element {
    let on_surface = if is_dark { "#E6E1E5" } else { "#1C1B1F" };
    let total_balance: i64 = app_state.contacts.iter().map(|c| c.balance).sum();
    let contact_count = app_state.contacts.len();
    let transaction_count = app_state.transactions.len();
    let balance_color = if total_balance >= 0 { "#029C76" } else { "#BA1A1A" };

    rsx! {
        GradientBackground { is_dark,
            div { style: "padding: 24px;",
                h1 { style: "color: {on_surface}; margin-bottom: 24px;", "Dashboard" }
                GradientCard { is_dark,
                    h2 { style: "color: {on_surface}; font-size: 1rem; margin-bottom: 8px;", "Net balance" }
                    p { style: "font-size: 1.5rem; font-weight: bold; color: {balance_color};",
                        "{format_number(total_balance)} IQD"
                    }
                }
                GradientCard { is_dark,
                    p { style: "color: {on_surface};", "Contacts: {contact_count}" }
                    p { style: "color: {on_surface};", "Transactions: {transaction_count}" }
                }
            }
        }
    }
}

fn format_number(n: i64) -> String {
    let s = n.abs().to_string();
    let mut out = String::new();
    for (i, c) in s.chars().enumerate() {
        if i > 0 && (s.len() - i) % 3 == 0 {
            out.push(',');
        }
        out.push(c);
    }
    if n < 0 {
        format!("-{}", out)
    } else {
        out
    }
}
