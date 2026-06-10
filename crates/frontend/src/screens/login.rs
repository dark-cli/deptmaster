use dioxus::prelude::*;
use crate::widgets::{GradientBackground, GradientCard};

#[component]
pub fn LoginScreen(
    is_dark: bool,
    on_login_success: EventHandler<()>,
    on_go_setup: EventHandler<()>,
) -> Element {
    let mut username = use_signal(|| "max".to_string());
    let mut password = use_signal(|| "12345678".to_string());
    let mut loading = use_signal(|| false);
    let mut error = use_signal(|| Option::<String>::None);

    let primary = if is_dark { "#D0BCFF" } else { "#6750A4" };
    let on_surface = if is_dark { "#E6E1E5" } else { "#1C1B1F" };

    rsx! {
        GradientBackground { is_dark,
            div { class: "safe-area", style: "padding: 24px 24px 16px; max-width: 400px; margin: 0 auto;",
                div { style: "text-align: center; margin-bottom: 24px;",
                    div { style: "font-size: 48px; color: {primary};", "💰" }
                    h1 { style: "font-size: 1.5rem; font-weight: bold; color: {on_surface}; margin: 16px 0 8px;", "Login" }
                    p { style: "color: {on_surface}; opacity: 0.8; font-size: 0.9rem;", "Enter your credentials to continue" }
                }
                GradientCard { is_dark,
                    form {
                        onsubmit: move |ev| { ev.prevent_default(); },
                        div { style: "margin-bottom: 16px;",
                            label { style: "display: block; margin-bottom: 4px; color: {on_surface}; font-size: 0.875rem;", "Username" }
                            input {
                                r#type: "text",
                                placeholder: "Username",
                                value: "{username()}",
                                oninput: move |ev| username.set(ev.value().clone()),
                                style: "width: 100%; padding: 12px; border-radius: 8px; border: 1px solid #938F99; background: transparent; color: {on_surface}; box-sizing: border-box;",
                            }
                        }
                        div { style: "margin-bottom: 16px;",
                            label { style: "display: block; margin-bottom: 4px; color: {on_surface}; font-size: 0.875rem;", "Password" }
                            input {
                                r#type: "password",
                                placeholder: "Password",
                                value: "{password()}",
                                oninput: move |ev| password.set(ev.value().clone()),
                                style: "width: 100%; padding: 12px; border-radius: 8px; border: 1px solid #938F99; background: transparent; color: {on_surface}; box-sizing: border-box;",
                            }
                        }
                        if let Some(ref e) = error() {
                            p { style: "color: #BA1A1A; font-size: 0.875rem; margin-bottom: 12px;", "{e}" }
                        }
                        button {
                            r#type: "submit",
                            disabled: loading(),
                            onclick: move |_| {
                                loading.set(true);
                                error.set(None);
                                let u = username().clone();
                                let p = password().clone();
                                spawn(async move {
                                    // TODO: call auth API
                                    if u == "max" && p == "12345678" {
                                        loading.set(false);
                                        on_login_success.call(());
                                    } else {
                                        loading.set(false);
                                        error.set(Some("Invalid credentials".to_string()));
                                    }
                                });
                            },
                            style: "width: 100%; padding: 12px; border-radius: 8px; background: {primary}; color: #381E72; font-weight: 600; border: none; cursor: pointer;",
                            if loading() { "Signing in…" } else { "Sign in" }
                        }
                    }
                }
                button {
                    onclick: move |_| on_go_setup.call(()),
                    style: "margin-top: 16px; background: none; border: none; color: {primary}; cursor: pointer; font-size: 0.9rem;",
                    "Configure backend"
                }
            }
        }
    }
}
