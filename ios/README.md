# Rocío iOS 1.0

Rocío's native SwiftUI client. It is not a WebView or a wrapper around the web demo.

## Release status

- `MARKETING_VERSION = 1.0`
- `CURRENT_PROJECT_VERSION = 1`
- Deployment target: iOS 17.0 with Swift 5.
- 194/194 tests pass under both unsigned-CI and locally signed simulator contracts on iOS 26.3.1.
- Debug and unsigned Release compile with Xcode 26.3.
- A Personal Team development build launches on a physical iPhone.
- TestFlight remains blocked by paid membership, `DEVELOPMENT_TEAM`, distribution signing, and outstanding external smoke tests.

## Native surface

- Catalog, Garden, Calendar, Scanner, and Settings in SwiftUI.
- Bilingual catalog of exactly 15 editorial flower guides with attributed local photography, plus arbitrary Plant.id results and manual plants that retain their own identity.
- Supabase account, Keychain session, and per-user garden sync with owner-bound, versioned primary/backup snapshots, fail-closed owner checks, repair from a valid redundant copy, quarantine for unsafe replacements, and a durable mutation outbox.
- Complete first-care flow: add a plant, return to the garden, enable a reminder, and confirm watering.
- Local-notification permission requested only after an explicit tap.
- Experimental scanner with off-main-thread image reduction, consent for every photo, an on-device option, and an honest fallback.
- PKCE password recovery with the verifier in Keychain, bearer-free URLs, and cross-scene race handling.
- App Intents to open the garden, open the scanner, and record watering.
- Export, local reset, cloud deletion, analytics opt-out, sign-out, and permanent account deletion.
- Demo mode isolated under `#if DEBUG`; it does not exist in Release.

## Requirements

- Full Xcode 26.3 installation.
- A compatible iOS Simulator runtime.
- A macOS version supported by Xcode 26.3.
- For cloud behavior: the project's public Supabase URL and publishable key.

Select Xcode:

```sh
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
xcodebuild -version
```

## Public Supabase configuration on each Mac

```sh
cp ios/Config/Local.xcconfig.example ios/Config/Local.xcconfig
```

Add only the Supabase `sb_publishable_...` key to `Local.xcconfig`. The file is ignored by Git and supplies both Debug and Release.

Never add these values to the client:

- `sb_secret_...`
- A JWT with the `service_role` role
- `SUPABASE_SERVICE_ROLE_KEY`
- `PLANT_ID_API_KEY`

A Debug build without the key shows **Explore local demo**. A signed Release build fails early when public configuration is missing, preventing an incomplete cloud build from being uploaded.

## Build

From the repository root:

```sh
xcodebuild \
  -project ios/Rocio.xcodeproj \
  -scheme Rocio \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  build
```

Unsigned Release:

```sh
xcodebuild \
  -project ios/Rocio.xcodeproj \
  -scheme Rocio \
  -configuration Release \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## Tests

```sh
xcodebuild \
  -project ios/Rocio.xcodeproj \
  -scheme Rocio \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  test
```

The suite covers authentication, PKCE, refresh-token rotation, account isolation, arbitrary Plant.id and manual plants, exact catalog-care matches, versioned snapshot recovery, durable outbox acceptance, idempotent scan retries, sync/epoch/tombstones, first care, notifications, scanner behavior, image reduction, routing, and persistence.

Run the additional gates from the repository root:

```sh
node qa/release-gate.mjs
node qa/cloud-ai-security-audit.mjs
node qa/ios-app-store-readiness-audit.mjs
```

## Offline and failure behavior

- A valid session and the local garden appear without waiting for the cloud handshake.
- Pending changes are retained and retried; the UI does not claim successful sync before remote confirmation.
- Sign-out, account changes, and recovery invalidate earlier tasks before they can publish stale state.
- Deleted plants use tombstones so they do not reappear from another device.
- If Plant.id or Supabase fails, the scanner returns to the local matcher and keeps uncertainty visible.

## Debug demo without Supabase

Tap **Explore local demo**. Demo mode:

- creates three temporary plants;
- lets you explore Garden, Calendar, and Scanner;
- never uploads photos or runs cloud analytics;
- never writes over an account's garden; and
- restores the previous data when you exit through Settings.

## Before TestFlight

1. Activate the Apple Developer Program and configure `DEVELOPMENT_TEAM`.
2. Confirm bundle ID `com.juliosuas.rocio` in Apple Developer and App Store Connect.
3. Verify that the signed Release build contains the correct publishable key.
4. Run `supabase db push --linked --dry-run` and review the expected pending migrations.
5. Apply `20260721000100_preserve_garden_deletions.sql`, then `20260722000100_support_arbitrary_plants.sql`, then `20260723000100_idempotent_scan_requests.sql`, and only then deploy the matching `identify-flower` Edge Function. All three incremental migrations and the Edge update remain undeployed.
6. Allowlist `com.juliosuas.rocio://auth/recovery`, then configure the HTTPS Site URL and SMTP.
7. Test real email recovery and synchronization with two sessions.
8. Test camera, photo picker, and notification delivery on a physical iPhone.
9. Archive through Xcode Organizer, upload to TestFlight, and capture final screenshots.

See [`../APP_STORE_RELEASE_CHECKLIST.md`](../APP_STORE_RELEASE_CHECKLIST.md) for the complete gate and [`../DESIGN.md`](../DESIGN.md) for visual rules.
