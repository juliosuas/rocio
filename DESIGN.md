# Rocio Design System

Rocio is a native flower-care companion. The interface should feel botanical,
editorial, calm, and precise. It must never resemble a generic AI dashboard or a
web page placed inside an iPhone shell.

## Principles

1. Show the flower first. Real, licensed photography is the primary visual signal.
2. Make care status scannable. Watering urgency and the next action should be clear
   without opening a detail screen.
3. Keep claims honest. Scanner confidence, provider, consent, and fallbacks remain
   visible and understandable.
4. Follow iOS conventions. Use SF Symbols, native navigation, sheets, forms, dynamic
   type, and controls with at least 44-point touch targets.
5. Prefer hierarchy over decoration. Avoid gradients, ornamental blobs, oversized
   cards, cards inside cards, and excessive rounded containers.

## Visual Language

- Display type: system serif, semibold, reserved for Rocio and screen-level titles.
- Interface type: San Francisco system fonts for controls, labels, and body copy.
- Leaf deep: primary actions and strong botanical surfaces.
- Teal: water, scanner device processing, and healthy care states.
- Rose: flowers, attention, and cloud AI accents.
- Amber: care that is due soon and low-confidence scanner states.
- Warm canvas: app background. White: elevated interactive surfaces.
- Corners: 8 points maximum for cards, images, fields, and buttons. Pills and circles
  are reserved for filters, compact statuses, and familiar icon actions.
- Spacing: 4, 8, 12, 16, 20, 24. Screen gutters are 16 or 20 points.

Exact SwiftUI tokens live in
`ios/Rocio/Views/Components/DesignSystem.swift`.

## Screen Rules

- Authentication and onboarding use one real flower image as the opening signal.
- Catalog uses a two-column photo grid and horizontally scrolling filter chips.
- Flower detail uses a full-width image, a compact care metric grid, then unframed
  editorial sections separated by dividers.
- My Garden begins with one status surface and lists plants with a single primary
  care action.
- Calendar highlights today, shows a seven-day horizon, and supports one-tap watering.
- Scanner uses a stable 4:3 capture stage. Experimental status and confidence cannot
  be hidden by visual polish.
- Settings stays a native Form. Privacy and destructive actions remain explicit.

## Release Review

Verify at 390x844 and 430x932, with English and Spanish, default and accessibility
text sizes, light and dark system appearance, empty and populated gardens, long flower
names, offline sync, denied camera access, and every scanner confidence state.
