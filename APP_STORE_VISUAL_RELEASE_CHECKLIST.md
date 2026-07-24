# Rocio App Store Visual Release Checklist

Date: 2026-07-24

Use this before TestFlight screenshots and before App Review submission.

## Screenshot Set

Capture five iPhone screenshots from the native app:

1. Catalog: filters visible, real flower photos, one flower already marked in the garden.
2. Garden: summary card, at least two saved flowers, one watering action visible.
3. Calendar: weekly watering schedule with saved plants.
4. Scanner: selected flower image, confidence band, candidates, and experimental copy, or the Review plant sheet with identity/source, confidence, specimen name, optional care, and Save to Garden.
5. Settings: reminders, local privacy copy, export data, delete local data.

Whichever scanner state is not selected for the five-image App Store set must still be retained as release-QA evidence. Record the result screen and the Review plant sheet from the exact Release candidate, followed by Garden after a successful save.

Current real-build documentation evidence, captured from the running iPhone 17 simulator on iOS 26.3 on 2026-07-22:

- `docs/screenshots/ios/catalog.png`
- `docs/screenshots/ios/garden.png`
- `docs/screenshots/ios/calendar.png`
- `docs/screenshots/ios/scanner.png`
- `docs/screenshots/ios/settings.png`

These are raw app screenshots, not mockups. The current scanner screenshot predates the Review plant sheet. Re-capture both scanner states and the final App Store set from the exact Release archive after the arbitrary-plant vertical is complete.

## Visual Quality Gate

- No clipped text at default Dynamic Type.
- No empty screen without a primary action.
- No card nested inside another card.
- Buttons use native icons for clear commands.
- Scanner never implies professional diagnosis or guaranteed identification.
- Privacy/export/delete are visible enough for App Review evidence.
- App icon renders sharply at 1024, 180, 120, 87, 80, 76, 60, 58, and 40 px.

## Asset License Gate

- Every flower photo used in App Store screenshots must have a source and license recorded in `PHOTO_ATTRIBUTIONS.md`.
- Replace any image whose source/license cannot be confirmed before final screenshots.
- Do not use competitor screenshots, competitor logos, or App Store badges without following their usage rules.

## Copy Gate

- Capture the primary App Store screenshot set in English, then verify the Spanish localized set for the same layouts.
- Avoid "precise AI", "diagnosis", "guaranteed", or "perfect identification".
- Prefer "candidates", "experimental scanner", "synchronized garden", "secure account", and "local reminders".
