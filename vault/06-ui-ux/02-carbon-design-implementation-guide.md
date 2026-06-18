# IBM Carbon Design Implementation Guide

**Branch**: `flutter/carbon-redesign`  
**Reference**: https://carbon.ibm.com  
**Dart Integration**: Use official Carbon Dart packages or implement tokens directly

## IBM Carbon Design System Overview

IBM Carbon is a comprehensive, open-source design system for enterprise applications. It provides:

- **Design tokens**: Color, typography, spacing, motion, shadows
- **Component library**: Pre-built, accessible UI components
- **Patterns**: Common interaction patterns and layouts
- **Guidelines**: Accessibility (WCAG AA), usability, design principles

## Key Design Principles

### 1. Purpose (Not Decoration)
- Every design decision should serve a purpose
- No excessive ornamentation
- Clear information hierarchy

### 2. Legibility & Readability
- **Typography**: Use Carbon's type scale (size, weight, line-height are all part of the scale)
- Never mix font sizes arbitrarily—use the defined scale
- Sufficient contrast ratios (WCAG AA minimum 4.5:1 for text)

### 3. Consistency
- Use Carbon components as-is; don't create custom variations
- Consistent spacing using 4pt or 8pt grid
- Consistent interaction patterns across app

### 4. Accessibility First
- Semantic HTML / Flutter widget structure
- Keyboard navigation throughout
- Screen reader support (alt text, labels)
- Color + text/icon for status indicators
- Motion respects `prefers-reduced-motion` (if Flutter supports)

### 5. Density & Breathing Room
- Normal density: 16px/24px spacing for most UIs
- Compact density: 12px/16px for data-heavy tables
- Never compress below readability

## Carbon Design Tokens

### Color Palette

#### Interactive Colors
- **Interactive**: Primary action buttons (typically blue in light, inverted in dark)
- **Interactive hover**: Darker shade for hover state
- **Interactive active**: Darkest shade for pressed state

#### Semantic Colors
- **Success**: Green (✓, positive feedback)
- **Warning**: Yellow/orange (⚠, attention needed)
- **Error**: Red (✗, error state)
- **Info**: Blue/cyan (ℹ, informational)

#### Neutrals
- **Background**: Off-white/light gray (light theme), very dark gray (dark theme)
- **Surface**: Cards, panels (lighter than background in light theme)
- **Border**: Subtle dividers and borders
- **Text**: High contrast text for readability

### Typography Scale

Carbon defines a strict type scale:

| Role | Size | Weight | Line Height | Usage |
|---|---|---|---|---|
| Display | 56px–32px | 400, 600 | Tight | Page titles, hero sections |
| Heading | 28px–20px | 400, 600 | 1.25 | Section headers |
| Body | 16px, 14px | 400, 500 | 1.5 | Body text, paragraphs |
| Label | 14px, 12px | 600 | 1.5 | Form labels, buttons |
| Code | Monospace 12px–14px | 400 | 1.5 | Inline code, logs |

**Rule**: Never define custom type sizes. Use Carbon's scale exclusively.

### Spacing System

Carbon uses an **8px base unit** (or 4px for finer control):

- **Horizontal/vertical padding on elements**: 8px, 16px, 24px, 32px (multiples of 8)
- **Gaps between elements**: 8px, 12px, 16px, 24px
- **Large spacing**: 32px, 40px, 48px

**Rule**: All spacing should align to the 8px grid. Never use arbitrary padding like 15px or 7px.

### Shadows & Elevation

Carbon provides a shadow system for depth:

- **Subtle**: Used for floating elements (pop-up menus, modals)
- **Moderate**: Used for elevated cards or dialogs
- **High**: Reserved for top-level modals and critical UI

Use Carbon's shadow variables; don't define custom shadows.

## Component Library

### Buttons
- **Primary**: Interactive semantic color (blue), highest emphasis
- **Secondary**: Border/outline style, medium emphasis
- **Tertiary**: Minimal/ghost style, lowest emphasis
- **Danger**: Error color for destructive actions (delete, etc.)
- **Disabled state**: Always present and obvious

### Form Inputs
- **Text input**: Label above or floating, clear focus state, error state
- **Dropdown / Select**: Carbon's native select/combo-box
- **Checkbox**: Standard Carbon checkbox with label
- **Radio button**: Standard Carbon radio group
- **Date picker**: Carbon's date picker (if Flutter support exists)

### Cards
- **Structure**: Padding (16px or 24px), subtle shadow
- **Content**: Title, description, optional image, optional CTA
- **Interactive**: Clickable cards get hover/active states

### Lists
- **Simple list**: Text items with optional icons
- **Data list**: Structured rows with columns (use Table component for complex data)
- **Dividers**: Subtle 1px border between items

### Tables (for Permission Matrix, etc.)
- **Header**: Bold, semantic background
- **Rows**: Alternating subtle background (zebra striping optional)
- **Pagination**: If >50 rows, use Carbon's pagination component
- **Responsive**: Horizontal scroll on mobile if necessary

### Modals & Dialogs
- **Structure**: Title, content, action buttons (primary + secondary)
- **Size**: Use Carbon's predefined sizes (default, wide, narrow)
- **Backdrop**: Semi-transparent overlay
- **Dismiss**: Clear close button (X icon), Esc key, click-outside options

### Navigation
- **Tab bar**: For horizontal section switching (e.g., Contacts vs. Transactions)
- **Side navigation**: For mobile drawer or desktop sidebar (if design calls for it)
- **Breadcrumb**: For deep hierarchies (less common in mobile)

### Status Indicators
- **Icons**: Success (✓), warning (⚠), error (✗), info (ℹ)
- **Colors**: Always pair with text label, don't rely on color alone
- **Pulse/animation**: Subtle pulse for active/loading states (respect `prefers-reduced-motion`)

## Implementation in Flutter

### Recommended Approach

1. **Token definitions** (Dart constants or `theme_data.dart`):
   ```dart
   class CarbonColors {
     static const interactive = Color(0x0F62FE); // Carbon blue
     static const success = Color(0x24A148);
     static const warning = Color(0xF1C21B);
     static const error = Color(0xDA1E28);
     // ...
   }
   
   class CarbonSpacing {
     static const xs = 4.0;
     static const sm = 8.0;
     static const md = 16.0;
     static const lg = 24.0;
     static const xl = 32.0;
   }
   ```

2. **ThemeData setup**:
   - Use Flutter's `ThemeData` to define text styles, colors, component themes
   - Leverage `copyWith()` for light/dark mode

3. **Reusable component widgets**:
   - `CarbonButton` (with primary, secondary, tertiary, danger variants)
   - `CarbonInput` (with label, error, state handling)
   - `CarbonCard` (with padding, shadow, optional border)
   - Wrap Carbon principles into custom widgets

4. **Responsive layout**:
   - Use `MediaQuery` and `LayoutBuilder` for breakpoints
   - Mobile breakpoint: < 600dp width
   - Tablet: 600dp–1200dp
   - Desktop: > 1200dp

### Accessibility Checklist

- [ ] All text meets WCAG AA contrast (4.5:1 for normal text, 3:1 for large text)
- [ ] All interactive elements are keyboard-navigable (tab order is logical)
- [ ] Form fields have semantic labels (not just placeholders)
- [ ] Error messages are linked to form fields (`errorText` in Flutter)
- [ ] Icons have text labels or `semanticLabel` for screen readers
- [ ] Color is not the only way to convey status (use icons, text, patterns)
- [ ] Motion animations respect `MediaQuery.of(context).disableAnimations`

## Dark Mode & Theming

Carbon provides both light and dark color palettes:

- **Light mode**: Off-white background, dark text
- **Dark mode**: Dark gray/black background, light text
- **Interactive colors** are adjusted for contrast in each mode

Implement:

```dart
// In your theme setup
final isDark = brightness == Brightness.dark;
return ThemeData(
  brightness: brightness,
  primaryColor: isDark ? CarbonColors.darkInteractive : CarbonColors.interactive,
  scaffoldBackgroundColor: isDark ? CarbonColors.darkBg : CarbonColors.lightBg,
  // ... rest of theme
);
```

## Glitching Effect Integration Strategy

The current design has an animated glitching visual effect. To preserve this within Carbon's constraints:

### Option 1: Custom Overlay Widget
- Create a `GlitchEffect` widget that layers on top of Carbon components
- Use `CustomPaint` for distortion animations
- Keep glitch subtle and respect readability

### Option 2: Carbon Component Customization
- Extend Carbon buttons/text to have optional glitch shader
- Conditionally enable on specific UI elements (balance display, sync status)

### Option 3: Separate Accent Layer
- Keep core UI fully Carbon-compliant
- Add glitch as a secondary visual that doesn't interfere with legibility
- Example: Subtle animated noise or chromatic aberration on card backgrounds

**Recommendation**: Start with Option 3 (separate accent layer). It's easiest to implement and ensures Carbon design integrity isn't compromised.

## Resources

- **Carbon Design System**: https://carbon.ibm.com
- **Carbon color tokens**: https://carbondesignsystem.com/guidelines/color/usage/
- **Carbon typography**: https://carbondesignsystem.com/guidelines/typography/overview/
- **Carbon spacing**: https://carbondesignsystem.com/guidelines/spacing/overview/
- **Carbon components**: https://carbondesignsystem.com/components/overview/
- **Accessibility (WCAG)**: https://www.w3.org/WAI/WCAG21/quickref/

## Implementation Phases (Proposed)

### Phase 1: Foundation (Week 1)
- [ ] Define Carbon token constants in Dart
- [ ] Set up `ThemeData` with Carbon colors and typography
- [ ] Create base widgets: `CarbonButton`, `CarbonInput`, `CarbonCard`
- [ ] Test light and dark themes

### Phase 2: Core Screens (Week 2)
- [ ] Login/auth screens (simplest to start)
- [ ] Wallet selection/dashboard summary
- [ ] Contacts list with search/sort
- [ ] Basic forms (add contact, add transaction)

### Phase 3: Complex Screens (Week 3)
- [ ] Permission matrix viewer and editor
- [ ] Transaction history with filters
- [ ] Settings screens
- [ ] Responsive refinement

### Phase 4: Polish & Effects (Week 4)
- [ ] Integrate glitching effect
- [ ] Dark mode testing and refinement
- [ ] Accessibility audit and fixes
- [ ] Animation polish (if needed)
- [ ] Performance optimization

### Phase 5: Testing & Refinement
- [ ] Integration testing with Rust backend
- [ ] Real data testing
- [ ] Device/OS testing (Android, iOS, web)
- [ ] User feedback and iterations

## Common Pitfalls to Avoid

1. **Don't mix type scales**: Use Carbon's defined sizes, not arbitrary values
2. **Don't break the 8px grid**: Padding and margins should align to multiples of 8
3. **Don't use custom shadows**: Use Carbon's elevation system
4. **Don't ignore accessibility**: Color contrast, keyboard nav, screen reader support are non-negotiable
5. **Don't preserve old design decisions**: Layout, fonts, sizes are all replaced per the brief
6. **Don't over-customize**: Use Carbon components as-is; extension is OK, replacement is not

## Questions & Decisions

- **Typeface**: Carbon recommends IBM Plex (open-source). Should we use Plex in Flutter, or rely on system fonts with Carbon type scale?
- **Glitching effect placement**: Where should the glitch appear? Balance display? Status indicators? Background?
- **Navigation pattern**: Side drawer (mobile) or bottom tab bar? Top navigation?
- **Density**: Normal or compact spacing for data-heavy screens (transaction list, permission matrix)?
- **RTL support**: Maintain current RTL layout support in Carbon design?

These should be decided during Phase 1 (foundation setup).
