use dioxus::prelude::*;
use crate::theme::spacing;

#[component]
pub fn GradientCard(is_dark: bool, children: Element) -> Element {
    let surface = if is_dark { "rgba(73,69,79,0.9)" } else { "rgba(255,255,255,0.95)" };
    rsx! {
        div {
            style: "background: {surface}; border-radius: 12px; padding: {spacing::CARD_PADDING}; margin: {spacing::SM};",
            {children}
        }
    }
}
