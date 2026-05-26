use dioxus::prelude::*;
use crate::screens::{ContactsScreen, DashboardScreen, TransactionsScreen};
use crate::state_builder::AppState;

#[derive(Clone, Copy, PartialEq)]
pub enum HomeTab {
    Contacts,
    Transactions,
    Dashboard,
}

#[component]
pub fn HomeScreen(
    is_dark: bool,
    app_state: AppState,
    on_logout: EventHandler<()>,
) -> Element {
    let mut tab = use_signal(|| HomeTab::Dashboard);
    let text_color = if is_dark { "#E6E1E5" } else { "#1C1B1F" };
    let active_bg = "#6750A4";
    let transparent = "transparent";
    let bg_contacts = if tab() == HomeTab::Contacts { active_bg } else { transparent };
    let bg_transactions = if tab() == HomeTab::Transactions { active_bg } else { transparent };
    let bg_dashboard = if tab() == HomeTab::Dashboard { active_bg } else { transparent };

    rsx! {
        div { style: "display: flex; flex-direction: column; height: 100vh;",
            div { style: "display: flex; padding: 12px 24px; gap: 12px; align-items: center; border-bottom: 1px solid #49454F; flex-shrink: 0;",
                button {
                    onclick: move |_| tab.set(HomeTab::Contacts),
                    style: "padding: 8px 16px; border-radius: 8px; border: none; cursor: pointer; background: {bg_contacts}; color: {text_color};",
                    "Contacts"
                }
                button {
                    onclick: move |_| tab.set(HomeTab::Transactions),
                    style: "padding: 8px 16px; border-radius: 8px; border: none; cursor: pointer; background: {bg_transactions}; color: {text_color};",
                    "Transactions"
                }
                button {
                    onclick: move |_| tab.set(HomeTab::Dashboard),
                    style: "padding: 8px 16px; border-radius: 8px; border: none; cursor: pointer; background: {bg_dashboard}; color: {text_color};",
                    "Dashboard"
                }
                div { style: "flex: 1;" }
                button {
                    onclick: move |_| on_logout.call(()),
                    style: "padding: 8px 16px; border-radius: 8px; border: 1px solid #938F99; background: transparent; color: #938F99; cursor: pointer;",
                    "Logout"
                }
            }
            div { style: "flex: 1; overflow: auto;",
                {match tab() {
                    HomeTab::Contacts => rsx! { ContactsScreen { is_dark, contacts: app_state.contacts.clone() } },
                    HomeTab::Transactions => rsx! { TransactionsScreen { is_dark, transactions: app_state.transactions.clone() } },
                    HomeTab::Dashboard => rsx! { DashboardScreen { is_dark, app_state: app_state.clone() } },
                }}
            }
        }
    }
}
