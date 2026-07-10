# 🌸 Rocío

**Cuida tus flores con amor**

Rocío (meaning "dew" in Spanish) is a flower-care product with a zero-dependency web demo and a native SwiftUI iOS app. The web demo keeps an honest local flower matcher. The native iOS track now includes an authenticated Supabase/Plant.id path, while deployment credentials remain a release blocker.

The iOS version is SwiftUI, not a WebView wrapper. It uses a required account for garden sync and AI quota, keeps a local cache for resilience, stores sessions in Keychain, and retains local notifications and App Intents.

## ✨ Features

- **🌸 Catálogo** — Browse 15+ flowers with detailed care information (Spanish + scientific names)
- **🌱 Mi Jardín** — Track your personal garden, watering schedule, and plant health
- **📅 Calendario** — Weekly care schedule with color-coded urgency
- **💡 Tips** — Seasonal gardening tips that rotate monthly
- **📸 Identificador experimental** — Camera/file upload flow with uncertainty, top candidates, correction buttons, and an honest local fallback while real recognition is blocked
- **🔔 Recordatorios** — Local watering reminder support for due/overdue plants while the app is open
- **🌙 Dark Mode** — Beautiful dark theme toggle
- **🌐 Cloud recognition path** — Authenticated Supabase Edge Function + Plant.id, explicit photo consent, monthly quota, no raw image database storage, and local fallback

## 🎨 Design

- Soft sage green, cream ivory, rose pink, and earth brown palette
- Glassmorphism elements and micro-animations
- Mobile-first responsive layout
- Smooth CSS-only page transitions
- Onboarding walkthrough for first-time visitors

## 🛠 Tech

### Web MVP

- Single `index.html` app
- Zero framework dependencies
- Optional Plant.id API integration
- localStorage persistence
- Pure vanilla JS + modern CSS
- Works on iPhone Safari, Android Chrome, Desktop

### Native iOS Track

- SwiftUI app under `ios/`
- Bundle id: `com.juliosuas.rocio`
- Catalog, Garden, Calendar, Scanner, and Settings tabs
- Native onboarding, catalog filters, garden summary, and scanner confidence bands
- Supabase email accounts, Keychain session storage, and account-owned garden sync
- Native local notifications for watering reminders
- App Intents for opening the garden, opening scanner, and logging watering
- Export, cloud garden deletion, analytics opt-out, sign out, and permanent in-app account deletion
- Privacy manifest and App Store privacy answers
- GitHub Actions build/test/archive gates on macOS runners

## 🚀 Launch Demo

Run a local demo:

```sh
python3 -m http.server 3002
```

Open:

- Landing: `http://localhost:3002/launch.html`
- App: `http://localhost:3002/index.html`
- Privacy: `http://localhost:3002/privacy.html`
- Support: `http://localhost:3002/support.html`

Launch materials live in:

- `DEMO_RUNBOOK.md`
- `APP_STORE_METADATA.md`
- `APP_STORE_PRIVACY_ANSWERS.md`
- `APP_STORE_VISUAL_RELEASE_CHECKLIST.md`
- `COMPETITIVE_BENCHMARK.md`
- `MARKETING_LAUNCH_KIT.md`
- `APPLE_DEVELOPER_RUNBOOK.md`
- `APP_STORE_RELEASE_CHECKLIST.md`
- `GSTACK_APP_STORE_DAILY_PLAN.md`
- `ROCIO_BRAIN.md`

## ✅ CI / Release Gates

GitHub Actions currently validates:

- PWA flower classifier QA
- iOS simulator build and unit tests
- Unsigned iOS Release archive
- GitHub Pages deployment

The local machine does not need full Xcode for the core build gate because iOS validation runs on GitHub macOS runners. Full Xcode is still useful later for local simulator screenshots, device smoke testing, and Xcode Organizer upload.

## 🍎 App Store Status

Ready in repo:

- Native SwiftUI foundation
- App Store metadata draft
- Privacy answers draft
- Privacy/support web pages
- Launch/marketing kit
- Apple Developer runbook
- CI build/test/archive gates

Still external/manual:

- Apple Developer Program enrollment
- App Store Connect app record
- Bundle ID confirmation for `com.juliosuas.rocio`
- Signing certificate/provisioning setup
- TestFlight upload
- Final screenshots and app icon review

## 📸 Screenshots

<!-- Add screenshots here -->

## 🔗 Live

**[https://juliosuas.github.io/rocio/](https://juliosuas.github.io/rocio/)**

## 📄 License

MIT
