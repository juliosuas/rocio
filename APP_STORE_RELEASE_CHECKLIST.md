# Rocio App Store Release Checklist

Date: 2026-07-04

## Current Build Strategy

Local Xcode is still useful, but it is no longer the only gate. Because this machine has Command Line Tools active and no full Xcode selected, iOS build/test should be proven in GitHub Actions on `macos-latest`.

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
- Privacy policy URL and support URL are live.
- App Privacy answers match `APP_STORE_PRIVACY_ANSWERS.md`.
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

Rocio is a Spanish-first flower-care app. The app stores the user's garden locally on the device, schedules local watering reminders, and uses camera/photo input for an experimental on-device flower identification helper. No Plant.id or Supabase provider calls are enabled in the native app in this release.

Camera permission is used only when the user taps the scanner camera action. Photo library permission is used only when the user chooses a photo for local analysis. Notification permission is requested only from Settings when the user enables watering reminders.

Detailed App Privacy answers are drafted in `APP_STORE_PRIVACY_ANSWERS.md` and must be rechecked before App Store Connect submission.
