# Phase 1: Foundation Setup — COMPLETE

**Branch**: `flutter/carbon-redesign`  
**Commit**: cddfab7  
**Status**: ✅ Complete  
**Completed**: 2026-06-19

## What Was Done

### 1. Added flutter_carbon Package
- **pubspec.yaml**: Added `flutter_carbon: ^1.2.1`
- **Source**: https://pub.dev/packages/flutter_carbon
- **Provides**: 48 pre-built Carbon components, 4 themes, full theming system

### 2. Updated main.dart
- Removed: Custom `AppTheme` (app_theme.dart)
- Added: `import 'package:flutter_carbon/carbon.dart'`
- Updated: Theme setup uses `CarbonTheme.light()` and `CarbonTheme.dark()`
- Maintained: All existing routing, initialization, and provider setup

### 3. Theme Integration
```dart
// Before
theme: AppTheme.lightTheme,
darkTheme: AppTheme.darkTheme,

// After
theme: CarbonTheme.light(),
darkTheme: CarbonTheme.dark(),
```

## Current State

- ✅ Dependency added to pubspec.yaml
- ✅ Theme provider integrated into MaterialApp
- ✅ Light and dark mode support configured
- ⏳ **Pending**: `flutter pub get` to fetch dependencies (user runs this)
- ⏳ **Pending**: Test build and theme rendering

## Next Steps: Phase 2 (Core Screens)

Once dependencies are fetched and theme compiles successfully, implement:

1. **Update Login Screen**
   - Use `CarbonButton` for sign-in button
   - Use `CarbonTextInput` for username/password fields
   - Use Carbon's form validation
   - Keep layout simple (login is information-light)

2. **Update Wallet Selection Screen**
   - Use `CarbonCard` for wallet items
   - Use `CarbonButton` for "Create Wallet" CTA
   - Update to Carbon spacing/typography

3. **Update Dashboard Screen**
   - Replace custom cards with `CarbonCard`
   - Use Carbon's color palette for balance indicators
   - Replace custom chart with Carbon-compliant layout
   - Keep data structure the same (total balance, outstanding balances, payment reminders)

### Testing Checklist for Phase 2

- [ ] Light theme renders without errors
- [ ] Dark theme renders without errors
- [ ] Carbon typography scales correctly (use type scale, not custom sizes)
- [ ] Carbon spacing aligns to 8px grid
- [ ] Colors match Carbon palette (no custom color overrides)
- [ ] RTL text direction still works (app supports Arabic)
- [ ] Sync status icon and real-time indicators work
- [ ] No design regressions on existing screens

## Important Notes

### Screens NOT Updated Yet
The following screens still use old theme and components:
- Home/Dashboard screen (needs Phase 2)
- Contacts screen
- Transactions screen
- Add/edit screens
- Settings screen
- Permission matrix
- Events log

They will continue to render using Material default theme until updated in Phase 2-4.

### Preserving Functionality
- All Rust backend FFI calls unchanged
- All provider state management (Riverpod) unchanged
- All real-time WebSocket sync unchanged
- All data models unchanged
- Only UI layer is being replaced

### Glitching Effect
- Not yet integrated (Phase 4)
- Will be added as a custom overlay/animation layer on top of Carbon components
- Must not interfere with readability or accessibility

## Build Commands

Once Phase 1 is complete and you want to test:

```bash
cd mobile
flutter pub get              # Fetch flutter_carbon and dependencies
flutter run                  # Test on connected device/emulator
flutter run -d chrome        # Test on web (if available)
flutter pub upgrade          # (Later) Update to newer Carbon versions
```

## Files Changed

- `mobile/pubspec.yaml` — Added flutter_carbon dependency
- `mobile/lib/main.dart` — Updated imports and theme setup
- `mobile/lib/utils/app_theme.dart` — No longer used (can delete after Phase 2 confirms no breakage)

## Carbon Design System Resources

- **Official Documentation**: https://carbon.ibm.com
- **flutter_carbon Repository**: https://github.com/hwkim1127/flutter_carbon.git
- **Component List**: Check repo examples/ for component showcase
- **Color Tokens**: Carbon provides semantic color tokens (interactive, success, warning, error, etc.)
- **Typography**: Use Carbon's type scale only (no custom sizes)
- **Spacing**: Grid is 8px-based

## Next Instruction

Once you've run `flutter pub get` and confirmed the build compiles, let me know and we'll start Phase 2: Core Screens (login, wallet selection, dashboard).

Estimated Phase 2 duration: 3-4 days
