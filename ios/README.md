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

## Before TestFlight

- Set `DEVELOPMENT_TEAM` in the Rocio target.
- Confirm bundle id `com.juliosuas.rocio` in Apple Developer/App Store Connect.
- Replace the provisional icon with final App Store artwork.
- Capture iPhone screenshots from a real simulator/device.
- Publish privacy policy and support URL.
- Archive from Xcode Organizer and upload to App Store Connect.

