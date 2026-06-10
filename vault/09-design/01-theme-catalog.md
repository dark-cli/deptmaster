---
tags:
  - design
  - mobile
  - themes
  - palette
---

# Theme Catalog

**Status:** Candidate palettes considered for the mobile app. None is committed as the production theme yet.

This catalog is a survey of color palettes evaluated for the Flutter mobile UI (and indirectly the Dioxus web UI, which inherits brand decisions). It is meant to be the single place to look when picking or proposing a new theme — palettes from prior design sessions live here instead of in one-off `*_THEME.md` files scattered around `mobile/`.

Each entry lists primary, secondary, background, and surface colors for both light and dark modes, with notes on what the palette feels like and where it fits.

---

## Conventional / professional palettes

Drawn from well-known design systems. High readability, broadly familiar, low risk for a financial app.

### 1. Material Design 3 — Blue (Google's default)
- Light primary: Blue 600 `#2563EB` · Secondary: Teal 500 `#14B8A6` · Background `#FFFFFF`
- Dark primary: same · Background: Gray 900 `#111827`
- Contrast: WCAG AAA · Feel: Professional, clean, widely recognized

### 2. Material Design 3 — Purple (Material You)
- Light primary: Purple 600 `#9333EA` · Secondary: Pink 500 `#EC4899` · Background `#FFFFFF`
- Dark primary: same · Background: Gray 900 `#111827`
- Contrast: WCAG AAA · Feel: Modern, vibrant, playful (Android 12+)

### 3. GitHub Dark/Light
- Light: Blue 600 `#0969DA` on `#FFFFFF`
- Dark: Blue 500 `#58A6FF` on `#0D1117`
- Contrast: Excellent (designed for code) · Feel: High-contrast, developer-friendly

### 4. Tailwind CSS default
- Light primary: Blue 600 `#2563EB` · Secondary: Indigo 600 `#4F46E5` · Background `#FFFFFF`
- Dark background: Slate 900 `#0F172A`
- Feel: Modern web aesthetic, clean

### 5. Apple Human Interface Guidelines
- Light: Blue `#007AFF` on `#FFFFFF`
- Dark: Blue `#0A84FF` on `#000000` (or System Gray 6)
- Feel: iOS-native; great for an iOS-first build

### 6. Discord
- Blurple `#5865F2` (both modes) · Dark background `#36393F`
- Feel: Social, high-visibility

### 7. Notion
- Blue 600 `#2383E2` (both modes) · Dark background `#2E2E2E` (warm dark gray)
- Feel: Soft on the eyes; productivity / long-reading

### 8. Linear
- Light: Purple 600 `#5E6AD2` on `#FFFFFF`
- Dark: Purple 500 `#8B5CF6` on `#0D0D0D`
- Feel: Modern SaaS, premium

### 9. VS Code "Dark+"
- Light: Blue 600 `#007ACC` on `#FFFFFF`
- Dark: Teal `#4EC9B0` on `#1E1E1E`
- Feel: Built for long, data-heavy sessions

### 10. High-Contrast (Accessibility-first)
- Light: Blue 700 `#0052CC` on `#FFFFFF`
- Dark: Yellow 400 `#FCD34D` on `#000000`
- Contrast: WCAG AAA+ · Feel: Maximum readability

---

## Warm / casual palettes

Same evaluation, but optimized for an approachable, "not-quite-a-bank" feel.

### 11. Sunset Orange 🌅
- Light: Orange 600 `#EA580C` + Amber 500 `#F59E0B` on warm white `#FFFBF7`
- Dark: Orange 400 `#FB923C` + Amber 400 `#FBBF24` on `#1C1917` (brown-tinted)
- Feel: Cozy, inviting; trust + warmth blend (good for financial-but-friendly)

### 12. Coffee Shop ☕
- Light: Brown 700 `#92400E` + Caramel `#D97706` on cream `#FEF9F3`
- Dark: Brown-tinted `#1A1612` surface, amber accents
- Feel: Comfortable, café-like

### 13. Warm Sage Green 🌿
- Light: Green 600 `#16A34A` + Teal 500 `#14B8A6` on `#FAFAF9`
- Dark: Green 400 `#4ADE80` on `#0F1B15`
- Feel: Natural, calming, organic

### 14. Warm Purple / Lavender 💜
- Light: Purple 600 `#9333EA` + Pink 500 `#EC4899` on `#FDF4FF`
- Dark: Purple 400 `#C084FC` on deep purple `#1A0B2E`
- Feel: Creative, friendly, artistic

### 15. Autumn / Warm Earth 🍂
- Light: Burnt orange `#C2410C` + Golden amber on cream `#FFF8F0`
- Dark: Orange 500 `#F97316` on `#1A1612`
- Feel: Earthy, grounded

### 16. Peach & Coral 🍑
- Light: Orange 500 `#F97316` + Rose 500 `#F43F5E` on peach `#FFF5F0`
- Dark: Orange 400 + Rose 400 on `#1F1614`
- Feel: Playful, energetic

---

## Reference inspiration — kaleem.dev

A specific reference design pulled from the kaleem.dev portfolio site. Same orange-on-clean-neutral language as #11/#15 above but with a deeper, more saturated accent.

| | Light | Dark |
|---|---|---|
| Accent | `#E65F1E` / `#D35400` (deep orange-red) | `#FF8147` / `#F28C38` |
| Background | `#F9F9F9` / `#FAFAFA` | `#1C1C1C` / `#0F0F0F` |
| Surface | `#FFFFFF` | `#2A2A2A` |
| Text primary | `#333333` / `#2B2B2B` | `#EFEFEF` / `#F5F5F5` |
| Text secondary | `#777777` | `#CCCCCC` |

**Feel:** clean, minimal, warm accent that "really pops" against the neutral; professional-but-approachable.

---

## Quick comparison

| Palette | Readability | Professional | Modern | Warmth |
|---|:---:|:---:|:---:|:---:|
| Material Blue (#1) | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐ |
| GitHub (#3) | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐ |
| Notion (#7) | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ |
| Linear (#8) | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐ |
| High-Contrast (#10) | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐ | ⭐ |
| Sunset Orange (#11) | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| Coffee Shop (#12) | ⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| Warm Sage (#13) | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ |
| Kaleem.dev | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ |

---

## Notes for picking

- Anything chosen must hit at least **WCAG AA** for body text in both modes. The high-contrast and Material entries already pass AAA.
- For a financial-but-friendly product, the warm orange/amber family (#11, #15, kaleem.dev) tends to read as "approachable but trustworthy" without going into bank-blue formality.
- For maximum reach and least surprise, the Material Blue (#1) or Notion (#7) palettes are the safest defaults.
- When implementing, generate the full tonal scale (10 steps) from the primary so component theming has the shades it needs, not just primary + 2.
