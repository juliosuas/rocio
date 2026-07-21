# Rocio iOS

This is the native iOS track for Rocio. It is a SwiftUI app, not a thin WebView wrapper.

## What Is In This Cut

- Native SwiftUI shell with Catalog, Garden, Calendar, Scanner, and Settings tabs.
- Local flower catalog copied from the MVP.
- Local garden persistence with `UserDefaults`.
- Native local notification scheduling for watering reminders.
- Native camera/photo scanner flow with an honest local color-based identifier.
- App Intents for opening the garden, opening the scanner, and logging watering for saved plants.
- Privacy manifest and camera/photo usage descriptions.
- Shared Xcode scheme and GitHub Actions iOS build workflow.

## Local Build

Requires full Xcode, not only Command Line Tools.

```sh
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
xcodebuild -project ios/Rocio.xcodeproj -scheme Rocio -destination 'platform=iOS Simulator,name=iPhone 16' build
```

Run tests:

```sh
xcodebuild -project ios/Rocio.xcodeproj -scheme Rocio -destination 'platform=iOS Simulator,name=iPhone 16' test
```

## Supabase Public Configuration Per Mac

The project URL is committed because it is public. The Supabase publishable key is not committed and clean checkouts intentionally build with cloud features unconfigured.

To enable Rocio Cloud on one Mac:

```sh
cp ios/Config/Local.xcconfig.example ios/Config/Local.xcconfig
```

Open `ios/Config/Local.xcconfig` and replace the placeholder with the project's `sb_publishable_...` key from Supabase API settings. `Local.xcconfig` is ignored by Git and is consumed by both Debug and Release. Never place `sb_secret_...`, a legacy `service_role` JWT, or `PLANT_ID_API_KEY` in any iOS configuration.

## Debug Demo Without Supabase

When a Debug build has no Supabase public configuration, launch the app and tap **Explore local demo**. The demo:

- seeds three in-memory plants so Garden and Calendar are immediately testable;
- keeps garden edits out of persistent account data;
- uses only the on-device scanner and never uploads a photo;
- skips cloud analytics and synchronization;
- restores the garden that existed before the demo when you exit from Settings.

The demo entry point and session state are wrapped in `#if DEBUG` and are absent from Release builds.

## Before TestFlight

- Set `DEVELOPMENT_TEAM` in the Rocio target.
- Confirm bundle id `com.juliosuas.rocio` in Apple Developer/App Store Connect.
- Replace the provisional icon with final App Store artwork.
- Capture iPhone screenshots from a real simulator/device.
- Publish privacy policy and support URL.
- Archive from Xcode Organizer and upload to App Store Connect.
