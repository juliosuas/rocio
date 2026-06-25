# Rocio GBRAIN

Last updated: 2026-06-25

This is the project brain for turning Rocio from a lovable MVP into an App Store-ready product. Treat it as the source of truth for product direction, technical tradeoffs, launch risk, and PR review standards.

## Product Thesis

Rocio is a Spanish-first flower-care companion for people who want a gentle, practical way to care for a small home garden. The App Store version should not be a thin web wrapper. It must earn its place on iPhone by doing native things well: reliable reminders, camera/photo capture with clear privacy, Shortcuts/Siri entry points, widgets later, offline-first care data, and a polished mobile experience.

## Current MVP Reality

- The current app is a single-file PWA in `index.html`.
- Data is stored locally through `localStorage` keys such as `rocio_garden` and `rocio_scan_history`.
- The catalog has 15 flowers with care data and local image assets.
- Plant identification has a local fallback classifier. Plant.id is architected through Supabase Edge Functions, but the public Supabase URL/key are disabled in `index.html` right now.
- Notifications are local/browser notifications and only work when browser conditions allow them. They are not reliable scheduled iOS reminders yet.
- There is no Xcode project, iOS bundle id, SwiftUI app, App Intents target, widget target, TestFlight setup, privacy policy, App Store metadata, or release CI.

## GStack For This Repo

`gstack` means the smallest launch stack that lets us ship repeatedly without losing discipline:

- GitHub repo as the operating system for source, PRs, issues, CI, and review history.
- Codex agents for implementation, App Store launch audits, and daily project follow-up.
- CodeRabbit for independent PR review when a real diff is available.
- Supabase Edge Functions only for server-side secrets and provider calls such as Plant.id.
- Apple-native surface for the store app: SwiftUI, App Intents, local notifications, and later widgets.
- Keep the MVP web app usable while migrating the highest-value flows into native code.

## GBrain Rules

- Be critical before being clever.
- No PR gets approved if it weakens privacy, stores secrets in the browser, breaks the local MVP, or makes the scanner sound more certain than it is.
- Prefer small PRs with one shippable outcome.
- Every launch PR must update this file or the launch plan when it changes scope, risk, or sequencing.
- Keep App Store work grounded in Apple's review reality: a plain WebView clone is high risk; native value must be visible.

## First Native App Intents Surface

Start narrow. Do not mirror every tab.

1. `OpenGardenIntent`
   - Opens Rocio directly to Mi Jardin.
   - Good for Siri, Shortcuts, and Spotlight.

2. `LogWateringIntent`
   - Lets the user mark a saved garden plant as watered without opening the app.
   - Requires a small `GardenPlantEntity` backed by native/local persistence.

3. `OpenScannerIntent`
   - Opens the native app to scanner/camera flow.
   - Must include clear camera privacy text and should not run identification silently.

Entity surface:

- `GardenPlantEntity`: id, display name, flower type, last watered date, watering interval, status.
- Optional later: `FlowerEntity` for catalog lookup and Spotlight results.

## App Store Non-Negotiables

- Add a privacy policy and support URL before TestFlight external review.
- Add camera usage text that explains photo analysis plainly.
- Add notification permission text that explains watering reminders.
- Keep Plant.id API keys only in server-side secrets.
- Provide a way to delete local garden and scan history.
- Do not claim medical, agricultural, or professional diagnosis accuracy.
- Audit all flower photo licenses and keep attribution in the release notes/admin docs.
- Add 1024px App Store icon, required iOS app icon sizes, screenshots, subtitle, keywords, and review notes.
- Build real native functionality before submitting. A WebView-only app is not enough.

## PR Approval Standard

A PR can be approved only when:

- The behavior is testable from the diff.
- App Store/privacy impact is explicitly considered.
- CI or an equivalent manual check is recorded.
- The change does not regress the PWA fallback.
- Any user-facing claim about identification confidence stays honest.

When in doubt, request changes instead of approving.