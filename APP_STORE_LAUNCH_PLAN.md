# Rocio App Store Launch Plan

Date: 2026-06-28

This plan starts from the current MVP in `juliosuas/rocio`: a working Spanish-first PWA for flower care with local garden tracking, flower catalog, scanner fallback, service worker, and Supabase/Plant.id proxy code.

## Brutally Honest Status

Rocio is not App Store-ready yet, but it now has a native SwiftUI iOS foundation in this working tree. The next phase is not more concept work; it is build validation, signing, metadata, privacy URLs, screenshots, and TestFlight hardening.

## Critical Blockers

1. Native build is not locally verified on this machine.
   - Full Xcode is still required. Command Line Tools alone cannot run `xcodebuild` or `simctl`.

2. Signing and App Store Connect are not configured.
   - Set Apple Developer Team, confirm bundle id `com.juliosuas.rocio`, create the App Store Connect app record, and produce an archive.

3. Privacy materials are still missing.
   - App Privacy answers are drafted in `APP_STORE_PRIVACY_ANSWERS.md`.
   - Need live privacy policy URL and support URL before external TestFlight/App Store submission.

4. Plant identification remains assistive only.
   - Supabase URL/key are currently blank in `index.html`.
   - Plant.id secret must stay server-side.
   - Scanner UX must keep uncertainty visible.
   - Review notes must explain that identification is assistive, not guaranteed.

5. Reminder reliability needs device testing.
   - Native local notifications exist, but permission flow and scheduled delivery must be tested on a real simulator/device before TestFlight.

6. Persistence is still local-only.
   - The native app stores garden data in `UserDefaults` and now supports local export/delete. Cloud sync is out of scope for v1 unless product scope changes.

7. Assets need release audit.
   - Photo attributions exist, but each image must be license-safe for App Store distribution.
   - Need App Store icon and screenshots.

8. QA is still too narrow.
   - Existing classifier harness is good. iOS CI exists for build, but native tests and a real-device smoke pass are still required before submission.

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
- PWA users can export a local JSON copy and delete garden data plus scan history from the UI; native iOS must keep the same control.
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

## Current Smallest Shippable PR

Harden the native foundation for App Store review:

- Keep the SwiftUI app native, not WebView-based.
- Keep App Intents narrow: open garden, log watering, open scanner.
- Add local export/delete controls for user data.
- Prevent overdue watering reminders from scheduling in the past.
- Refresh garden state when App Intents modify persistence while the app is inactive.
- Update launch docs so every next agent starts from the current iOS reality.
