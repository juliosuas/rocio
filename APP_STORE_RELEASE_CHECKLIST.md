# Rocio App Store Release Checklist

Date: 2026-07-05

## Current Build Strategy

Local Xcode is still useful, but it is no longer the only gate. Because this machine has Command Line Tools active and no full Xcode selected, iOS build/test should be proven in GitHub Actions on `macos-latest`.

The unsigned iOS archive workflow should also run on iOS PRs and pushes so archive regressions are caught before merge, while remaining manually runnable for release checks.

Local Xcode remains optional until screenshots, simulator smoke testing, or Xcode Organizer upload are needed.

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
- Supabase migration and authenticated Edge Function are deployed.
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
