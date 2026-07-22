# Rocío: 12-Hour Production Completion Plan

Last updated: 2026-07-22

Branch: `fsociaty/rocio-beta-first-care`

Current PR: [#20](https://github.com/juliosuas/rocio/pull/20)

Operating mode: resume-ready; the long-running CTO goal remains paused until the user resumes it.

## Mission

Turn Rocío 1.0 from a polished 15-flower beta into a production-capable plant-care app that can accept, save, sync, and care for arbitrary plants returned by the configured provider or entered manually.

"All plants" means the app is no longer hard-coded to `FlowerCatalog.all`. It does not mean perfect recognition or authoritative care instructions for every known species. The current Plant.id product advertises coverage for more than 35,000 taxa, but identification remains probabilistic and provider coverage can change.

## Ship Standard

The sprint is complete only when a plant outside the bundled 15-flower catalog can:

1. Be returned by a consented cloud scan or entered manually when the provider is unavailable.
2. Be selected without being replaced by the closest bundled flower.
3. Be saved to the garden with a stable provider taxon identifier.
4. Retain a local care profile and remain useful offline.
5. Use an editable watering schedule and local reminders.
6. Sync between accounts/devices under the same RLS and deletion rules as bundled plants.
7. Render safely in Garden, Calendar, Scanner, Settings, App Intents, export, and delete flows.
8. Preserve source, language, and freshness metadata for provider-derived identity data.
9. Avoid presenting uncertain identification, toxicity, edibility, disease, or treatment text as fact.
10. Pass the complete release gate, migration harness, XCTest suite, and physical-device smoke.

## Current Constraint

Plant.id results outside the local catalog are displayed, but the app still requires a bundled `Flower` value for its primary result and garden model. The following runtime paths depend on `FlowerCatalog.flower(id:)` and therefore cannot represent an arbitrary species correctly:

- `ios/Rocio/Services/FlowerIdentifier.swift`
- `ios/Rocio/Models/GardenPlant.swift`
- `ios/Rocio/Stores/GardenStore.swift`
- `ios/Rocio/Services/WateringNotificationScheduler.swift`
- `ios/Rocio/Intents/RocioIntents.swift`
- `ios/Rocio/Views/Garden/GardenView.swift`
- `ios/Rocio/Views/Scanner/ScannerView.swift`

The first production change must remove that dependency from saved plants without breaking existing users.

## Confirmed P0 Implementation Blockers

1. `GardenPlant` persists only `flowerId`; an unknown plant has no durable identity or care state.
2. Garden, Calendar, notifications, and App Intents omit plants that cannot be resolved through `FlowerCatalog`.
3. The scanner overlays an external name on a local color match, so the external species cannot be selected or saved honestly.
4. The Edge Function and iOS DTO discard the provider's persistent suggestion ID, `is_plant`, rank, and locale.
5. The current `Flower` model requires exact care fields that the provider does not reliably supply.
6. Persistence decode failures return an empty array, which can turn a migration mistake into silent garden loss.
7. The Supabase garden contract cannot sync arbitrary identity/care fields, and deletion tombstones do not yet scrub them.
8. `GardenStore.add` currently prevents two specimens of the same species.
9. The Edge request asks for `health: "auto"` but discards health output, adding provider-cost and privacy risk without product value.

Treat these as the first acceptance tests, not as a separate discovery phase.

## Target Data Model

### `PlantIdentity`

Stable identity independent of display copy:

- `source`: `bundled`, `plant_id`, or `manual`
- `sourceID`: persistent provider class ID when available
- `scientificName`
- localized `commonName`
- optional rank and taxonomy identifiers when the provider returns them

Never use a mutable scientific/common-name string as the database primary key. Kindwise documents its class `id` as persistent and recommends it for internal mapping.

### `PlantCareProfile`

An offline snapshot attached to the saved plant:

- optional provider watering preference and a user-selected reminder interval
- optional user-confirmed water amount
- optional light preference
- safety fields only when explicitly known; unknown stays unknown
- `source`, `language`, `fetchedAt`, and `schemaVersion`
- a user-editable override layer that is never overwritten by refresh

Provider data must not be converted into false precision. Plant.id's watering detail is a dry/medium/wet preference range, not an exact number of milliliters or days. Rocío must ask the user to confirm the reminder interval.

### `GardenPlant`

Persist the plant's identity and care snapshot instead of only `flowerId`:

- keep `flowerId` temporarily for backward decoding and bundled-asset lookup
- add `identity`, `careProfile`, and optional `imageReference`
- migrate old records deterministically from the bundled catalog
- encode a schema version and test decoding every previous fixture

## Cloud Contract

The client must never call Plant.id directly.

1. Keep `PLANT_ID_API_KEY` only in Supabase secrets.
2. Extend the authenticated Edge Function response with the persistent class ID, `is_plant`, common/scientific names, locale, rank, and confidence.
3. Remove the unused `health: "auto"` request so identification cannot consume a second provider credit without delivering health results.
4. Add an idempotent request ID, strict body/response validation, timeout handling, per-user quotas, and global budget protection.
5. Delete the provider-side identification after Rocío normalizes the response, unless a reviewed retention contract explicitly requires otherwise.
6. Do not store raw user photos. Continue storing only bounded operational scan metadata.
7. Apply the same RLS, account deletion, analytics opt-out, and audit boundaries used by the current scanner.

Useful provider references:

- [Plant.id API documentation](https://plant.id/docs)
- [Kindwise API handbook](https://www.kindwise.com/handbook)
- [Knowledge-base name search and detail endpoints](https://www.kindwise.com/post/api-search-for-plant-insect-mushroom-details-by-its-name)

## 12-Hour Execution Order

This sprint targets one complete production vertical: **any scanned or manually entered plant can be saved, scheduled, used offline, synced, and rendered everywhere**. Remote name search, external images, encyclopedia content, diagnosis, and new recommendation systems are explicitly post-sprint work.

### Hour 0:00-0:30 — Freeze scope and establish one base

- Merge or rebase the stacked PR chain in order: PR18, PR19, then PR20.
- Record the exact release SHA and re-run CI from it.
- Freeze unrelated PWA, StoreKit, content, and visual-polish work.
- Keep production migrations unapplied until their matching client contract is integrated.

Exit evidence: clean branch, one base SHA, existing 115 XCTest passing, release gate 11/11.

### Hour 0:30-2:15 — Versioned domain and crash-safe persistence

- Add `PlantIdentity` and `PlantCareProfile` as `Codable`, `Equatable`, and `Sendable` values.
- Add backward-compatible `GardenPlant` decoding from `flowerId` and keep the 15 bundled entries as editorial guides.
- Add an explicit `.unscheduled` state; never invent a three-day interval for an unknown plant.
- Replace decode-to-empty behavior with a versioned snapshot, backup, and surfaced recovery path.
- Make the garden snapshot and sync outbox durable as one logical write.
- Add fixtures for a bundled rose, an external monstera, a manual plant, and a corrupt legacy snapshot.

Exit evidence: old gardens decode unchanged; corruption cannot silently erase a garden; arbitrary plants round-trip locally and through export.

### Hour 2:15-3:45 — Additive cloud contract

- Add identity, locale, optional care, and schema-version fields to the garden contract.
- Backfill the 15 bundled flowers deterministically.
- Update fetch/upsert DTOs and deletion-tombstone scrubbing for every new field.
- Reject or normalize implausible client `updated_at` values and enforce payload/row limits.
- Extend the PostgreSQL 16 upgrade fixture before applying any production migration.

Exit evidence: legacy and arbitrary plants round-trip through the disposable database with RLS, delete-wins, reset, and purge intact.

### Hour 3:45-5:15 — Remove catalog assumptions from consumers

- Garden, Calendar, notification scheduling, App Intents, and export read the saved identity/profile instead of requiring `FlowerCatalog`.
- Render a generic botanical placeholder when no bundled art exists.
- Support optional intervals and amounts without misleading copy.
- Allow multiple specimens of the same species, each with its own schedule and nickname.

Exit evidence: a manual non-catalog plant appears everywhere, survives relaunch, can be watered/deleted, and never disappears from a failed catalog lookup.

### Hour 5:15-6:45 — Make the scanner save real provider results

- Decouple `IdentificationResult` from `Flower`.
- Preserve the provider's stable ID, `is_plant`, localized/common name, scientific name, rank, locale, and confidence.
- Make external candidates selectable and stop substituting the closest local flower.
- Add a confirmation step for nickname and optional watering interval.
- Add manual offline entry as the provider-free fallback.

Exit evidence: an external monstera and a manual unknown plant both reach Garden without being relabeled as a bundled flower.

### Hour 6:45-8:15 — Edge runtime, budget, and privacy safety

- Remove unused `health: "auto"` provider work.
- Add strict request/response validation, response-size bounds, timeouts, idempotent request IDs, per-user quotas, and global budget protection.
- Count quota according to the agreed successful-result rule so retries do not double-charge the user.
- Normalize `is_plant`, stable ID, locale, rank, and names into the iOS DTO.
- Delete provider-side identification data after normalization unless a reviewed retention policy says otherwise.
- Add runtime tests for valid, no-plant, malformed, timeout, retry, quota, locale, and unauthenticated cases.

Exit evidence: the runtime—not only a static source audit—proves the security and failure contract.

### Hour 8:15-10:00 — Product, migration, and two-session QA

- Test legacy decode, corrupt snapshot recovery, offline add/edit/water/relaunch/export, two roses, and a plant with no schedule.
- Test two sessions, future timestamps, delete-wins, account switch, reset, purge, and tombstone scrubbing.
- Verify every provider failure leaves the existing garden usable.
- Verify accessibility labels, Dynamic Type, dark appearance, and English/Spanish fallback behavior.
- Keep toxicity, edibility, health, disease, and treatment fields out of this sprint.

Exit evidence: focused XCTest and the disposable PostgreSQL matrix pass with recorded simulator/device evidence.

### Hour 10:00-12:00 — Integrate one release candidate

- Run the complete XCTest suite, unsigned Release build, release gate, cloud/security audit, App Store audit, and PostgreSQL harness.
- Complete physical camera, photo-picker, consent, notification-permission, offline, and delivery smoke.
- Capture English screenshots from the exact release-candidate build and repeat a focused Spanish localization smoke.
- Update README, privacy, support, metadata, review notes, and PR evidence.
- Leave only owner actions: production migration/Edge deployment, paid distribution, App Store Connect, SMTP/redirect configuration, and TestFlight upload.

Exit evidence: one reviewed release-candidate commit, a precise deploy order, and no known P0/P1 defect in the arbitrary-plant vertical.

## Explicit Post-Sprint Work

- remote name search and provider profile caching;
- external images and license presentation;
- enriched taxonomy and encyclopedia descriptions;
- toxicity, edibility, disease, diagnosis, and treatment content;
- generated recommendations or a new local classifier;
- StoreKit, PWA expansion, and full watering history.

These are product extensions, not prerequisites for the arbitrary-plant care loop above.

## Parallel Agent Allocation

Run at most three implementation tracks against separate files, with one integration owner:

1. Domain/client: Swift models, persistence, scanner selection, UI.
2. Cloud/security: Edge Function, migration, RLS, PostgreSQL tests.
3. QA/release: fixtures, screenshots, docs, audits, physical-device checklist.

The integration owner rebases each track onto the same release SHA, resolves model/contract changes, runs the full suite, and is the only agent allowed to push the release branch.

## External Blockers That Must Not Stall Local Work

- Paid Apple Developer Program and distribution team.
- App Store Connect app record and TestFlight upload.
- Supabase Auth redirect allowlist, stable HTTPS Site URL, and custom SMTP.
- Approval to deploy the pending production migration.
- Plant.id production pricing/credit tier and confirmation that the requested detail fields are included.

Build and test every contract locally with fixtures while these owner actions remain pending.

## Final Validation Commands

```sh
node qa/release-gate.mjs
node qa/readonly-flower-classifier-harness.mjs --strict
node qa/cloud-ai-security-audit.mjs
node qa/ios-app-store-readiness-audit.mjs

ROCIO_SECURITY_DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:5432/postgres' \
  node qa/run-cloud-ai-security-postgres.mjs

xcodebuild \
  -project ios/Rocio.xcodeproj \
  -scheme Rocio \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3' \
  test
```

## Stop Conditions

Do not claim production readiness when any of these is true:

- an external result is still replaced by a bundled flower;
- a saved plant loses its profile offline;
- any displayed provider copy or image lacks its required source/license metadata;
- a provider failure blocks access to an existing garden;
- arbitrary plants break notifications, App Intents, export, sync, or deletion;
- the migration has not passed the disposable PostgreSQL upgrade harness;
- the physical permission and notification smoke remains incomplete;
- distribution signing is still unavailable.

## Resume Command

When the user resumes the paused 12-hour goal, start at **Hour 0:00**, verify the PR chain and current SHA, then assign the three parallel tracks above. Do not spend the first hour reinstalling tools or re-auditing facts already recorded in this plan unless the branch or remote state changed.
