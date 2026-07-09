# Rocio GStack App Store Daily Plan

Date: 2026-06-28
Source methodology: https://github.com/garrytan/gstack
Project source of truth: https://github.com/juliosuas/rocio

## Mission

Ship Rocio, the bilingual English/Spanish flower-care app, to the App Store through daily small PRs. Every session must lower one concrete launch risk: build, signing, privacy, review compliance, native value, QA, TestFlight, or metadata.

## Roles

### CEO/Product Agent

Chooses the one App Store risk worth reducing today. Rejects scope creep. Keeps v1 narrow: local garden, catalog, local reminders, scanner with honest uncertainty, App Intents, privacy controls.

### Engineering Agent

Turns the chosen risk into the smallest native implementation. Prefers SwiftUI, local persistence, App Intents, local notifications, and focused tests. Avoids backend/provider work unless the task explicitly requires it.

### Design Agent

Reviews English and Spanish copy, empty states, permission flow, screenshots, Settings, scanner confidence language, and whether the app feels native.

### QA Agent

Runs the relevant checks and records evidence:

- `node qa/readonly-flower-classifier-harness.mjs --strict`
- `xcodebuild -project ios/Rocio.xcodeproj -scheme Rocio -destination 'platform=iOS Simulator,name=iPhone 16' build`
- `xcodebuild -project ios/Rocio.xcodeproj -scheme Rocio -destination 'platform=iOS Simulator,name=iPhone 16' test`
- simulator/device smoke test when Xcode is available

### Security/Privacy Agent

Blocks secrets in client code, unclear camera/photo usage, notification permission misuse, missing privacy policy/support URL, missing data deletion/export, and any scanner claim that sounds guaranteed.

### Release Agent

Keeps PRs small, writes PR notes, watches CI, updates launch docs, and prepares TestFlight/App Store checklist items.

## Daily Session Order

1. Read `ROCIO_BRAIN.md`, `APP_STORE_LAUNCH_PLAN.md`, `APP_STORE_RELEASE_CHECKLIST.md`, and this file.
2. Check local status and remote PR/CI status.
3. Pick one task from the priority ladder.
4. Implement only that task.
5. Run the tightest relevant verification.
6. Update docs if launch state changed.
7. Leave a next-session checklist.

## Priority Ladder

1. Build gate: install/select full Xcode, make iOS build and tests pass.
2. Source of truth: keep `/Users/ghostcat/Documents/rocio/app` aligned with `juliosuas/rocio`.
3. Signing gate: Apple Developer Team, bundle id, archive settings.
4. Privacy gate: privacy policy URL, support URL, App Privacy answers, PrivacyInfo review.
5. Native value gate: local reminders, App Intents, scanner, local export/delete, offline catalog.
6. QA gate: iOS unit tests, simulator smoke, PWA classifier regression, CI green.
7. Asset gate: icon audit, screenshots, photo license audit.
8. TestFlight gate: internal build upload, device smoke, crash/permission pass.
9. Submission gate: metadata, keywords, review notes, final checklist.

## Definition Of App Store Ready

- Release archive succeeds.
- Tests and CI pass.
- App runs on simulator and at least one real device or trusted simulator smoke.
- App Store Connect record exists for `com.juliosuas.rocio`.
- Privacy policy and support URL are live.
- App Privacy answers match actual data behavior.
- Camera/photo/notification prompts are user-initiated and clear.
- No Plant.id or Supabase secrets are in client code.
- Scanner copy states uncertainty and avoids professional diagnosis claims.
- Local data export/delete works.
- Required screenshots, app icon, subtitle, keywords, and review notes are ready.

## Current Next Actions

1. Install/select full Xcode and run native build/test.
2. If build fails, fix compiler/project issues before adding features.
3. Set Apple Developer Team and confirm bundle id.
4. Draft privacy policy/support page and App Review notes.
5. Capture simulator screenshots after the UI passes smoke testing.
