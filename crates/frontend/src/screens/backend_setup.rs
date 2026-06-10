use dioxus::prelude::*;
use crate::widgets::{GradientBackground, GradientCard};

#[component]
pub fn BackendSetupScreen(
    is_dark: bool,
    on_saved: EventHandler<()>,
) -> Element {
    let mut ip = use_signal(|| "127.0.0.1".to_string());
    let mut port = use_signal(|| "8000".to_string());
    let mut error = use_signal(|| Option::<String>::None);
    let mut success = use_signal(|| Option::<String>::None);
    let mut testing = use_signal(|| false);

    let on_surface = if is_dark { "#E6E1E5" } else { "#1C1B1F" };
    let primary = if is_dark { "#D0BCFF" } else { "#6750A4" };

    rsx! {
        GradientBackground { is_dark,
            div { style: "padding: 24px; max-width: 480px; margin: 0 auto;",
                h1 { style: "color: {on_surface}; margin-bottom: 8px;", "Backend setup" }
                p { style: "color: {on_surface}; opacity: 0.8; margin-bottom: 24px; font-size: 0.9rem;",
                    "Set the IP and port of your Debitum API server."
                }
                GradientCard { is_dark,
                    div { style: "margin-bottom: 16px;",
                        label { style: "display: block; margin-bottom: 4px; color: {on_surface};", "IP address" }
                        input {
                            r#type: "text",
                            placeholder: "127.0.0.1",
                            value: "{ip()}",
                            oninput: move |ev| ip.set(ev.value().clone()),
                            style: "width: 100%; padding: 12px; border-radius: 8px; border: 1px solid #938F99; background: transparent; color: {on_surface}; box-sizing: border-box;",
                        }
                    }
                    div { style: "margin-bottom: 16px;",
                        label { style: "display: block; margin-bottom: 4px; color: {on_surface};", "Port" }
                        input {
                            r#type: "text",
                            placeholder: "8000",
                            value: "{port()}",
                            oninput: move |ev| port.set(ev.value().clone()),
                            style: "width: 100%; padding: 12px; border-radius: 8px; border: 1px solid #938F99; background: transparent; color: {on_surface}; box-sizing: border-box;",
                        }
                    }
                    if let Some(ref e) = error() {
                        p { style: "color: #BA1A1A; font-size: 0.875rem; margin-bottom: 12px;", "{e}" }
                    }
                    if let Some(ref s) = success() {
                        p { style: "color: #029C76; font-size: 0.875rem; margin-bottom: 12px;", "{s}" }
                    }
                    div { style: "display: flex; gap: 12px;",
                        button {
                            disabled: testing(),
                            onclick: move |_| {
                                testing.set(true);
                                error.set(None);
                                success.set(None);
                                let i = ip().clone();
                                let pt = port().clone();
                                spawn(async move {
                                    let url = format!("http://{}:{}/health", i, pt);
                                    let res = reqwest::get(&url).await;
                                    testing.set(false);
                                    match res {
                                        Ok(r) if r.status().is_success() => {
                                            success.set(Some("Connection successful!".to_string()));
                                        }
                                        Ok(r) => {
                                            error.set(Some(format!("Server returned {}", r.status())));
                                        }
                                        Err(e) => {
                                            error.set(Some(e.to_string()));
                                        }
                                    }
                                });
                            },
                            style: "padding: 12px 24px; border-radius: 8px; background: #49454F; color: white; border: none; cursor: pointer;",
                            if testing() { "Testing…" } else { "Test connection" }
                        }
                        button {
                            onclick: move |_| {
                                // TODO: persist config then navigate to login
                                on_saved.call(());
                            },
                            style: "padding: 12px 24px; border-radius: 8px; background: {primary}; color: #381E72; font-weight: 600; border: none; cursor: pointer;",
                            "Save"
                        }
                    }
                }
            }
        }
    }
}
