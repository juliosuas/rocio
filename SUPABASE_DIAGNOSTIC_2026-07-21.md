# Rocio Supabase Diagnostic — 2026-07-21

Project: `gnumzynfewmurvykopxq`

This report records read-only evidence gathered from Supabase CLI, the remote
Postgres catalog, public HTTP probes, and the authenticated Dashboard. No
secrets were printed and no remote SQL or configuration changes were made.

## Verdict

Supabase is not currently missing Rocio's foundation schema. The historical
404 responses happened before the foundation migration was applied. The
project is now healthy, the six API tables exist with RLS enabled, and the
deployed Edge Function rejects an unauthenticated caller correctly.

The remaining backend change is the deletion-preserving migration
[`20260721000100_preserve_garden_deletions.sql`](supabase/migrations/20260721000100_preserve_garden_deletions.sql).
It must remain pending until the client code that understands tombstones and
garden epochs is integrated. Do not run the SQL manually or apply it twice.

Password recovery has a separate configuration blocker. Authentication → URL
Configuration currently uses `http://localhost:3000` as Site URL and has no
additional redirect URLs, so Supabase does not allow Rocio's exact callback
`com.juliosuas.rocio://auth/recovery`. Custom SMTP is also disabled. The reset
template itself is correct and uses `{{ .ConfirmationURL }}`. These settings do
not explain ordinary sign-in failures, but they prevent a reliable end-to-end
password reset until they are changed deliberately.

The matching iOS client is backward-compatible with this deployment order.
Authentication is published independently of garden readiness; if the epoch
columns are still absent, the app keeps the valid session and local garden,
queues edits, and sends no garden mutation. The first write lifecycle reads
the current server epoch; later writes carry the last causally observed epoch,
which the database rejects if a concurrent reset has rotated it. Only
mutations created after a recorded preflight (or the safe never-reset
bootstrap case) may adopt that epoch; ambiguous edits made while the preflight
is in flight stay local. An
epoch conflict inherited from an older lifecycle is quarantined locally until
the user explicitly resets local data; it does not block causally authorized
changes. Eligible queued changes persist their validated epoch so they can
resume safely after an app relaunch, and mutations queued behind a local reset
adopt the epoch returned by that reset.

## Remote Evidence

- Project status: `Healthy`.
- Remote migration history contains `20260709000100_rocio_cloud_foundation`.
- Local migration `20260721000100_preserve_garden_deletions` is not remote yet.
- `profiles`, `garden_plants`, `watering_events`, `scan_usage`, `scan_results`,
  and `analytics_events` all exist. Remote table statistics list all six.
- RLS is enabled on all six tables.
- Every client-facing policy scopes rows through `auth.uid()`.
- `anon` has no table access. `authenticated` has only the operations the app
  needs; notably it cannot write `scan_usage` or `scan_results`.
- `consume_scan_quota`, `delete_my_account`, and `set_analytics_enabled` are
  executable by `authenticated`, use `SECURITY DEFINER`, set an empty
  `search_path`, and derive the affected account from `auth.uid()`.
- Edge Function `identify-flower` is `ACTIVE`, version 5, with gateway JWT
  verification disabled intentionally because the handler validates the
  bearer token with `auth.getUser`.
- A public POST without a bearer token returns HTTP 401 with
  `{"error":"authentication_required"}`.
- All six anonymous PostgREST probes now return HTTP 401/SQLSTATE 42501
  `permission denied`, rather than 404, confirming that the relations exist and
  the table ACL boundary is active.
- The authenticated Dashboard confirms no allowed password-recovery redirect
  and custom SMTP disabled; no settings were changed during this audit.

## Log Timeline

Dashboard times below are the browser's local time on 2026-07-21.

1. `02:33:45`–`02:35:37`: Auth and PostgREST readiness probes returned 521
   while the reactivated project was starting.
2. `02:35:47`: health/readiness returned 200.
3. `03:11:34`: six deliberate PostgREST probes returned 404 because the schema
   had not been migrated yet.
4. `03:34:55`: the foundation migration executed; grants and functions appear
   in the Postgres log.
5. `03:34:57`: PostgREST reloaded a schema cache containing six relations and
   four RPC functions.
6. `03:35:48` and later: unauthenticated table probes return 401/42501, which
   is the intended ACL boundary and proves the relations exist.
7. Edge Function traffic in the last 24 hours contains expected 400/401
   validation responses and no 5xx response.
8. Auth logs contain service restart/configuration messages, not a failed user
   login. API Gateway traffic in the same period contains CLI, management API,
   and curl probes, but no request from the iOS app.

Therefore the first real server failure was the temporary 521 during project
startup, followed by a pre-migration missing-schema 404. Both conditions are
resolved. An iOS app that opens and exits without appearing in API Gateway
fails before it reaches Supabase; server login is not the crash cause.

## Security Findings

- Cross-account reads and writes are blocked by RLS expressions matching
  `auth.uid()` to `id` or `user_id`.
- Scan quota cannot be increased or reset by a mobile client: `authenticated`
  has SELECT-only access to `scan_usage`, and the atomic RPC only increments
  the caller's monthly row.
- A mobile client cannot insert scan history. Only `service_role` can insert
  `scan_results`, and the Edge Function obtains the user id from a validated
  session rather than request JSON.
- Supabase Advisor reports one mutable-search-path warning on the old
  `reject_stale_garden_update` trigger. The pending deletion-preserving
  migration replaces it with an empty `search_path` and is already covered by
  the PostgreSQL 16 migration harness.
- The pending migration now also revokes `DELETE` as well as `UPDATE` on
  `watering_events`, making its advertised append-only ACL real. The static and
  PostgreSQL catalog audits both assert SELECT+INSERT only.
- Advisor also reports the three intentional authenticated `SECURITY DEFINER`
  RPCs. They are public product operations, not accidental grants; each is
  constrained to `auth.uid()`.

## Deployment And Rollback Plan

1. Merge the foundation/client recovery PRs before deploying the pending
   migration.
2. Confirm `supabase migration list --linked` shows the foundation migration
   remotely and only `20260721000100` locally.
3. Run the PostgreSQL 16 harness and cloud audit from the exact commit to ship.
4. Run `supabase db push --linked --dry-run` and review that only the canonical
   pending migration is selected.
5. In Auth URL Configuration, add exactly
   `com.juliosuas.rocio://auth/recovery`; replace the localhost Site URL only
   with the chosen stable HTTPS product URL. Configure custom SMTP before an
   external beta. These are explicit Dashboard changes and require separate
   approval/credentials.
6. Apply the migration once with `supabase db push --linked`.
7. Re-run the catalog/RLS/ACL checks and authenticated two-account tests.

Before commit, migration failure rolls back transactionally. After commit, do
not use `DROP`, `TRUNCATE`, migration repair, or a raw rerun as rollback. Keep
the migration recorded and ship a forward corrective migration. Re-enabling
physical plant deletes would remove tombstones and weaken delete-wins safety,
so it is not an acceptable rollback.

## Final Proofs

Integrated local evidence refreshed on 2026-07-22: 115/115 XCTest cases passed on an
iPhone 17 iOS 26.3.1 simulator; the unsigned Release simulator build passed;
the release gate passed 11/11, cloud security 41/41, App Store readiness 20/20,
and the strict classifier 12/12. The PostgreSQL 16 harness also passed the
foundation migration, a pre-upgrade data fixture, the pending migration,
effective RLS/ACL checks, direct client quota-forgery rejection,
cross-account quota isolation, reset/account-purge checks, and a final
rollback. These are
dated snapshots, not perpetual release guarantees; rerun them from the exact
commit selected for deployment.

Unauthenticated Edge Function request (no secret required):

```sh
curl -i -X POST \
  'https://gnumzynfewmurvykopxq.supabase.co/functions/v1/identify-flower' \
  -H 'Content-Type: application/json' \
  --data '{"test":true}'
```

Expected: HTTP 401 and `authentication_required`.

Cross-user read check in a transaction, using two existing test user UUIDs:

```sql
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', '<USER_A_UUID>', true);
select count(*)
from public.garden_plants
where user_id = '<USER_B_UUID>'::uuid;
rollback;
```

Expected: zero rows, even when user B has garden rows.

Quota-forgery attempt:

```sql
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', '<USER_A_UUID>', true);
insert into public.scan_usage (user_id, period_start, used)
values ('<USER_A_UUID>'::uuid, date_trunc('month', now())::date, 0);
rollback;
```

Expected: `permission denied for table scan_usage`. Use tokens only in the
local test client or Dashboard session; never paste them into chat or docs.
