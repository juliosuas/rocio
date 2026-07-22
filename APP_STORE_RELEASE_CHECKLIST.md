# Rocio App Store Release Checklist

Date: 2026-07-20

## Current Build Strategy

Full Xcode 26.3 is selected locally. The unsigned simulator build passed on 2026-07-20 with the generic iOS Simulator destination, and the iPhone 17 simulator test run passed the native unit suite. GitHub Actions remains the shared gate for PR review, and local Xcode is now available for smoke testing, screenshots, and Xcode Organizer upload.

The unsigned iOS archive workflow should also run on iOS PRs and pushes so archive regressions are caught before merge, while remaining manually runnable for release checks.

An iPhone 16e simulator smoke on 2026-07-20 verified Debug demo entry, catalog, seeded garden, bundled photos, and the local scanner disclosure. Real-device camera/photo and notification permission/delivery testing is still required before external TestFlight or App Store submission.

The remote Supabase foundation and `identify-flower` v5 are active and fail closed for unauthenticated callers. Migration `20260721000100_preserve_garden_deletions` remains pending by design until the matching iOS tombstone/epoch clients are integrated; see `SUPABASE_DIAGNOSTIC_2026-07-21.md`.

The matching client now treats Auth and garden readiness separately: pre-migration `profiles.garden_epoch` failures keep the valid session and local garden available, queue edits without cloud writes, and retry through the same guarded preflight. Only causally authorized edits adopt a fetched epoch; ambiguous/inherited conflicts stay quarantined without blocking safe edits, validated queue provenance survives relaunch, post-reset edits adopt the returned epoch, and sign-out uses Supabase `scope=local` so one Mac/iPhone does not revoke the user's other devices.

## Tomorrow Publish Gate

Rocio can move to TestFlight tomorrow only if these are true:

- iOS GitHub Actions build passes.
- iOS GitHub Actions tests pass.
- Manual unsigned archive workflow succeeds.
- Apple Developer account/team available.
- Bundle id `com.juliosuas.rocio` created or available.
- `DEVELOPMENT_TEAM` set in the Rocio target.
- App runs on an iPhone simulator or device before external TestFlight.
- Signed archive upload succeeds.
- Privacy policy URL and support URL are live and entered in App Store Connect.
- App Privacy answers match `APP_STORE_PRIVACY_ANSWERS.md`.
- The deletion-preserving Supabase migration and authenticated Edge Function are deployed from the integrated release commit.
- Production anonymous key is injected through release configuration; Plant.id secret exists only in Supabase.
- Account creation, login, sync, analytics opt-out, photo consent, quota, sign out, and in-app account deletion pass on a device.
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

Rocio is a bilingual English/Spanish flower-care app that follows the user's iOS language. A required account provides garden sync, scan quota/history, and in-app account deletion. The app schedules local reminders and uses an authenticated Supabase Edge Function for experimental Plant.id flower identification after explicit photo-transfer consent.

Camera and photo access are used only after a scanner action. Raw photos are not stored in Rocio's database. Identification falls back to a basic on-device visual match if cloud service is unavailable. Notification permission is requested only from Settings.

Detailed App Privacy answers are drafted in `APP_STORE_PRIVACY_ANSWERS.md` and must be rechecked before App Store Connect submission.

Production URLs:

- Privacy: `https://juliosuas.github.io/rocio/privacy.html`
- Support: `https://juliosuas.github.io/rocio/support.html`
