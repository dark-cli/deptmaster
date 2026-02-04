use dioxus::prelude::*;
use crate::models::{Transaction, TransactionDirection};
use crate::widgets::{GradientBackground, GradientCard};

fn direction_color(d: TransactionDirection) -> &'static str {
    match d {
        TransactionDirection::Lent => "#029C76",
        TransactionDirection::Owed => "#BA1A1A",
    }
}

#[component]
pub fn TransactionsScreen(is_dark: bool, transactions: Vec<Transaction>) -> Element {
    let on_surface = if is_dark { "#E6E1E5" } else { "#1C1B1F" };

    rsx! {
        GradientBackground { is_dark,
            div { style: "padding: 24px;",
                h1 { style: "color: {on_surface}; margin-bottom: 24px;", "Transactions" }
                if transactions.is_empty() {
                    GradientCard { is_dark,
                        p { style: "color: {on_surface}; opacity: 0.8;", "No transactions yet." }
                    }
                } else {
                    for txn in transactions.iter() {
                        GradientCard { is_dark,
                            div { style: "display: flex; justify-content: space-between; align-items: center;",
                                span { style: "color: {on_surface};",
                                    "{txn.description.as_deref().unwrap_or(\"-\")}"
                                }
                                span {
                                    style: "color: {direction_color(txn.direction)}; font-weight: 500;",
                                    "{txn.formatted_amount()}"
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
