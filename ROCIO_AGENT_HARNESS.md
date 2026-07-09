# Rocio Launch Agent Harness

Rocio uses the official `garrytan/gstack` Codex host plus repository-specific release gates. GBrain is intentionally out of the v1 release path; `ROCIO_BRAIN.md` remains the launch memory.

## Required Review Roles

1. Product: keep v1 narrow, useful, free, and honest.
2. iOS Engineering: protect native behavior, local persistence, App Intents, and notification correctness.
3. Design: verify iPhone layouts, localization, icon, screenshots, and product video.
4. QA: run `node qa/release-gate.mjs`, iOS build/test/archive, and browser smoke tests.
5. Privacy: block secrets, undisclosed collection, misleading scanner claims, and internal copy on public pages.
6. Release: require green CI, resolved review findings, public endpoint checks, and an explicit signing state.

P0 and P1 findings block merge and publication. P2 findings must be documented with an owner and follow-up date.

## Gstack Flow

- Plan: `gstack-autoplan`
- Code review: `gstack-review`
- Security/privacy: `gstack-cso`
- Product QA: `gstack-qa`
- iOS visual QA: `gstack-ios-design-review`
- Ship: `gstack-ship`

## Release Contract

- Native app: `ios/Rocio.xcodeproj`, bundle id `com.juliosuas.rocio`.
- Web fallback/demo: GitHub Pages.
- Marketing: canonical Lovable project only.
- Scanner: local and experimental in v1.
- App data: local, exportable, deletable, no tracking.
- Marketing waitlist: email collection only after explicit consent and privacy disclosure.
