# Rocio Apple Developer Runbook

Date: 2026-07-04

## Goal

Move iOS build/test off the local Mac and into GitHub Actions, then use Apple Developer/App Store Connect for signing, TestFlight, and submission.

## What We Can Do Without Local Xcode

- Build/test in GitHub Actions on `macos-latest`.
- Validate the PWA demo and marketing pages locally.
- Prepare metadata, privacy answers, support URL, and review notes.
- Create an unsigned release archive artifact in GitHub Actions.

## What Still Requires Apple Account Work

- Pay Apple Developer Program.
- Create or confirm bundle id `com.juliosuas.rocio`.
- Create the App Store Connect app record.
- Configure signing certificates/profiles or App Store Connect API automation.
- Upload a signed archive to TestFlight.

## GitHub Actions Gates

Every PR touching `ios/**` runs:

```sh
xcodebuild -project ios/Rocio.xcodeproj -scheme Rocio -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project ios/Rocio.xcodeproj -scheme Rocio -configuration Debug -destination "platform=iOS Simulator,name=<available iPhone>" CODE_SIGNING_ALLOWED=NO test
```

Manual archive workflow:

- GitHub Actions > `iOS Archive` > Run workflow.
- Produces an unsigned `Rocio.xcarchive` artifact.
- This proves Release archive shape before signing/TestFlight automation is wired.

## Paid Launch Steps

1. Enroll/pay Apple Developer Program.
2. In Certificates, Identifiers & Profiles, create App ID:
   - Bundle ID: `com.juliosuas.rocio`
   - Capabilities: none beyond default for v1 unless Xcode later requires notifications entitlement.
3. In App Store Connect, create app:
   - Name: `Rocio`
   - Primary language: Spanish.
   - Bundle ID: `com.juliosuas.rocio`
   - SKU: `rocio-ios-v1`
4. Add privacy/support URLs:
   - Privacy: production URL for `privacy.html`
   - Support: production URL for `support.html`
5. Fill metadata from `APP_STORE_METADATA.md`.
6. Capture screenshots after CI build passes and local/native simulator access is available.
7. Upload first signed build to TestFlight.

## Signing Automation Later

Do not add signing secrets until the Apple Developer account is ready.

When ready, choose one path:

- Xcode Organizer upload from a local Mac with Xcode.
- GitHub Actions signing/upload with App Store Connect API key, certificate, and provisioning profile secrets.

The second path is more automatable but must be added only after secrets exist.
