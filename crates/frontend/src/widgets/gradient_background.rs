use dioxus::prelude::*;
use crate::theme::AppColors;

#[component]
pub fn GradientBackground(is_dark: bool, children: Element) -> Element {
    let (bg_start, bg_end) = if is_dark {
        (AppColors::DARK_SURFACE, AppColors::DARK_SURFACE)
    } else {
        ("#E7E0EC", "#E7E0EC")
    };
    rsx! {
        div {
            style: "min-height: 100vh; background: linear-gradient(to bottom, {bg_start}, {bg_end});",
            {children}
        }
    }
}
