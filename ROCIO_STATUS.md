# Rocío - Status Report

## What Works (Real, Functional)

This section describes the single-file PWA demo unless a bullet explicitly says native iOS.

- **Flower Catalog** — 15 flowers with botanical care data and local app-owned image assets (Rosa, Tulipán, Orquídea, Girasol, Lavanda, Gardenia, Jazmín, Hortensia, Lirio, Margarita, Clavel, Violeta, Geranio, Petunia, Cempasúchil).
- **Mi Jardín** — Add/remove plants, track watering, set status, write notes. Persisted in localStorage and sorted by urgency.
- **Watering Tracker** — Tap to water with animation, last-watered tracking, urgency dots, streak, and stats dashboard.
- **Weekly Calendar** — Shows which plants need water by day; tasks have water buttons directly inside the calendar.
- **Moon Phase Calendar** — Real Conway-style moon phase algorithm with gardening recommendations.
- **Seasonal Tips** — 36 tips across all 12 months, culturally relevant for Mexico.
- **Plant Doctor** — Symptom categories, pest profiles, home remedies, and treatments, now labeled as PENDING botanical verification before App Store/commercial claims.
- **Composting Guide** — Green/brown guide, DIY fertilizers, vermicomposting.
- **Watering Calculator** — Adjusts water amount by pot size, location, climate, and season.
- **Dark Mode** — Full dark theme with persisted preference.
- **Web-demo Local Plant Identifier** — The PWA camera/file-upload flow uses the local flower matcher by default. Rocío resizes/compresses the flower image, compares it against the local flower catalog, and shows uncertainty/top candidates without requiring cloud configuration.
- **Scan History** — Saves recent scans locally.
- **Web-demo Notifications** — The PWA requests notification permission when the first plant is added and can notify due/overdue watering reminders while browser conditions allow it.
- **Share** — Native share API or clipboard fallback for plant info cards.
- **Onboarding** — 3-step welcome flow for first-time visitors.
- **Splash Screen** — Animated launch screen once per session.

## What Is Still Limited

- **Plant.id cloud path was verified for native iOS on 2026-07-21** — The dated read-only diagnostic found a healthy Rocio Supabase project exposing `identify-flower` v5, validating bearer sessions manually, and rejecting unauthenticated requests with 401. Revalidate that remote state from the exact release commit. An authenticated real-device scan still needs release smoke testing; the web demo intentionally keeps its cloud configuration blank.
- **Native local matcher is user-selectable and a fallback** — Native iOS offers an explicit on-device-only choice for each photo and also falls back locally when the cloud path is unavailable. The PWA uses the local matcher by default. Both surfaces label the result as uncertain rather than market-grade recognition.
- **Only 15 catalog flowers are supported locally** — Unknown Plant.id species can be detected by the API but may not map to a local care card yet.
- **Native cloud hardening is pending one ordered migration** — The foundation schema and Edge Function are deployed. The SwiftUI app implements required accounts, Keychain sessions, account-scoped garden sync, analytics opt-out, quotas, and account deletion. A missing/slow epoch endpoint no longer rejects a valid login: changes remain local and no garden write is sent until the current session obtains a causally valid epoch. Ambiguous/inherited conflicts are quarantined without blocking safe edits, validated queue provenance survives relaunch, and post-reset edits adopt the returned epoch. Deploy the deletion-preserving tombstone/epoch migration only after this matching client code is integrated; the web demo remains localStorage-only.
- **No Web Push Server for the PWA** — Browser reminders remain limited by browser execution. Native iOS watering reminders are scheduled locally and do not require a Web Push server; their remaining gap is physical-device permission and delivery validation.
- **No Weather Integration** — Watering calculator still uses manual climate input.
- **Disease/treatment evidence is not source-audited yet** — Existing symptom and treatment guidance is visible only as PENDING verification and must be checked against reliable horticultural sources before being sold as diagnosis or treatment advice.
- **Photo assets pass the local App Store photo gate** — 15/15 catalog JPGs exist, all have attribution rows, none have pending license/source audit markers, all meet the local 800px minimum-dimension threshold, and every JPG is under the 1 MB payload cap. Keep attribution visible and re-run `node qa/photo-asset-audit.mjs --app-store-ready` before using screenshots or metadata.
- **Commercial/App Store claims are guarded but not verified** — `qa/commercial-claim-audit.mjs` checks that disease/treatment content stays labeled as PENDING botanical verification, scanner and README copy stay honest about local matching, and no Plant.id secret is present in the browser build.
- **Botanical content coverage is guarded, not medically verified** — `qa/botanical-content-audit.mjs` verifies that every catalog flower has complete disease rows and every Plant Doctor symptom cause has complete guidance while still rendering treatment text behind PENDING verification and caveats.
- **App Store/Lovable static readiness is guarded locally** — `qa/appstore-static-readiness-audit.mjs` verifies local privacy/support drafts, iOS/PWA metadata, manifest identity, App Store owner-action blocks, and Lovable no-publish/no-secret constraints while still reporting `appStoreSubmissionReady: false`.

## Longer-Term Commercial Opportunities

These are post-beta opportunities, not blockers for the native Beta 0.1 sequence in `APP_STORE_LAUNCH_PLAN.md`.

### 1. Web Push for the PWA

Add Web Push subscriptions plus a daily job that sends watering reminders even when Rocío has not opened the app.

### 2. Expand Plant.id Result Coverage

The Supabase proxy is now the intended architecture. Next: add generic care guidance for Plant.id species that are outside the 15-flower local catalog.

### 3. Family Sharing

Extend the implemented account sync with explicit shared-garden invitations and roles.

---

*Built with love for Rocío Calderón. The web demo remains a zero-dependency single `index.html`; the native SwiftUI app is the App Store product.*
