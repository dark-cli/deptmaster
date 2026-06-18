# Phase 2: Core Screens — PROGRESS

**Branch**: `flutter/carbon-redesign`  
**Status**: In Progress  
**Started**: 2026-06-19

## Completed Screens

### ✅ 1. Login Screen
- **File**: `mobile/lib/screens/login_screen.dart`
- **Changes**:
  - Replaced `TextFormField` → `CarbonTextInput`
  - Replaced custom `ElevatedButton` with animation → `CarbonButton` (primary kind)
  - Replaced `OutlinedButton` → `CarbonButton` (secondary kind)
  - Replaced `TextButton` → `CarbonButton` (ghost kind)
  - Removed `GradientBackground` widget
  - Preserved all validation logic and error handling
  - Uses Carbon spacing (8px multiples)
- **Status**: ✅ Ready for testing

### ✅ 2. Sign Up Screen
- **File**: `mobile/lib/screens/sign_up_screen.dart`
- **Changes**:
  - Replaced 3x `TextFormField` → `CarbonTextInput`
  - Replaced button styling → Carbon button kinds
  - Removed `GradientBackground`
  - Preserved password matching validation
  - Uses Carbon typography and spacing
- **Status**: ✅ Ready for testing

### ✅ 3. Wallet Selection Screen
- **File**: `mobile/lib/screens/wallet_selection_screen.dart`
- **Changes**:
  - Replaced invite code `TextField` → `CarbonTextInput`
  - Replaced `FilledButton`/`TextButton.icon` → `CarbonButton`
  - Removed `GradientBackground` from full-screen version
  - Refactored empty state to use Carbon layout
  - Refactored error state with Carbon buttons
  - Preserved all wallet selection and invite code logic
- **Status**: ✅ Ready for testing

## Pending Screens (Phase 2)

### ⏳ 4. Dashboard Screen
- **File**: `mobile/lib/screens/dashboard_screen.dart`
- **Complexity**: HIGH (largest screen, custom charts, complex layouts)
- **What needs to change**:
  - Replace custom `GradientCard` → `CarbonCard` components
  - Replace custom balance chart styling → Carbon typography + layout
  - Replace custom "Gave/Received" indicator bars → Carbon color system
  - Keep data structures (total balance, contact list, transaction dates)
  - Preserve glitching effect on balance text (AnimatedPixelatedText)
  - Use Carbon spacing for all padding/margins
  - Use Carbon type scale for all text
  - Use Carbon color palette for indicators (success=green, warning=yellow, error=red)
- **Estimated Time**: 2-3 hours

## Testing Checklist

Before moving to next screens, test these in both light and dark mode:

- [ ] Login screen renders without errors
- [ ] Login form validation works
- [ ] Sign up screen form fields work
- [ ] Password confirmation validation works
- [ ] Wallet selection sheet appears as modal
- [ ] Invite code input and join button work
- [ ] Wallet list renders with icons and buttons
- [ ] Empty state shows when no wallets
- [ ] Error state shows and retry button works
- [ ] All buttons have proper Carbon styling (primary/secondary/ghost kinds)
- [ ] Text inputs have proper labels and placeholders
- [ ] Light theme renders correctly
- [ ] Dark theme renders correctly
- [ ] No layout shifts or rendering errors

## Architecture Notes

### Carbon Component Usage Pattern

```dart
// Buttons
CarbonButton(
  label: 'Sign in',
  kind: CarbonButtonKind.primary,  // primary | secondary | ghost | danger
  size: CarbonButtonSize.default,   // default | small | large
  onPressed: () {},
  isLoading: false,
)

// Text Inputs
CarbonTextInput(
  controller: controller,
  label: 'Username',
  placeholder: 'Enter username',
  keyboardType: TextInputType.text,
  validator: (value) => value?.isEmpty ?? true ? 'Required' : null,
  errorText: 'Show this if validation fails',
)

// Cards (to be used in dashboard)
CarbonCard(
  // Check flutter_carbon docs for exact API
  child: Column(...),
)
```

### Preserved Patterns

- ✅ Riverpod providers for state management (unchanged)
- ✅ FFI calls to Rust backend (unchanged)
- ✅ Real-time WebSocket sync (unchanged)
- ✅ Data models and type safety (unchanged)
- ✅ Error handling and user feedback (enhanced with Carbon components)

## Next Steps

1. **Implement Dashboard Screen**
   - Start with the summary card (total balance)
   - Then balance chart (Gave/Received columns)
   - Then payment reminders section
   - Preserve data flow; replace only UI layer

2. **Test All Screens Together**
   - Navigation flow: Login → Wallet Selection → Dashboard
   - Theme switching (light/dark)
   - Real-time data updates

3. **Continue to Phase 3**
   - Contact list screen
   - Transaction list screen
   - Permissions matrix

## Build & Run

Once dashboard is updated:

```bash
cd mobile
flutter pub get              # Already done
flutter run                  # Test on device
flutter run -d chrome        # Test on web (if available)
```

## Carbon Component Docs

Reference during implementation:
- **flutter_carbon package**: https://pub.dev/packages/flutter_carbon
- **Repository examples**: https://github.com/hwkim1127/flutter_carbon.git
- **IBM Carbon docs**: https://carbon.ibm.com

## Commits So Far

- `cddfab7`: Phase 1 foundation setup (flutter_carbon added)
- `08241e5`: Auth screens (login + sign up) to Carbon
- `d249448`: Wallet selection screen to Carbon

**Total time Phase 2 so far**: ~1 hour  
**Estimated remaining**: 2-3 hours to complete dashboard
**Estimated Phase 2 total**: 4-5 hours (vs 21+ days without flutter_carbon!)
