---
tags:
  - design
  - mobile
  - animation
  - motion
---

# Animation & Motion Guidelines

**Status:** Mixed. The "Principles", "Page transitions", and "Micro-interactions" sections are wishlist (from the prior design audit). The **Glitch motion vocabulary** section is implemented and shipping in `mobile/lib/widgets/`.

Companion to [[01-theme-catalog]] — themes give the *look*, this gives the *behavior over time*.

---

## Principles

- **Motion follows Material Design 3.** Easing curves, durations, and shared-element behavior should match what users already expect from native Android. iOS-only animations are fine for iOS-only screens.
- **60fps or it's broken.** A janky animation is worse than no animation. If a transition can't hold 60fps on the target devices, simplify it or remove it.
- **Animations communicate, they don't decorate.** Every motion should answer "what happened?" or "where am I?" — never just "look at this pretty thing."

---

## Page transitions

- Use Material motion for navigation pushes/pops. Standard shared-axis or fade-through for sibling routes; container transform when a list item expands into its detail view.
- **Shared element transitions** for contact-row → contact-detail and transaction-row → transaction-detail. The avatar / amount should feel like it travels, not redraw.
- Navigation between bottom-nav tabs is instant (no slide); navigation deeper than that is animated.

## Micro-interactions

| Surface | Behavior |
|---|---|
| Buttons | Press scales to ~0.97 with 150 ms ease-out; release returns with 100 ms ease-in. Ripple stays Material default. |
| List rows | Insertion: fade + slide-up 250 ms. Deletion: fade + slide-down 200 ms (during the soft-delete flow). Reorder uses Material's drag handle animation. |
| Swipe actions | The action color reveal tracks the finger 1:1 (no animation). On release-to-commit, the row slides off-screen in 200 ms. |
| Loading | Skeleton screens (shimmering placeholders) for the contact list and transaction list while events replay locally. Avoid spinners except for explicit user-triggered network calls. |
| Success / error | Inline toast or chip with a 200 ms fade-in; auto-dismiss in 3 s with fade-out. Errors stay until tapped. |

## Numbers and balances

Animated transitions when a balance changes — count up/down from old → new value over ~400 ms with `Curves.easeOut`. Applies to:

- Dashboard "Total balance" card
- Per-contact balance row when a new transaction lands
- Per-wallet stats after a sync

These transitions matter most after a sync completes — they're how the user perceives "something happened from the server."

## Theme transitions

When the user toggles light/dark, animate the color crossfade (don't snap). 300 ms is enough; longer feels sluggish.

---

## Glitch motion vocabulary (implemented)

The app has a distinctive "digital signal failure / chromatic aberration" motion language for value changes. The aesthetic is intentional — when a balance or a transaction list updates, the UI briefly **glitches** rather than fading: text shakes, color channels split, random scramble characters flash in. It reads as "the world just changed" louder than a fade does.

The vocabulary is implemented as a small set of composable widgets in `mobile/lib/widgets/`:

### `GlitchScrambleOverlay`
The visual primitive. Paints random characters (default set: `@#$%^&*`) across its bounds at a controllable `intensity` (0.0–1.0), `seed`, font size, and opacity. Used as a layer on top of changing content during a transition.

### `GlitchTransition`
Wraps a single child with an `Animation<double>`. While animating: applies translation jitter (default `maxX = 4 px`, `maxY = 2 px`), random opacity flicker (20% chance per frame, drops to 0.6), and optionally overlays `GlitchScrambleOverlay`. Lightweight — does not duplicate the child widget tree.

### `AnimatedPixelatedText`
Text widget that transitions value changes with chromatic-aberration: separates the red and blue color channels and shakes them independently for 400 ms while a scramble overlay (6–10 chars from `@#$%^&*`) flashes. Optional `animateFromEmpty` plays the same effect when text first appears from empty. This is the headline glitch effect — most visible on dashboard balances and transaction amounts.

### `FlashOnChange`
Wraps a child + a `signature` value. When the signature changes, fires a 250 ms flash overlay (color or glitch flavor, configurable). Used on list rows to say "this row just updated" without rebuilding the list. Token-based — first build and selection toggles don't fire it; only real signature changes do.

### `DiffAnimatedList`
Not glitch-specific, but it's the partner widget. Diffs a `List<T>` by stable item id and animates insertions / removals via Flutter's `AnimatedList`. Default duration 800 ms. Reorders can be disabled (`animateReorder: false`) to avoid moves when the list shuffles for non-meaningful reasons. Pairs with `FlashOnChange` inside each item builder so existing items can glitch while new ones slide in.

### Where it's used
Dashboard, contacts list, contact-transactions screen, transactions list, and the contact list item itself. Triggered by sync completion, by event replay landing a new value, and by signature changes on individual rows.

### When to reach for it
Use the glitch family when the change is **data-driven** and represents real world state moving (a balance updates, a new transaction lands, a contact's permissions change). Don't use it for navigation, button presses, or anything where the user did the thing — those are micro-interactions and belong in the Material vocabulary above. Mixing the two languages on the same screen weakens both.

### Tuning knobs
All effects expose their intensity, duration, and seed parameters. The defaults are conservative on purpose (`maxX = 4` not `12`; flicker 20% not 40%) — these were reduced from earlier values that felt too aggressive. If new screens want a louder glitch, prefer increasing duration over increasing per-frame intensity; it's the difference between "system blip" and "something is broken."

## Performance budget

- **All animations: 60fps target.** Profile with Flutter DevTools when a screen feels heavy.
- **Don't animate above the fold during initial load.** Skeleton in, then content, then optional intro animation — not all three at once.
- **Defer expensive work.** Image decoding, large lists, sync triggers all wait until the inbound animation completes (`addPostFrameCallback`).
- **Test on a low-end Android device**, not just the emulator. The 60fps budget is real and easy to blow.

---

## Out of scope (for now)

These are tempting but explicitly deferred:

- Hero parallax effects between screens
- Lottie / Rive animations for empty states (use static illustrations + skeleton)
- Pull-to-refresh custom animations (use Flutter's default `RefreshIndicator`)
- Page transitions tied to scroll position

If any of these become a priority, capture the reason here and move them out of this section.
