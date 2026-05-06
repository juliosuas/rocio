# Rocío - Status Report

## What Works (Real, Functional)

- **Flower Catalog** — 15 flowers with botanical care data and local app-owned image assets (Rosa, Tulipán, Orquídea, Girasol, Lavanda, Gardenia, Jazmín, Hortensia, Lirio, Margarita, Clavel, Violeta, Geranio, Petunia, Cempasúchil).
- **Mi Jardín** — Add/remove plants, track watering, set status, write notes. Persisted in localStorage and sorted by urgency.
- **Watering Tracker** — Tap to water with animation, last-watered tracking, urgency dots, streak, and stats dashboard.
- **Weekly Calendar** — Shows which plants need water by day; tasks have water buttons directly inside the calendar.
- **Moon Phase Calendar** — Real Conway-style moon phase algorithm with gardening recommendations.
- **Seasonal Tips** — 36 tips across all 12 months, culturally relevant for Mexico.
- **Plant Doctor** — Symptom categories, pest profiles, home remedies, and treatments.
- **Composting Guide** — Green/brown guide, DIY fertilizers, vermicomposting.
- **Watering Calculator** — Adjusts water amount by pot size, location, climate, and season.
- **Dark Mode** — Full dark theme with persisted preference.
- **Plant.id Identifier via Supabase** — Camera/file-upload flow uses a Supabase Edge Function proxy so Plant.id secrets stay server-side. Rocío resizes/compresses the flower image, sends it to Supabase, maps Plant.id suggestions through the local flower catalog, shows uncertainty/top candidates, and falls back gracefully if the API is unavailable or does not map to a local care card.
- **Scan History** — Saves recent scans locally.
- **Offline Shell** — `manifest.webmanifest` + `sw.js` cache the app shell and local flower assets for first-load offline support.
- **Local Notifications** — Requests notification permission when the first plant is added and can notify due/overdue watering reminders while the app is open.
- **Share** — Native share API or clipboard fallback for plant info cards.
- **Onboarding** — 3-step welcome flow for first-time visitors.
- **Splash Screen** — Animated launch screen once per session.

## What Is Still Limited

- **Plant.id needs Supabase secret/deploy** — Real recognition requires deploying `identify-flower` and setting `PLANT_ID_API_KEY` as a Supabase Edge Function secret.
- **Local matcher is fallback only** — It samples image colors and compares against hardcoded flower profiles when Plant.id/Supabase is unavailable. It is clearly labeled as uncertain and never presented as market-grade recognition.
- **Only 15 catalog flowers are supported locally** — Unknown Plant.id species can be detected by the API but may not map to a local care card yet.
- **No Backend / Sync** — Everything is localStorage. No accounts, no cloud backup, no multi-device sync.
- **No Web Push Server** — Current notification support is local/app-open. True scheduled push reminders require backend push subscriptions.
- **No Weather Integration** — Watering calculator still uses manual climate input.

## Top Next Steps to Make This Commercial

### 1. Backend Push Notifications

Add Web Push subscriptions plus a daily job that sends watering reminders even when Rocío has not opened the app.

### 2. Expand Plant.id Result Coverage

The Supabase proxy is now the intended architecture. Next: add generic care guidance for Plant.id species that are outside the 15-flower local catalog.

### 3. Multi-Device Sync + Family Sharing

Add optional sign-in and shared garden access so Julio/Rocío can manage the same garden from multiple devices.

---

*Built with love for Rocío Calderón. A single index.html, zero dependencies, offline-ready shell, and a clear path from charming MVP to real plant-care product.*
