# Rocío - Status Report

## What Works (Real, Functional)

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
- **Local Plant Identifier** — Camera/file-upload flow now uses the local flower matcher by default. Rocío resizes/compresses the flower image, compares it against the local flower catalog, shows uncertainty/top candidates, and avoids depending on the old Supabase project while it is unavailable.
- **Scan History** — Saves recent scans locally.
- **Local Notifications** — Requests notification permission when the first plant is added and can notify due/overdue watering reminders while the app is open.
- **Share** — Native share API or clipboard fallback for plant info cards.
- **Onboarding** — 3-step welcome flow for first-time visitors.
- **Splash Screen** — Animated launch screen once per session.

## What Is Still Limited

- **Plant.id needs a new/healthy Supabase deploy** — Real recognition requires restoring or replacing the old `rocio` Supabase project, deploying `identify-flower`, setting `PLANT_ID_API_KEY` as a Supabase Edge Function secret, and then re-enabling the public URL/key in `index.html`.
- **Local matcher is fallback only** — It samples image colors and compares against hardcoded flower profiles when Plant.id/Supabase is unavailable. It is clearly labeled as uncertain and never presented as market-grade recognition.
- **Only 15 catalog flowers are supported locally** — Unknown Plant.id species can be detected by the API but may not map to a local care card yet.
- **No Backend / Sync** — Everything is localStorage. No accounts, no cloud backup, no multi-device sync.
- **No Web Push Server** — Current notification support is local/app-open. True scheduled push reminders require backend push subscriptions.
- **No Weather Integration** — Watering calculator still uses manual climate input.
- **Disease/treatment evidence is not source-audited yet** — Existing symptom and treatment guidance is visible only as PENDING verification and must be checked against reliable horticultural sources before being sold as diagnosis or treatment advice.
- **Photo assets pass the local App Store photo gate** — 15/15 catalog JPGs exist, all have attribution rows, none have pending license/source audit markers, and all meet the local 800px minimum-dimension threshold. Keep attribution visible and re-run `node qa/photo-asset-audit.mjs --app-store-ready` before using screenshots or metadata.
- **Commercial/App Store claims are guarded but not verified** — `qa/commercial-claim-audit.mjs` checks that disease/treatment content stays labeled as PENDING botanical verification, scanner and README copy stay honest about local matching, and no Plant.id secret is present in the browser build.
- **Botanical content coverage is guarded, not medically verified** — `qa/botanical-content-audit.mjs` verifies that every catalog flower has complete disease rows and every Plant Doctor symptom cause has complete guidance while still rendering treatment text behind PENDING verification and caveats.
- **App Store/Lovable static readiness is guarded locally** — `qa/appstore-static-readiness-audit.mjs` verifies local privacy/support drafts, iOS/PWA metadata, manifest identity, App Store owner-action blocks, and Lovable no-publish/no-secret constraints while still reporting `appStoreSubmissionReady: false`.

## Top Next Steps to Make This Commercial

### 1. Backend Push Notifications

Add Web Push subscriptions plus a daily job that sends watering reminders even when Rocío has not opened the app.

### 2. Expand Plant.id Result Coverage

The Supabase proxy is now the intended architecture. Next: add generic care guidance for Plant.id species that are outside the 15-flower local catalog.

### 3. Multi-Device Sync + Family Sharing

Add optional sign-in and shared garden access so Julio/Rocío can manage the same garden from multiple devices.

---

*Built with love for Rocío Calderón. A single index.html, zero dependencies, local-first plant identification, and a clear path from charming MVP to real plant-care product.*
