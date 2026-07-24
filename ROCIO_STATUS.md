# Rocío 1.0: Current Status

Last updated: July 24, 2026

Implementation branch: `fsociaty/rocio-arbitrary-plants`

Base commit: `649293e`

Rocío is a locally verified iOS feature candidate, not a production release. The native arbitrary-plant implementation is complete enough for integration testing, but its matching Supabase migrations and Edge Function update have not been deployed. Rocío is not available through TestFlight or the App Store.

## Native iOS Implementation

The native runtime is no longer limited to the bundled catalog:

- **15 bundled editorial guides** remain available with attributed photography and curated care copy.
- **Plant.id results retain their own identity** including source, stable provider identifier when supplied, common and scientific names, rank, locale, and capture freshness. Taxonomy and confidence are normalized in the scan response but are not yet stored as long-term garden fields.
- **Manual plant entry** provides an offline fallback when a provider result is unavailable or the user does not want to upload a photo.
- **Durable saved plants** keep a versioned identity and care snapshot instead of depending on a `FlowerCatalog` lookup.
- **Optional user-confirmed care** supports dry, medium, or wet watering preferences and optional reminder schedules. Unknown plants do not receive invented milliliter or interval precision.
- **Offline persistence** uses owner-bound, versioned primary and backup snapshots. Ownerless or mixed-ownership data fails closed, recoverable single-slot corruption is repaired from its valid peer, and unsafe replacement inputs are quarantined instead of being claimed by another account.
- **Generic rendering** keeps non-catalog plants visible in Garden, Calendar, notifications, App Intents, export, watering, and deletion flows.
- **Duplicate specimens** are supported. Two plants of the same species can keep independent nicknames, schedules, and watering state.
- **Account synchronization contract** carries arbitrary identity and care fields through the same account isolation, RLS, delete-wins, reset, and purge boundaries used by bundled plants.
- **Per-photo privacy** still offers on-device matching or fresh consent before a reduced image is sent through the authenticated Supabase proxy.
- **Idempotent paid scans** use one stable request UUID, atomically claim quota once, recover ambiguous Plant.id work through `custom_id`, and replay a bounded normalized result for seven days without storing raw photos or provider tokens.

## Verification Evidence

Current evidence for the arbitrary-plant branch:

- **194/194 XCTest cases pass** under both the unsigned-CI contract on iPhone 17 Pro and the locally signed contract on iPhone 17 Pro Max with iOS 26.3.1.
- **Edge runtime tests pass 28/28**, including timeout, body-abort, idempotent recovery, replay, quota, deletion, and malformed-provider paths.
- **Static cloud/security audit passes 50/50**.
- **PostgreSQL 16 four-migration harness passes**, including ordered upgrade, RLS, ACLs, idempotent quota/replay lifecycle, tombstones, reset, purge, and rollback.
- **Release gate passes 12/12**.
- **Strict local classifier passes 12/12**.
- **Unsigned App Store audit passes 20/20** with `unsignedReady=true`.
- **Unsigned Release build passes** with signing disabled.
- **Six real simulator screenshots** are in `docs/screenshots/ios/` and are not mockups. Five document the bundled catalog, garden, calendar, scanner, and settings surfaces; the July 23 manual Swiss cheese plant capture is real Debug-build evidence of the newer arbitrary-plant flow. None is final App Store art.

`signedReady=false` remains the correct App Store result until a paid distribution team is configured.

## Deployment and Release Work Remaining

These items prevent a production-readiness claim:

1. Review and merge the stacked pull request with Edge runtime tests and every repository gate green.
2. Review the final migration dry run, then apply `20260721000100_preserve_garden_deletions.sql`, `20260722000100_support_arbitrary_plants.sql`, and `20260723000100_idempotent_scan_requests.sql` in that order before deploying the matching Edge Function update.
3. Complete a two-session authenticated smoke test covering add, edit, water, relaunch, sync, delete-wins, reset, purge, and account switching.
4. Complete real-device tests for camera, photo picker, per-photo consent, offline behavior, notification permission, scheduling, and delivery.
5. Configure the stable HTTPS Site URL, exact Auth redirect allowlist, custom SMTP, and the complete email → app → new-password recovery path.
6. Activate the paid Apple Developer Program, configure `DEVELOPMENT_TEAM`, create a distribution-signed archive, and upload it to TestFlight.
7. Capture final English App Store screenshots from that exact Release archive and repeat a focused Spanish localization smoke.

Production migration and Edge deployment are owner actions. They must not be run from an unreviewed feature branch.

## Separate Web/PWA Demo

The public `index.html` experience remains a zero-dependency local-data demo. It is not the native application and it does not exercise the new arbitrary-plant cloud contract.

It currently provides:

- a fixed 15-flower editorial catalog and local image matcher;
- a browser-local garden, watering records, weekly and lunar calendars;
- 36 seasonal tips, Plant Doctor, composting, and a watering calculator;
- dark mode, onboarding, scan history, sharing, and browser-limited reminders;
- export and deletion of data stored in the current browser.

Its cloud configuration is intentionally blank. The web demo does not create accounts, synchronize with Supabase, call Plant.id, or install an iOS binary.

## Product Boundaries

- Identification is probabilistic and care guidance is assistive. Rocío does not promise perfect recognition or professional botanical diagnosis.
- The 15 bundled guides are the only editorial care records and local matcher targets. Arbitrary native plants use saved identity, generic presentation, and user-confirmed care.
- Disease and treatment content remains marked pending botanical verification and must not be presented as validated medical, toxicity, edibility, or treatment advice.
- External plant images, remote encyclopedia content, family sharing, weather integration, StoreKit, and a Web Push server remain post-release extensions.

The detailed implementation ledger and fastest remaining execution order are in [`GSTACK_APP_STORE_DAILY_PLAN.md`](GSTACK_APP_STORE_DAILY_PLAN.md).

---

*Built with love for Rocío Calderón. The native SwiftUI app is the App Store product; the web demo remains a separate local-data preview.*
