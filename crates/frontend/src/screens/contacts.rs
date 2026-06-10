use dioxus::prelude::*;
use crate::models::Contact;
use crate::widgets::{GradientBackground, GradientCard};

fn balance_color(b: i64) -> &'static str {
    if b >= 0 { "#029C76" } else { "#BA1A1A" }
}

#[component]
pub fn ContactsScreen(is_dark: bool, contacts: Vec<Contact>) -> Element {
    let on_surface = if is_dark { "#E6E1E5" } else { "#1C1B1F" };

    rsx! {
        GradientBackground { is_dark,
            div { style: "padding: 24px;",
                h1 { style: "color: {on_surface}; margin-bottom: 24px;", "Contacts" }
                if contacts.is_empty() {
                    GradientCard { is_dark,
                        p { style: "color: {on_surface}; opacity: 0.8;", "No contacts yet." }
                    }
                } else {
                    for contact in contacts.iter() {
                        GradientCard { is_dark,
                            div { style: "display: flex; justify-content: space-between; align-items: center;",
                                span { style: "font-weight: 600; color: {on_surface};", "{contact.name}" }
                                span {
                                    style: "color: {balance_color(contact.balance)}; font-weight: 500;",
                                    "{format_balance(contact.balance)} IQD"
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

fn format_balance(b: i64) -> String {
    let s = b.abs().to_string();
    let mut out = String::new();
    for (i, c) in s.chars().enumerate() {
        if i > 0 && (s.len() - i) % 3 == 0 {
            out.push(',');
        }
        out.push(c);
    }
    if b < 0 {
        format!("-{}", out)
    } else {
        out
    }
}
