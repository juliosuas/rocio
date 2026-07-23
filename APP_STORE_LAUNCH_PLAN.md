# Rocio App Store Launch Plan

Date: 2026-07-23

This plan starts from the current `juliosuas/rocio` product: a bilingual native SwiftUI app supported by a PWA demo and public marketing site.

## Brutally Honest Status

Rocio has a native SwiftUI iOS feature candidate with EN/ES localization, authenticated Supabase accounts, account-scoped garden sync with versioned local recovery, local notifications, App Intents, an honest hybrid scanner, manual and Plant.id arbitrary-plant identity, privacy controls, CI, locally verified unsigned Debug and Release simulator builds, 170 passing integrated simulator tests, and an isolated Debug-only local demo. A Personal Team Debug build for `com.juliosuas.rocio` also installed and launched successfully on the connected iPhone after the development profile was trusted. The current client, three incremental migrations, and matching Edge Function are locally verified but not yet landed and deployed. The remaining release path is reviewing and merging the stacked PRs, applying the three migrations in order after backup and dry-run review, deploying the matching Edge code, configuring and smoke-testing password recovery, completing authenticated two-session and real-device permission smoke, paid distribution signing, final screenshots, TestFlight, and App Store Connect.

## Critical Blockers

1. Real-device permission smoke is not locally verified on this machine.
   - Full Xcode 26.3 is selected; unsigned Debug and Release builds passed locally, and 170/170 iPhone 17 simulator tests passed on 2026-07-23 with iOS 26.3.1. Re-run these gates from the exact release commit.
   - An iPhone 16e simulator smoke verified Debug demo entry, catalog, seeded garden, bundled photos, and local scanner disclosure on 2026-07-20.
   - Camera capture, photo picker, notification permission, and notification delivery still require real-device testing before TestFlight or external review.

2. Development signing works locally; distribution signing and App Store Connect are not configured.
   - A Personal Team Debug build for bundle id `com.juliosuas.rocio` and team `67QTYANL3F` installed and launched successfully after the developer profile was trusted in Settings. Its provisioning profile expires on 2026-07-28.
   - The project-level `DEVELOPMENT_TEAM` remains blank. Paid Apple Developer Program membership, a distribution team, the App Store Connect app record, and a signed distribution archive are required only when TestFlight is the immediate next step.

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

5. Reminder reliability needs physical-device testing.
   - Native local notifications exist, but permission flow and scheduled delivery must be tested on a physical iPhone before TestFlight.

6. Cloud deployment is partially complete.
   - The read-only production diagnostic on 2026-07-21 confirmed only the foundation migration, six RLS-protected tables, public client configuration, and `identify-flower` v5. Treat that as dated evidence and revalidate the exact remote state before deployment.
   - After the matching client stack lands and a database backup plus dry run are reviewed, apply `20260721000100_preserve_garden_deletions.sql`, `20260722000100_support_arbitrary_plants.sql`, and `20260723000100_idempotent_scan_requests.sql` in that order, then deploy the matching Edge Function and verify account isolation, delete-wins/reset convergence, quota/replay, analytics opt-out, and account deletion.

7. Assets need final visual release review.
   - Photo attributions and automated asset checks pass.
   - The opaque production icon is generated and the App Store marketing icon is exact 1024x1024; screenshots and a native simulator video remain.

8. QA must finish on hardware and production cloud state.
   - Classifier, release, App Store, security, unsigned Release build, and 170/170 simulator tests pass locally on the feature candidate as of 2026-07-23. A verified simulator smoke covers core Debug screens and the Personal Team app launches on the physical iPhone; re-run all gates from the exact release commit, then complete real-device permissions and authenticated two-session production sync before submission.

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

## Current Feature Candidate

Ship `Rocio 1.0 — arbitrary plants end to end` on top of the beta first-care foundation. All three incremental migrations and the matching Edge update remain unapplied in production:

- Upload a first plant created during the authenticated epoch handshake without requiring a second edit.
- Move directly to My Garden after adding a plant and show cloud sync state beside the action that created it.
- Offer watering reminders in context, while requesting iOS permission only after an explicit tap.
- Confirm the first watering immediately in the garden UI.
- Ask for cloud-photo consent for every scan, preserve an on-device-only choice, and downsample large photos before retaining or analyzing them.
- Require confirmation before the irreversible removal of one plant.
- Report garden deletion as cloud-confirmed only after the reset RPC and authoritative reconciliation succeed; otherwise keep a visible pending state.
- Include the locally integrated PKCE password-recovery client, while keeping it externally blocked until the callback allowlist, stable HTTPS Site URL, custom SMTP, and a real email-to-app password-change smoke test are complete.
- Preserve arbitrary Plant.id and manual identity without inventing exact care, and keep those plants usable across Garden, Calendar, notifications, App Intents, export, sync, deletion, and recovery.
- Make paid scans idempotent with one quota claim, bounded replay, provider recovery by `custom_id`, and best-effort provider cleanup.
- Fail closed on future local or cloud schemas so an older build cannot overwrite fields it does not understand.

Landing order is fixed: merge the beta-first-care base PR, then merge the stacked arbitrary-plant PR. After a production backup, linked dry run, and review, apply `20260721000100` → `20260722000100` → `20260723000100`, deploy the matching Edge Function, and run authenticated canaries plus the two-session smoke. Do not deploy backend changes from an unreviewed feature branch.
