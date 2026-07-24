# Rocio App Store Release Checklist

Date: 2026-07-24

## Current Build Strategy

Full Xcode 26.3 is selected locally. The current scanner-review worktree passes the unsigned Release simulator build and both the full unsigned CI-equivalent and locally signed XCTest suites 200/200 on iPhone 17 Pro with iOS 26.3.1. Exact-PR-head CI confirmation remains pending. GitHub Actions remains the shared gate for PR review, and local Xcode is available for smoke testing, screenshots, and Xcode Organizer upload.

The unsigned iOS archive workflow should also run on iOS PRs and pushes so archive regressions are caught before merge, while remaining manually runnable for release checks.

An iPhone 16e simulator smoke on 2026-07-20 verified Debug demo entry, catalog, seeded garden, bundled photos, and the local scanner disclosure. Real-device camera/photo, local and consented cloud analysis, review cancellation, a successful scan → review → Garden save, and notification permission/delivery testing are still required before external TestFlight or App Store submission.

A Personal Team Debug build for `com.juliosuas.rocio`, team `67QTYANL3F`, installed and launched successfully on the connected iPhone after the developer profile was trusted. Its provisioning profile expires on 2026-07-28. This confirms the earlier launch block was the iOS signing/trust boundary rather than a Supabase crash. The project-level `DEVELOPMENT_TEAM` remains blank, and paid membership is needed only for distribution/TestFlight signing.

The read-only diagnostic on 2026-07-21 confirmed the remote Supabase foundation and `identify-flower` v5, including fail-closed unauthenticated responses. This is dated evidence, not a perpetual guarantee: revalidate the remote state against the exact release commit. The three incremental migrations remain pending by design: `20260721000100_preserve_garden_deletions.sql`, `20260722000100_support_arbitrary_plants.sql`, and `20260723000100_idempotent_scan_requests.sql`; see `SUPABASE_DIAGNOSTIC_2026-07-21.md`.

The matching client now treats Auth and garden readiness separately: pre-migration `profiles.garden_epoch` failures keep the valid session and local garden available, queue edits without cloud writes, and retry through the same guarded preflight. Only causally authorized edits adopt a fetched epoch; ambiguous/inherited conflicts stay quarantined without blocking safe edits, validated queue provenance survives relaunch, post-reset edits adopt the returned epoch, and sign-out uses Supabase `scope=local` so one Mac/iPhone does not revoke the user's other devices.

## Tomorrow Publish Gate

Rocio can move to TestFlight tomorrow only if these are true:

- iOS GitHub Actions build passes.
- iOS GitHub Actions tests pass.
- Manual unsigned archive workflow succeeds.
- Paid Apple Developer Program membership and distribution team active. This is currently **not met**; only a free Personal Team is available.
- Bundle id `com.juliosuas.rocio` created or available for the distribution team; the local Personal Team Debug app already uses the correct identifier.
- Distribution `DEVELOPMENT_TEAM` set in the Rocio target; it is currently blank.
- The installed Personal Team Debug app launches after the developer profile is trusted, then camera/photo access, local and consented cloud analysis, review cancellation, a successful scan → review → Garden save, duplicate specimens, and notification permissions pass on the physical iPhone before external TestFlight.
- Signed archive upload succeeds.
- Privacy policy URL and support URL are live and entered in App Store Connect.
- App Privacy answers match `APP_STORE_PRIVACY_ANSWERS.md`.
- Supabase Auth allowlists exactly `com.juliosuas.rocio://auth/recovery` and uses the chosen stable HTTPS product URL instead of localhost as Site URL.
- Custom SMTP is configured for external users, and a real reset email opens Rocio, exchanges the PKCE code, changes the password, and permits a fresh sign-in.
- After backup and linked dry-run review, the deletion-preserving, arbitrary-plant, and idempotent-scan migrations are applied once in timestamp order, then the matching authenticated Edge Function/configuration is deployed and verified against the integrated release commit.
- Production anonymous key is injected through release configuration; Plant.id secret exists only in Supabase.
- Account creation, login, sync, analytics opt-out, photo consent, quota, scanner review, failed-save behavior, successful Garden routing, duplicate specimens, sign out, and in-app account deletion pass on a device.
- App Review demo account is active and included in Review Information.
- Final app icon and screenshots are ready.
- App Store Connect metadata draft is filled.

## CI Build Commands

```sh
xcodebuild -project ios/Rocio.xcodeproj -scheme Rocio -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project ios/Rocio.xcodeproj -scheme Rocio -configuration Debug -destination 'platform=iOS Simulator,name=<available iPhone>' CODE_SIGNING_ALLOWED=NO test
```

## Manual Local Commands If Xcode Is Installed

```sh
sudo xcodebuild -license accept
sudo xcodebuild -runFirstLaunch
xcodebuild -project ios/Rocio.xcodeproj -scheme Rocio -destination 'platform=iOS Simulator,name=iPhone 16' build
xcodebuild -project ios/Rocio.xcodeproj -scheme Rocio -destination 'platform=iOS Simulator,name=iPhone 16' test
```

## App Store Notes Draft

Rocio is a bilingual English/Spanish plant-care app that follows the user's iOS language. A required account provides garden sync, scan quota/history, and in-app account deletion. The app schedules optional local reminders and uses an authenticated Supabase Edge Function for experimental Plant.id plant identification after explicit consent for each transferred photo.

Camera and photo access are used only after a scanner action. For every photo, the user chooses on-device analysis or cloud transfer. Raw photos are not stored in Rocio's database. Identification falls back to a basic on-device visual match if cloud service is unavailable. A suggested result is reviewed before saving so the provider identity remains separate from the user's specimen nickname and optional watering preference. Notification permission is requested only after an explicit tap in Garden or Settings.

Detailed App Privacy answers are drafted in `APP_STORE_PRIVACY_ANSWERS.md` and must be rechecked before App Store Connect submission.

Production URLs:

- Privacy: `https://juliosuas.github.io/rocio/privacy.html`
- Support: `https://juliosuas.github.io/rocio/support.html`
