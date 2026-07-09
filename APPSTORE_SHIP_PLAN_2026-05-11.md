# Superseded App Store Plan (2026-05-11)

This historical Capacitor-wrapper plan is superseded by `APP_STORE_LAUNCH_PLAN.md` and must not be used for implementation or release decisions.

Rocio now has a native SwiftUI target under `ios/` with local garden persistence, local notifications, App Intents, camera/photo handling, EN/ES localization, privacy controls, and native tests. The PWA remains a demo/fallback and is not the App Store binary.

Current release gates:

1. Run `node qa/release-gate.mjs`.
2. Pass local `xcodebuild build`, `test`, and unsigned `archive` with full Xcode.
3. Record the real native app in Simulator and publish the verified demo video.
4. Configure Apple Developer Team and App Store Connect.
5. Upload to TestFlight, run the release smoke checklist, then submit.

Canonical privacy and support URLs:

- `https://juliosuas.github.io/rocio/privacy.html`
- `https://juliosuas.github.io/rocio/support.html`
