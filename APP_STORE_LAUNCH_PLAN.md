# Rocio App Store Launch Plan

Date: 2026-06-25

This plan starts from the current MVP in `juliosuas/rocio`: a working Spanish-first PWA for flower care with local garden tracking, flower catalog, scanner fallback, service worker, and Supabase/Plant.id proxy code.

## Brutally Honest Status

Rocio is not App Store-ready yet. It is a strong MVP, but it is currently a web app, not an iOS app. The next phase is to make it reviewable, testable, privacy-complete, and meaningfully native.

## Critical Blockers

1. No iOS project exists.
   - Need an Xcode project, bundle identifier, signing team, app icon set, launch screen, capabilities, and release scheme.

2. App Store Review risk: thin wrapper.
   - A simple WKWebView around `index.html` is likely too weak. The iOS version needs native value such as local notifications, App Intents, deep links, and eventually widgets.

3. Privacy materials are missing.
   - Need privacy policy, support URL, data collection summary, camera/photo explanation, notification explanation, and account/deletion story even if the app stays local-first.

4. Plant identification is not production-ready.
   - Supabase URL/key are currently blank in `index.html`.
   - Plant.id secret must stay server-side.
   - Scanner UX must keep uncertainty visible.
   - Review notes must explain that identification is assistive, not guaranteed.

5. Reminder reliability is not enough for iOS.
   - Browser notifications only fire under limited conditions.
   - Native local notifications should schedule watering reminders even when the app is closed.

6. Persistence is fragile for a store app.
   - `localStorage` is acceptable for MVP, but App Store users need reset/export/delete and eventually migration to native persistence or cloud sync.

7. Assets need release audit.
   - Photo attributions exist, but each image must be license-safe for App Store distribution.
   - Need App Store icon and screenshots.

8. QA is too narrow.
   - Existing classifier harness is good. Need CI, smoke tests, and native build checks once iOS exists.

## Garry Tan Tooling Context

The requested helper stack is external tooling, not app code:

- `garrytan/gstack` can guide planning, review, QA, shipping, and security workflows when installed in the agent environment.
- `garrytan/gbrain` can provide long-term memory/retrieval if we choose to deploy or connect it later.
- `garrytan/gbrain-evals` is useful context for evaluating GBrain itself, not a Rocio test suite.

Rocio's own project memory lives in `ROCIO_BRAIN.md` until a real GBrain integration exists.

## Launch Architecture Decision

Recommended path:

- Keep the PWA alive as the product prototype and web fallback.
- Add a native SwiftUI iOS app rather than only wrapping the web app.
- Use native persistence for saved garden plants in the iOS app.
- Reuse the flower catalog data by extracting it from `index.html` into a structured data file in a later PR.
- Use Supabase Edge Functions for Plant.id only when the provider is enabled.
- Add App Intents in the first iOS milestone, but keep the intent surface small.

## Milestone 0: Project Control

Goal: make the project reviewable before native work begins.

Acceptance criteria:

- `ROCIO_BRAIN.md` exists and defines product/technical decisions without conflating Rocio with `garrytan/gbrain`.
- `APP_STORE_LAUNCH_PLAN.md` exists and lists blockers.
- `AGENTS.md` exists with PR/review standards.
- GitHub Actions runs the existing strict classifier QA on PRs.
- PR template forces App Store/privacy/test notes.

## Milestone 1: Stabilize MVP For Migration

Goal: reduce risk in the current PWA before extracting native pieces.

Acceptance criteria:

- Flower catalog data is moved from inline JS into structured JSON or a small module.
- Local storage keys and data shapes are documented.
- User can delete garden data and scan history from the UI.
- Supabase/Plant.id configuration is documented without exposing secrets.
- QA covers the catalog data shape and classifier fallback.

## Milestone 2: Native iOS Foundation

Goal: create an iOS app that can build, run, and hold native state.

Acceptance criteria:

- Xcode project under `ios/`.
- SwiftUI app with Catalog, Garden, Calendar, Scanner placeholder, and Settings skeleton.
- Bundle id selected.
- App icon and launch screen included.
- Local persistence model for saved garden plants.
- Native local notification scheduling for watering reminders.
- Test target builds.

## Milestone 3: App Intents First Pass

Goal: expose useful system actions without creating a giant shortcut taxonomy.

Acceptance criteria:

- `OpenGardenIntent` opens the app to Mi Jardin.
- `LogWateringIntent` marks a selected saved garden plant as watered.
- `OpenScannerIntent` opens the scanner flow.
- `GardenPlantEntity` supports display and suggested entities.
- `AppShortcutsProvider` exposes clear Spanish phrases.
- App handles intent handoff through one central route.

## Milestone 4: TestFlight Readiness

Goal: make the app reviewable by a small external group.

Acceptance criteria:

- Archive build succeeds.
- TestFlight internal build uploaded.
- Privacy policy and support URL are live.
- App Store Connect metadata draft exists.
- Screenshots captured on required devices.
- Review notes explain camera, Plant.id, local reminders, and local-first data.
- No secrets in client code.

## Milestone 5: App Store Submission

Goal: submit a narrow, honest, polished v1.

Acceptance criteria:

- All launch blockers resolved or explicitly deferred outside App Store scope.
- Native iOS app provides value beyond the web app.
- App Review notes are written.
- Marketing copy avoids overclaiming identification accuracy.
- Release checklist is complete.

## Recommended First Real Feature PR After This One

Create the iOS project skeleton and native App Intents routing stub. Do not wire Plant.id yet. The first native PR should prove the app builds and opens to the right destinations before adding provider/network complexity.