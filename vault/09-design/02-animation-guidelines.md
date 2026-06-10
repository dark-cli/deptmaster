---
tags:
  - design
  - mobile
  - animation
  - motion
---

# Animation & Motion Guidelines

**Status:** Wishlist captured from the prior design audit (formerly `mobile/DESIGN_MODERNIZATION_PLAN.md`). These are targets for the Flutter UI, not implemented contracts. Use them as the brief when adding new screens or polishing existing ones.

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
