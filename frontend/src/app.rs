use dioxus::prelude::*;
use crate::event_store;
use crate::screens::{BackendSetupScreen, HomeScreen, LoginScreen};
use crate::state_builder;

#[derive(Clone, Copy, PartialEq)]
pub enum Route {
    Setup,
    Login,
    Home,
}

#[component]
pub fn App() -> Element {
    let mut route = use_signal(|| Route::Login);
    let is_dark = use_signal(|| true);

    let home_state = (route() == Route::Home).then(|| {
        let events = event_store::get_all_events();
        state_builder::build_state(&events)
    }).unwrap_or_default();

    let current_screen = match route() {
        Route::Setup => rsx! {
            BackendSetupScreen {
                is_dark: is_dark(),
                on_saved: move |_| route.set(Route::Login),
            }
        },
        Route::Login => rsx! {
            LoginScreen {
                is_dark: is_dark(),
                on_login_success: move |_| route.set(Route::Home),
                on_go_setup: move |_| route.set(Route::Setup),
            }
        },
        Route::Home => rsx! {
            HomeScreen {
                is_dark: is_dark(),
                app_state: home_state.clone(),
                on_logout: move |_| route.set(Route::Login),
            }
        },
    };

    rsx! {
        div { style: "font-family: system-ui, sans-serif;",
            {current_screen}
        }
    }
}
