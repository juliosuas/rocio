# Rocio App Store Launch Plan

Date: 2026-07-20

This plan starts from the current `juliosuas/rocio` product: a bilingual native SwiftUI app supported by a PWA demo and public marketing site.

## Brutally Honest Status

Rocio has a native SwiftUI iOS product with EN/ES localization, authenticated Supabase accounts, account-scoped garden sync with a local cache, local notifications, App Intents, an honest hybrid scanner, privacy controls, CI, a locally verified unsigned simulator build, passing local simulator unit tests, and an isolated Debug-only local demo. The remaining release path is backend deployment, production credentials, real-device permission smoke, signing, screenshots, TestFlight, and App Store Connect.

## Critical Blockers

1. Real-device permission smoke is not locally verified on this machine.
   - Full Xcode 26.3 is selected; the unsigned simulator build and iPhone 17 simulator tests passed locally on 2026-07-20.
   - An iPhone 16e simulator smoke verified Debug demo entry, catalog, seeded garden, bundled photos, and local scanner disclosure on 2026-07-20.
   - Camera capture, photo picker, notification permission, and notification delivery still require real-device testing before TestFlight or external review.

2. Signing and App Store Connect are not configured.
   - Set Apple Developer Team, confirm bundle id `com.juliosuas.rocio`, create the App Store Connect app record, and produce an archive.

3. Privacy materials need final App Store Connect entry, not first publication.
   - App Privacy answers are drafted in `APP_STORE_PRIVACY_ANSWERS.md`.
   - Live privacy policy URL: `https://juliosuas.github.io/rocio/privacy.html`.
   - Live support URL: `https://juliosuas.github.io/rocio/support.html`.
   - Recheck answers immediately before upload if analytics, crash reporting, sync, Supabase, Plant.id, or image upload behavior changes.

4. Plant identification remains assistive only.
   - Supabase URL/key are currently blank in `index.html`.
   - Plant.id secret must stay server-side.
   - Scanner UX must keep uncertainty visible.
   - Review notes must explain that identification is assistive, not guaranteed.

5. Reminder reliability needs device testing.
   - Native local notifications exist, but permission flow and scheduled delivery must be tested on a real simulator/device before TestFlight.

6. Cloud deployment is partially complete.
   - The foundation migration, six RLS-protected tables, production public client configuration, and `identify-flower` v5 are active remotely.
   - Deploy `20260721000100_preserve_garden_deletions` only after its client PRs are integrated, then verify two-account delete-wins/reset convergence, quota, analytics opt-out, and account deletion against production.

7. Assets need final visual release review.
   - Photo attributions and automated asset checks pass.
   - The opaque production icon is generated and the App Store marketing icon is exact 1024x1024; screenshots and a native simulator video remain.

8. QA is still too narrow.
   - Existing classifier harness is good. iOS CI exists for build, local simulator unit tests pass, and a trusted simulator smoke covers core Debug demo screens; real-device permission smoke is still required before submission.

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
- Use local caching plus account-scoped Supabase synchronization for saved garden plants.
- Reuse the flower catalog data by extracting it from `index.html` into a structured data file in a later PR.
- Use an authenticated Supabase Edge Function for consented Plant.id scans, with monthly quotas and an on-device fallback.
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
- `AppShortcutsProvider` exposes localized English and Spanish phrases.
- App handles intent handoff through one central route.

## Milestone 4: TestFlight Readiness

Goal: make the app reviewable by a small external group.

Acceptance criteria:

- Archive build succeeds.
- TestFlight internal build uploaded.
- Privacy policy and support URL are live and entered in App Store Connect.
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

Finish active garden convergence:

- Run the complete flush/readback/reconciliation path after every queued mutation.
- Pull the authoritative garden when the app returns to the foreground.
- Prevent cancelled or cross-account work from applying a stale snapshot.
- Keep valid authentication usable when garden REST is offline or awaiting migration, while requiring a causally observed current-session epoch before any garden write.
- Revoke only the current device on sign-out and publish the local signed-out state without waiting for the remote request.
- Preserve the conflict timestamp of watering logged through Siri/App Intents.
- Cover server no-op/tombstone readback, foreground deletion, handshake recovery, preflight/reset races, inherited/current mixed queues, relaunch-safe epoch provenance, and sign-out cancellation with deterministic tests.
