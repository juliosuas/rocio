# Rocio Demo Runbook

Date: 2026-07-04

## Web Demo Now

Run:

```sh
cd /Users/ghostcat/Documents/rocio/app
python3 -m http.server 3002
```

Open:

- Landing: `http://localhost:3002/launch.html`
- App demo: `http://localhost:3002/index.html`
- Privacy: `http://localhost:3002/privacy.html`
- Support: `http://localhost:3002/support.html`

## Demo Script

1. Open `launch.html`.
2. Explain the positioning: gentle flower care in English and Spanish, account-synced, and honest about experimental matching. State that consented scans are authenticated through Rocio Cloud and forwarded to Plant.id, with a local fallback.
3. Open the app demo.
4. Show catalog flower cards and care information.
5. Add a flower to Mi Jardin.
6. Show watering/calendar flow.
7. Open scanner and explain uncertainty.
8. Open privacy/support pages.
9. Close with App Store path: Xcode build, TestFlight, free v1, monetization later.

## Native iOS Gate

Local native execution is blocked until full Xcode is installed and selected. CI native build/test is not blocked: use GitHub Actions `iOS`.

CI gates:

- Pull request or push touching `ios/**` runs iOS build/test.
- Manual `iOS Archive` workflow creates an unsigned Release archive artifact.

Expected local commands after Xcode 16.4 install:

```sh
sudo xcodebuild -license accept
sudo xcodebuild -runFirstLaunch
cd /Users/ghostcat/Documents/rocio/app
xcodebuild -project ios/Rocio.xcodeproj -scheme Rocio -destination 'platform=iOS Simulator,name=iPhone 16' build
xcodebuild -project ios/Rocio.xcodeproj -scheme Rocio -destination 'platform=iOS Simulator,name=iPhone 16' test
```

## Acceptance Criteria For A Real Demo

- Landing page loads on mobile and desktop.
- App demo opens without console-blocking errors.
- Scanner copy keeps uncertainty visible.
- Privacy/support URLs are present.
- App Store metadata draft exists.
- GitHub Actions iOS build/test is green, or local Xcode blocker is documented if native demo cannot run.
