//! App theme: colors and spacing (ported from Flutter app_colors, app_spacing).

/// Material Design 3–style colors. Light/dark selected at runtime.
#[derive(Clone, Copy)]
pub struct AppColors;

impl AppColors {
    // Light
    pub const LIGHT_PRIMARY: &'static str = "#6750A4";
    pub const LIGHT_SURFACE: &'static str = "#FFFBFE";
    pub const LIGHT_ON_SURFACE: &'static str = "#1C1B1F";
    pub const LIGHT_SUCCESS: &'static str = "#029C76";
    pub const LIGHT_ERROR: &'static str = "#BA1A1A";

    // Dark
    pub const DARK_PRIMARY: &'static str = "#D0BCFF";
    pub const DARK_SURFACE: &'static str = "#1C1B1F";
    pub const DARK_ON_SURFACE: &'static str = "#E6E1E5";
    pub const DARK_SUCCESS: &'static str = "#029C76";
    pub const DARK_ERROR: &'static str = "#FFB4AB";

    pub fn primary(is_dark: bool) -> &'static str {
        if is_dark {
            Self::DARK_PRIMARY
        } else {
            Self::LIGHT_PRIMARY
        }
    }
    pub fn surface(is_dark: bool) -> &'static str {
        if is_dark {
            Self::DARK_SURFACE
        } else {
            Self::LIGHT_SURFACE
        }
    }
    pub fn on_surface(is_dark: bool) -> &'static str {
        if is_dark {
            Self::DARK_ON_SURFACE
        } else {
            Self::LIGHT_ON_SURFACE
        }
    }
    pub fn success(is_dark: bool) -> &'static str {
        if is_dark {
            Self::DARK_SUCCESS
        } else {
            Self::LIGHT_SUCCESS
        }
    }
    pub fn error(is_dark: bool) -> &'static str {
        if is_dark {
            Self::DARK_ERROR
        } else {
            Self::LIGHT_ERROR
        }
    }
}

/// 8dp grid spacing (Material 3).
pub mod spacing {
    pub const XS: &'static str = "4px";
    pub const SM: &'static str = "8px";
    pub const MD: &'static str = "16px";
    pub const LG: &'static str = "24px";
    pub const XL: &'static str = "32px";
    pub const CARD_PADDING: &'static str = "16px";
    pub const SCREEN_PADDING: &'static str = "16px";
}
