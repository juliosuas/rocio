# Rocío: 12-Hour Production Completion Ledger

Last updated: July 24, 2026

Implementation branch: `fsociaty/rocio-arbitrary-plants`

Verification target: the exact PR head after the scanner-review increment

Consolidated integration PR: [#21](https://github.com/juliosuas/rocio/pull/21), targeting `main`

Operating mode: active implementation and release hardening. Do not restart the original 12-hour plan from Hour 0; continue from the remaining runtime, integration, deployment, and device work below.

## Mission

Ship one production-capable native care loop in which a Plant.id result or manually entered plant can be saved without being replaced by a bundled flower, remain useful offline, receive optional user-confirmed care, synchronize under the existing security model, and render everywhere the user expects.

"All plants" means the runtime is no longer hard-coded to `FlowerCatalog.all`. It does not mean perfect identification, authoritative care instructions for every taxon, or a reviewed editorial article for every species. The 15 bundled flower guides remain the curated catalog and local matcher dataset.

## Current Outcome

The arbitrary-plant vertical and scanner review-to-Garden handoff are implemented in the current worktree. Both the full unsigned CI-equivalent and locally signed XCTest suites pass 200/200 on iPhone 17 Pro with iOS 26.3.1; exact-PR-head CI confirmation remains pending. The additive database migrations and Edge Function update exist locally and the four-migration PostgreSQL 16 harness passes, but those backend changes have not been deployed. The branch is a feature candidate, not an App Store release candidate.

## Ship Standard Ledger

| Requirement | State | Evidence or remaining proof |
|---|---|---|
| Preserve a Plant.id result without substituting a bundled flower | Implemented and simulator-tested | The scanner response carries provider identity, names, locale, rank, taxonomy, confidence, and `is_plant`; the saved garden identity retains the stable ID, names, rank, locale, and freshness. |
| Scanner review-to-Garden handoff | Implemented and fully simulator-tested | Provider identity remains separate from the specimen nickname; optional user care removes false exact precision; failed saves do not mutate or route; successful saves create one independent specimen and open Garden. |
| Manual provider-free entry | Implemented and simulator-tested | Manual plants use durable manual identity and enter the same garden model. |
| Durable identity and offline care snapshot | Implemented and simulator-tested | `PlantIdentity`, `PlantCareProfile`, and backward-compatible `GardenPlant` decoding round-trip arbitrary and bundled plants. |
| Crash-safe local garden | Implemented and simulator-tested | Versioned primary and backup snapshots recover valid data and surface unrecoverable corruption instead of silently returning an empty garden. |
| Optional editable watering schedule | Implemented and simulator-tested | Dry, medium, and wet preferences can map to app-default reminder intervals; unscheduled plants remain unscheduled until the user chooses. Exact water amounts stay optional. |
| Generic product rendering | Implemented and simulator-tested | Garden, Calendar, notifications, App Intents, export, watering, and deletion no longer require a bundled catalog match. |
| Duplicate specimens | Implemented and simulator-tested | Multiple plants of the same species retain independent identifiers, nicknames, care state, and schedules. |
| Additive account-sync contract | Implemented and PostgreSQL-tested | Identity, care, bounds, legacy compatibility, RLS, delete-wins, reset, purge, and tombstone scrubbing pass the disposable PostgreSQL 16 harness. |
| Provider privacy and metadata contract | Implemented and runtime-tested locally | The Edge update preserves bounded provider metadata, atomically claims quota once per stable request UUID, recovers ambiguous Plant.id work through `custom_id`, replays bounded results, and deletes provider-side identification best-effort. The executable runtime suite passes 28/28. |
| Two-session production behavior | Pending | Requires an authenticated staging/production smoke after the matching backend deployment. |
| Physical-device camera and notifications | Pending | Requires a real iPhone with the release configuration. |
| Distribution-signed archive and TestFlight | Externally blocked | Requires a paid Apple Developer membership, `DEVELOPMENT_TEAM`, signing assets, and App Store Connect. |

## Completed Engineering

### 1. Versioned domain and offline persistence

- Added durable `PlantIdentity` sources for bundled, Plant.id, and manual plants.
- Added optional `PlantCareProfile` data without inventing exact intervals or milliliter amounts.
- Kept legacy `flowerId` decoding and deterministic bundled-guide migration.
- Added versioned primary and backup garden snapshots with a surfaced recovery state.
- Added durable sync-outbox recovery so valid queued changes are not silently discarded.
- Added fixtures for bundled, external, manual, duplicate, legacy, and corrupt records.

### 2. Additive cloud contract

- Added bounded identity, locale, care, and schema-version garden payloads; taxonomy remains bounded in the transient scanner response.
- Preserved backward compatibility for older clients while making saved identity authoritative.
- Added deletion-tombstone scrubbing for the new metadata.
- Enforced row and payload bounds and rejected unsafe future timestamps.
- Extended the PostgreSQL 16 upgrade fixture across all four ordered migrations, including expiry, reclaim, recompletion, replay, and account-purge coverage for the scan ledger.

Deployment status: **not deployed**. Review the backup and linked dry run before applying the deletion-preserving, arbitrary-plant, and idempotent-scan migrations in timestamp order.

### 3. Catalog-independent consumers

- Garden and Calendar use saved identity and care rather than requiring `FlowerCatalog`.
- Notifications and App Intents support arbitrary plants and omit false water-volume precision.
- Export includes generic saved plants.
- Non-catalog plants use a generic botanical presentation when bundled art is unavailable.
- Duplicate specimens are allowed.

### 4. Honest scanner and manual entry

- External suggestions remain external suggestions and keep their provider identity.
- Results marked as not a plant cannot be saved.
- Results pass through an explicit review that shows the suggested identity, source, and confidence while keeping the editable specimen nickname separate.
- A user-confirmed watering preference removes exact catalog interval and milliliter values so the app does not imply false precision.
- Failed saves leave the garden and route unchanged; successful saves create one independent specimen, clear the completed scan, and open Garden.
- Rank, locale, freshness, and stable provider ID survive into the saved model when available. Taxonomy and confidence remain transient scan evidence rather than durable garden claims.
- Manual entry supplies an offline/provider-free path.
- User care remains optional and editable after save.

### 5. Edge privacy and cost changes

- Removed the unused provider health request.
- Preserved `is_plant`, stable ID, names, locale, rank, taxonomy, and confidence.
- Normalized optional provider strings rather than persisting empty identifiers.
- Kept `PLANT_ID_API_KEY` server-side.
- Continued to avoid storing raw user photographs.
- Added best-effort provider-side identification deletion after response normalization.
- Added stable request UUIDs, atomic quota claims, bounded seven-day replay, Plant.id `custom_id` recovery, body timeouts, and executable failure-path coverage.

Deployment status: **not deployed**. Runtime integration tests pass locally; authenticated deployment canaries remain required.

## Verified Evidence

Evidence recorded from the current work:

- **XCTest passes 200/200 under both the unsigned CI-equivalent and locally signed simulator contracts** on iPhone 17 Pro with iOS 26.3.1 for the current scanner-review worktree. Exact-PR-head CI confirmation remains pending.
- **Edge runtime tests pass 28/28**.
- **Static cloud/security audit passes 50/50**.
- **PostgreSQL 16 four-migration harness passes** with ordered upgrade, RLS, ACL, idempotent quota/replay lifecycle, tombstone, reset, purge, and rollback checks.
- **Release gate passes 12/12**.
- **Strict local classifier passes 12/12**.
- **Unsigned App Store audit passes 20/20** with `unsignedReady=true`.
- **Unsigned Release build passes** with signing disabled.
- **Seven real iOS screenshots** are featured in `docs/screenshots/ios/`. Five show the bundled catalog, garden, calendar, scanner, and settings from a running Debug build; the July 23 manual Swiss cheese plant capture covers arbitrary entry; and the July 24 Review plant sheet from feature commit `0a65394` covers the scanner review gate. None is final App Store art.

## Fastest Remaining Execution Path

Follow this order. Do not spend time rediscovering or rebuilding completed domain work.

### R1. Close integration review — completed locally

1. Resolve every actionable code-review finding in the current worktree.
2. Run `git diff --check`.
3. Run focused persistence, cloud-contract, scanner, garden, calendar, notification, App Intent, export, and localization tests.

Exit evidence: no open P0/P1 review finding and focused tests green.

### R2. Prove the Edge runtime — completed locally

Add executable runtime tests for:

- valid arbitrary-plant response;
- provider response with no plant;
- absent and empty optional provider identifiers;
- malformed and oversized provider responses;
- timeout and network failure;
- idempotent retry and quota behavior, including Plant.id `custom_id`
  recovery without a second provider POST;
- locale and taxonomy normalization;
- unauthenticated request rejection;
- provider-side deletion success and failure.

Exit evidence: runtime tests prove the failure contract, not only source-shape
assertions. A stable iOS request UUID must atomically claim quota once, completed
responses must replay from a bounded ledger with a seven-day replay window, and an uncertain provider
call must recover with Plant.id `custom_id` (or safely terminate after the
documented 404 grace period) without issuing a second provider POST.

### R3. Cut one local release candidate — completed locally

Run from one reviewed commit:

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
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' \
  test
```

Also produce an unsigned Release build and archive validation from the same commit.

Exit evidence: current, not inherited, results for XCTest, release gate, cloud/security, App Store audit, PostgreSQL, and unsigned Release.

### R4. Commit, push, and review — active for the scanner-review increment

1. Commit the scanner review-to-Garden increment as one reviewable unit on `fsociaty/rocio-arbitrary-plants`.
2. Push the branch and update consolidated PR #21, which targets `main`.
3. Attach exact commands, current result counts, migration order, deployment warning, and screenshot provenance.
4. Run review and every repository workflow on the exact PR head.
5. Merge #21 only after CI is green, then verify `main` before closing #18–#20 as superseded.

Exit evidence: reviewed commit, green CI, and no unresolved P0/P1 comment.

### R5. Deploy matching backend changes

Owner-controlled sequence:

1. Confirm a database backup and target project.
2. Run `supabase db push --linked --dry-run`.
3. Confirm the remote still has only the foundation migration, then review that the three expected incremental migrations are pending.
4. Apply `20260721000100_preserve_garden_deletions.sql` once.
5. Apply `20260722000100_support_arbitrary_plants.sql` once.
6. Apply `20260723000100_idempotent_scan_requests.sql` once.
7. Deploy the matching `identify-flower` Edge Function.
8. Confirm `PLANT_ID_API_KEY` is a server secret and no secret exists in the client or repository.
9. Run authenticated canaries for legacy bundled plants, arbitrary plants, scan replay, tombstones, reset, purge, quota, and account isolation.

Exit evidence: production schema and Edge version match the reviewed client contract.

### R6. Complete two-session and real-device smoke

Two authenticated sessions:

- add an arbitrary plant on session A and observe it on session B;
- edit care and water it from both sessions;
- verify delete-wins, relaunch, offline queue recovery, reset, purge, and account switching;
- verify provider failures never block access to the existing garden.

Physical iPhone:

- camera, photo picker, local analysis, and per-photo cloud consent;
- review cancellation without mutation, a successful scan → review → Garden save, and duplicate specimens;
- manual entry and a duplicate specimen;
- offline add/edit/water/relaunch/export;
- notification permission, scheduling, delivery, and cancellation;
- Dynamic Type, VoiceOver labels, dark appearance, English, and focused Spanish localization.

Exit evidence: recorded device, OS, build SHA, account isolation result, and every smoke result.

### R7. Sign and distribute

Owner actions:

1. Activate the paid Apple Developer Program.
2. Configure `DEVELOPMENT_TEAM` and distribution signing.
3. Create the exact Release archive used for submission.
4. Capture final English App Store screenshots from that archive and repeat the focused Spanish smoke.
5. Configure App Store Connect, privacy answers, support URL, recovery redirects, and SMTP.
6. Upload to TestFlight and run one final install/update smoke.

Exit evidence: signed TestFlight build with no known P0/P1 defect.

## Explicit Post-Release Work

These are product extensions, not blockers for the arbitrary-plant care loop:

- remote name search and provider profile caching;
- external images and license presentation;
- enriched taxonomy and encyclopedia descriptions;
- toxicity, edibility, disease, diagnosis, and treatment content;
- generated recommendations or a new local classifier;
- family sharing, StoreKit, PWA expansion, weather integration, and full watering history.

## External Blockers That Must Not Stall Local Work

- Paid Apple Developer Program and distribution team.
- App Store Connect app record and TestFlight upload.
- Supabase Auth redirect allowlist, stable HTTPS Site URL, and custom SMTP.
- Owner approval to deploy the pending production migrations and Edge Function.
- Plant.id production credit tier and provider contract confirmation.

Complete code review, runtime tests, simulator QA, static audits, documentation, and the deployment runbook while these owner actions remain pending.

## Stop Conditions

Do not claim production readiness while any of these is true:

- an external result is replaced by a bundled flower;
- a saved plant or queued change can disappear after a recoverable write failure;
- an unscheduled plant receives invented reminder or water-amount precision;
- a provider failure blocks access to an existing garden;
- arbitrary plants break notifications, App Intents, export, sync, reset, purge, or deletion;
- the Edge runtime suite or release gate is failing;
- the matching migrations or Edge Function are not deployed;
- two-session and physical permission/notification smoke tests are incomplete;
- distribution signing is unavailable.

## Resume Point

Resume at **R4: Commit, push, and review** for the scanner-review increment. Treat R1 through R3 as prior evidence until the expanded suite and gates pass on the exact PR head. Move to R5 only after consolidated PR #21 is green, reviewed, merged, and verified on `main`; the backend deployment, two-session/device smoke, and signing steps remain deliberately separate owner-controlled gates.
