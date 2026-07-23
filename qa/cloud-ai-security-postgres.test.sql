\set ON_ERROR_STOP on

-- Reapply the arbitrary-plant migration over a staged, pre-existing tombstone.
-- This reproduces the production upgrade case where reject_stale_garden_update
-- is already installed but there is no request JWT for the migration session.
alter table public.garden_plants
  disable trigger reject_stale_garden_update;
alter table public.garden_plants
  disable trigger scrub_garden_plant_profile;

insert into public.garden_plants (
  id, user_id, flower_id, nickname, added_at, last_watered_at, status, notes,
  updated_at, deleted_at, garden_epoch, identity, care_profile, schema_version
) values (
  'abababab-abab-abab-abab-abababababab',
  '33333333-3333-3333-3333-333333333333',
  'deleted',
  'Deleted plant',
  '2026-07-20 09:00:00+00',
  '2026-07-20 09:00:00+00',
  'healthy',
  '',
  '2026-07-20 09:00:00+00',
  '2026-07-20 09:00:00+00',
  (select garden_epoch from public.profiles where id = '33333333-3333-3333-3333-333333333333'),
  '{"source":"manual","common_name":"Profile that must be scrubbed"}'::jsonb,
  '{"source":"manual","watering_preference":"wet"}'::jsonb,
  2
);

alter table public.garden_plants
  enable trigger scrub_garden_plant_profile;
alter table public.garden_plants
  enable trigger reject_stale_garden_update;

alter table public.garden_plants
  drop constraint garden_plants_schema_version_range,
  drop constraint garden_plants_live_identity_present,
  drop constraint garden_plants_identity_shape,
  drop constraint garden_plants_care_profile_shape;

\ir ../supabase/migrations/20260722000100_support_arbitrary_plants.sql

do $upgrade_fixture$
begin
  if not exists (
    select 1
    from public.profiles as profiles
    join public.garden_plants as plants
      on plants.user_id = profiles.id
     and plants.garden_epoch = profiles.garden_epoch
    where profiles.id = '33333333-3333-3333-3333-333333333333'
      and profiles.garden_epoch is not null
      and plants.id = 'ffffffff-ffff-ffff-ffff-ffffffffffff'
      and plants.deleted_at is null
      and plants.nickname = 'Pre-upgrade rose'
      and plants.notes = 'Existing care history'
      and plants.identity is null
      and plants.care_profile is null
      and plants.schema_version = 1
  ) then
    raise exception 'garden upgrades did not preserve and version an existing plant';
  end if;

  if not exists (
    select 1
    from public.watering_events
    where id = '44444444-4444-4444-4444-444444444444'
      and user_id = '33333333-3333-3333-3333-333333333333'
      and plant_id = 'ffffffff-ffff-ffff-ffff-ffffffffffff'
  ) then
    raise exception 'garden epoch upgrade did not preserve existing watering history';
  end if;

  if not exists (
    select 1
    from public.garden_plants
    where id = 'abababab-abab-abab-abab-abababababab'
      and deleted_at is not null
      and flower_id = 'deleted'
      and identity is null
      and care_profile is null
      and schema_version = 1
  ) then
    raise exception 'arbitrary-plant migration did not scrub a pre-existing tombstone';
  end if;
end;
$upgrade_fixture$;

-- Effective-state checks. These query PostgreSQL after every migration has
-- executed, so a later DROP/REVOKE/CREATE OR REPLACE cannot hide in history.
do $catalog$
declare
  insecure_function text;
begin
  if not exists (
    select 1
    from pg_catalog.pg_attribute
    where attrelid = 'public.garden_plants'::regclass
      and attname = 'deleted_at'
      and atttypid = 'timestamptz'::regtype
      and not attisdropped
  ) then
    raise exception 'garden_plants.deleted_at timestamptz is missing';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_attribute
    where attrelid = 'public.profiles'::regclass
      and attname = 'garden_reset_at'
      and atttypid = 'timestamptz'::regtype
      and not attisdropped
  ) then
    raise exception 'profiles.garden_reset_at timestamptz is missing';
  end if;

  if (select count(*)
      from pg_catalog.pg_attribute
      where (attrelid, attname) in (
        ('public.profiles'::regclass, 'garden_epoch'),
        ('public.garden_plants'::regclass, 'garden_epoch')
      )
        and atttypid = 'uuid'::regtype
        and attnotnull
        and not attisdropped) <> 2 then
    raise exception 'server garden epoch columns are missing or nullable';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_attribute
    where attrelid = 'public.garden_plants'::regclass
      and attname = 'flower_id'
      and atttypid = 'text'::regtype
      and attnotnull
      and not attisdropped
  ) then
    raise exception 'garden_plants.flower_id must remain non-null for mixed-version clients';
  end if;

  if (select count(*)
      from pg_catalog.pg_attribute
      where (attrelid, attname, atttypid, attnotnull) in (
        ('public.garden_plants'::regclass, 'identity', 'jsonb'::regtype, false),
        ('public.garden_plants'::regclass, 'care_profile', 'jsonb'::regtype, false),
        ('public.garden_plants'::regclass, 'schema_version', 'int2'::regtype, true)
      )
        and not attisdropped) <> 3 then
    raise exception 'versioned arbitrary-plant profile columns are missing or incorrectly typed';
  end if;

  if (select count(*)
      from pg_catalog.pg_constraint
      where conrelid = 'public.garden_plants'::regclass
        and contype = 'c'
        and convalidated
        and conname in (
          'garden_plants_schema_version_range',
          'garden_plants_live_identity_present',
          'garden_plants_identity_shape',
          'garden_plants_care_profile_shape'
        )) <> 4 then
    raise exception 'arbitrary-plant profile constraints are missing or unvalidated';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_class
    where oid = 'public.garden_plants'::regclass
      and relrowsecurity
  ) then
    raise exception 'garden_plants RLS is not enabled';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_class
    where oid = 'public.scan_results'::regclass
      and relrowsecurity
  ) then
    raise exception 'scan_results RLS is not enabled';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_class
    where oid = 'public.scan_usage'::regclass
      and relrowsecurity
  ) then
    raise exception 'scan_usage RLS is not enabled';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_class
    where oid = 'public.scan_requests'::regclass
      and relrowsecurity
  ) then
    raise exception 'scan_requests RLS is not enabled';
  end if;

  if (select count(*)
      from pg_catalog.pg_constraint
      where conrelid = 'public.scan_requests'::regclass
        and contype = 'c'
        and convalidated
        and conname in (
          'scan_requests_state',
          'scan_requests_response_size',
          'scan_requests_completion_shape',
          'scan_requests_retention_window'
        )) <> 4 then
    raise exception 'scan request bounds are missing or unvalidated';
  end if;

  if (select count(*)
      from pg_catalog.pg_policies
      where schemaname = 'public'
        and tablename = 'scan_usage') <> 1
     or not exists (
       select 1
       from pg_catalog.pg_policies
       where schemaname = 'public'
         and tablename = 'scan_usage'
         and policyname = 'scan_usage_select_own'
         and permissive = 'PERMISSIVE'
         and cmd = 'SELECT'
         and qual like '%auth.uid() = user_id%'
         and with_check is null
     ) then
    raise exception 'scan_usage owner policy is missing, weakened, or accompanied by another policy';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'garden_plants'
      and policyname = 'garden_plants_own'
      and cmd = 'ALL'
      and qual like '%auth.uid() = user_id%'
      and with_check like '%auth.uid() = user_id%'
  ) then
    raise exception 'garden_plants owner policy is missing or weakened';
  end if;

  if exists (
    select 1
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'scan_results'
      and cmd in ('INSERT', 'ALL')
  ) then
    raise exception 'scan_results gained a client insert policy';
  end if;

  if not pg_catalog.has_table_privilege('authenticated', 'public.garden_plants', 'SELECT')
     or not pg_catalog.has_table_privilege('authenticated', 'public.garden_plants', 'INSERT')
     or not pg_catalog.has_table_privilege('authenticated', 'public.garden_plants', 'UPDATE') then
    raise exception 'authenticated garden read/upsert ACL is incomplete';
  end if;

  if pg_catalog.has_table_privilege('authenticated', 'public.garden_plants', 'DELETE') then
    raise exception 'authenticated can physically delete garden tombstones';
  end if;

  if pg_catalog.has_table_privilege('authenticated', 'public.scan_results', 'INSERT')
     or not pg_catalog.has_table_privilege('authenticated', 'public.scan_results', 'SELECT')
     or not pg_catalog.has_table_privilege('service_role', 'public.scan_results', 'INSERT') then
    raise exception 'scan_results ACLs are not server-write/client-read';
  end if;

  if not pg_catalog.has_table_privilege('authenticated', 'public.scan_usage', 'SELECT')
     or pg_catalog.has_table_privilege('authenticated', 'public.scan_usage', 'INSERT')
     or pg_catalog.has_table_privilege('authenticated', 'public.scan_usage', 'UPDATE')
     or pg_catalog.has_table_privilege('authenticated', 'public.scan_usage', 'DELETE')
     or pg_catalog.has_table_privilege('authenticated', 'public.scan_usage', 'TRUNCATE')
     or pg_catalog.has_table_privilege('authenticated', 'public.scan_usage', 'REFERENCES')
     or pg_catalog.has_table_privilege('authenticated', 'public.scan_usage', 'TRIGGER')
     or pg_catalog.has_table_privilege('anon', 'public.scan_usage', 'SELECT')
     or pg_catalog.has_table_privilege('anon', 'public.scan_usage', 'INSERT')
     or pg_catalog.has_table_privilege('anon', 'public.scan_usage', 'UPDATE')
     or pg_catalog.has_table_privilege('anon', 'public.scan_usage', 'DELETE')
     or pg_catalog.has_table_privilege('anon', 'public.scan_usage', 'TRUNCATE')
     or pg_catalog.has_table_privilege('anon', 'public.scan_usage', 'REFERENCES')
     or pg_catalog.has_table_privilege('anon', 'public.scan_usage', 'TRIGGER') then
    raise exception 'scan_usage ACLs allow client quota forgery or anonymous reads';
  end if;

  if pg_catalog.has_table_privilege('authenticated', 'public.profiles', 'UPDATE') then
    raise exception 'authenticated can edit protected profile fields directly';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_trigger
    where tgrelid = 'public.garden_plants'::regclass
      and tgname = 'reject_stale_garden_update'
      and not tgisinternal
      and tgenabled <> 'D'
      and pg_catalog.pg_get_triggerdef(oid) like '%BEFORE INSERT OR UPDATE%'
  ) then
    raise exception 'garden stale/tombstone trigger is missing or disabled';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_trigger
    where tgrelid = 'public.garden_plants'::regclass
      and tgname = 'retain_garden_plant_schema'
      and not tgisinternal
      and tgenabled <> 'D'
      and pg_catalog.pg_get_triggerdef(oid) like '%BEFORE UPDATE%'
  ) then
    raise exception 'garden schema-downgrade trigger is missing or disabled';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_trigger
    where tgrelid = 'public.garden_plants'::regclass
      and tgname = 'scrub_garden_plant_profile'
      and not tgisinternal
      and tgenabled <> 'D'
      and pg_catalog.pg_get_triggerdef(oid) like '%BEFORE INSERT OR UPDATE%'
  ) then
    raise exception 'arbitrary-plant tombstone scrub trigger is missing or disabled';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_trigger
    where tgrelid = 'public.garden_plants'::regclass
      and tgname = 'validate_garden_plant_sync_time'
      and not tgisinternal
      and tgenabled <> 'D'
      and pg_catalog.pg_get_triggerdef(oid) like '%BEFORE INSERT OR UPDATE%'
  ) then
    raise exception 'garden sync-time validation trigger is missing or disabled';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_trigger
    where tgrelid = 'public.watering_events'::regclass
      and tgname = 'reject_watering_for_deleted_plant'
      and not tgisinternal
      and tgenabled <> 'D'
      and pg_catalog.pg_get_triggerdef(oid) like '%BEFORE INSERT%'
  ) then
    raise exception 'watering tombstone trigger is missing or disabled';
  end if;

  select n.nspname || '.' || p.proname
  into insecure_function
  from pg_catalog.pg_proc as p
  join pg_catalog.pg_namespace as n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.prosecdef
    and not coalesce(p.proconfig @> array['search_path=""']::text[], false)
  limit 1;

  if insecure_function is not null then
    raise exception 'security-definer function has unsafe search_path: %', insecure_function;
  end if;

  if not pg_catalog.has_function_privilege('authenticated', 'public.reset_my_garden(uuid)', 'EXECUTE')
     or pg_catalog.has_function_privilege('anon', 'public.reset_my_garden(uuid)', 'EXECUTE') then
    raise exception 'reset_my_garden execute ACL is unsafe';
  end if;

  if not pg_catalog.has_function_privilege('authenticated', 'public.consume_scan_quota()', 'EXECUTE')
     or pg_catalog.has_function_privilege('anon', 'public.consume_scan_quota()', 'EXECUTE') then
    raise exception 'consume_scan_quota execute ACL is unsafe';
  end if;

  if not pg_catalog.has_function_privilege(
       'authenticated',
       'public.begin_scan_request(uuid)',
       'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'anon',
       'public.begin_scan_request(uuid)',
       'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'authenticated',
       'public.complete_scan_request(uuid,uuid,jsonb,integer,text,numeric,integer)',
       'EXECUTE'
     )
     or not pg_catalog.has_function_privilege(
       'service_role',
       'public.complete_scan_request(uuid,uuid,jsonb,integer,text,numeric,integer)',
       'EXECUTE'
     ) then
    raise exception 'scan idempotency RPC execute ACLs are unsafe';
  end if;

  if pg_catalog.has_function_privilege('authenticated', 'public.reject_stale_garden_update()', 'EXECUTE')
     or pg_catalog.has_function_privilege('authenticated', 'public.reject_watering_for_deleted_plant()', 'EXECUTE')
     or pg_catalog.has_function_privilege('authenticated', 'public.retain_garden_plant_schema()', 'EXECUTE')
     or pg_catalog.has_function_privilege('authenticated', 'public.scrub_garden_plant_profile()', 'EXECUTE')
     or pg_catalog.has_function_privilege('authenticated', 'public.validate_garden_plant_sync_time()', 'EXECUTE') then
    raise exception 'authenticated can execute an internal trigger function';
  end if;

  if pg_catalog.has_table_privilege('authenticated', 'public.garden_reset_requests', 'SELECT')
     or pg_catalog.has_table_privilege('authenticated', 'public.garden_reset_requests', 'INSERT')
     or not (select relrowsecurity from pg_catalog.pg_class where oid = 'public.garden_reset_requests'::regclass) then
    raise exception 'garden reset deduplication ledger is exposed';
  end if;

  if pg_catalog.has_table_privilege('authenticated', 'public.scan_requests', 'SELECT')
     or pg_catalog.has_table_privilege('authenticated', 'public.scan_requests', 'INSERT')
     or pg_catalog.has_table_privilege('service_role', 'public.scan_requests', 'SELECT')
     or pg_catalog.has_table_privilege('service_role', 'public.scan_requests', 'UPDATE') then
    raise exception 'scan request replay ledger is directly exposed';
  end if;

  if not pg_catalog.has_table_privilege('authenticated', 'public.watering_events', 'SELECT')
     or not pg_catalog.has_table_privilege('authenticated', 'public.watering_events', 'INSERT')
     or pg_catalog.has_table_privilege('authenticated', 'public.watering_events', 'UPDATE')
     or pg_catalog.has_table_privilege('authenticated', 'public.watering_events', 'DELETE')
     or pg_catalog.has_table_privilege('authenticated', 'public.watering_events', 'TRUNCATE')
     or pg_catalog.has_table_privilege('authenticated', 'public.watering_events', 'REFERENCES')
     or pg_catalog.has_table_privilege('authenticated', 'public.watering_events', 'TRIGGER') then
    raise exception 'watering events ACL is not append-only';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_constraint
    where conrelid = 'public.watering_events'::regclass
      and contype = 'f'
      and pg_catalog.pg_get_constraintdef(oid) like
        'FOREIGN KEY (user_id, plant_id) REFERENCES garden_plants(user_id, id)%'
  ) then
    raise exception 'watering_events lost its same-user composite foreign key';
  end if;
end;
$catalog$;

-- Seed two accounts as the auth owner. handle_new_user() must still provision
-- their protected profiles after the full migration history is applied.
insert into auth.users (id, raw_user_meta_data)
values
  ('11111111-1111-1111-1111-111111111111', '{"locale":"en"}'::jsonb),
  ('22222222-2222-2222-2222-222222222222', '{"locale":"ES"}'::jsonb);

do $profiles$
begin
  if (select locale from public.profiles where id = '22222222-2222-2222-2222-222222222222') <> 'es' then
    raise exception 'handle_new_user no longer normalizes locale';
  end if;
end;
$profiles$;

set role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub',
  '11111111-1111-1111-1111-111111111111',
  false
);

-- The mobile role may observe its quota but cannot insert, lower, reset, or
-- transfer usage. Only the parameterless RPC can advance the authenticated
-- account's counter, and sequential calls advance it monotonically.
do $quota_forgery$
declare
  quota_row record;
  stored_used integer;
begin
  select * into quota_row from public.consume_scan_quota();
  if not found then
    raise exception 'first quota consumption returned no row';
  end if;
  if quota_row.allowed is distinct from true
     or quota_row.used is distinct from 1
     or quota_row.quota is distinct from 5
     or quota_row.remaining is distinct from 4 then
    raise exception 'first quota consumption returned unexpected values';
  end if;

  begin
    insert into public.scan_usage (user_id, period_start, used)
    values (
      auth.uid(),
      pg_catalog.date_trunc('month', pg_catalog.now())::date,
      0
    );
    raise exception 'authenticated client inserted a forged quota row';
  exception
    when insufficient_privilege then null;
  end;

  begin
    update public.scan_usage
    set used = 0
    where user_id = auth.uid();
    raise exception 'authenticated client reset its quota counter';
  exception
    when insufficient_privilege then null;
  end;

  select used into stored_used
  from public.scan_usage
  where user_id = auth.uid()
    and period_start = pg_catalog.date_trunc('month', pg_catalog.now())::date;
  if not found or stored_used is distinct from 1 then
    raise exception 'failed client forgery changed the quota counter';
  end if;

  select * into quota_row from public.consume_scan_quota();
  if not found then
    raise exception 'second quota consumption returned no row';
  end if;
  if quota_row.allowed is distinct from true
     or quota_row.used is distinct from 2
     or quota_row.quota is distinct from 5
     or quota_row.remaining is distinct from 3 then
    raise exception 'second quota consumption was not monotonic';
  end if;

  select used into stored_used
  from public.scan_usage
  where user_id = auth.uid()
    and period_start = pg_catalog.date_trunc('month', pg_catalog.now())::date;
  if not found or stored_used is distinct from 2 then
    raise exception 'second quota consumption did not persist the returned counter';
  end if;
end;
$quota_forgery$;

-- A duplicate request ID must observe the original provider custom_id without
-- consuming quota again. The two-minute grace flag enables recovery/abandonment
-- by GET/DELETE only; it never authorizes a second Plant.id POST.
do $idempotent_scan_claim$
declare
  first_claim record;
  duplicate_claim record;
  stored_used integer;
begin
  select * into strict first_claim
  from public.begin_scan_request('aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee');

  if first_claim.claim_status <> 'claimed'
     or first_claim.quota <> 5
     or first_claim.remaining <> 2
     or first_claim.provider_custom_id is null
     or first_claim.can_abandon is distinct from false then
    raise exception 'first scan claim returned unexpected values';
  end if;

  select * into strict duplicate_claim
  from public.begin_scan_request('aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee');

  if duplicate_claim.claim_status <> 'recover'
     or duplicate_claim.provider_custom_id <> first_claim.provider_custom_id
     or duplicate_claim.can_abandon is distinct from false then
    raise exception 'duplicate scan claim did not return the pending recovery identity';
  end if;

  select used into strict stored_used
  from public.scan_usage
  where user_id = auth.uid()
    and period_start = pg_catalog.date_trunc('month', pg_catalog.now())::date;
  if stored_used <> 3 then
    raise exception 'duplicate scan claim consumed quota twice';
  end if;

  perform pg_catalog.set_config(
    'rocio.test.provider_custom_id',
    first_claim.provider_custom_id::text,
    false
  );

  begin
    perform public.complete_scan_request(
      auth.uid(),
      'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee',
      '{"success":true}'::jsonb,
      200,
      'Rosa',
      0.9,
      1
    );
    raise exception 'authenticated client completed its own scan ledger row';
  exception
    when insufficient_privilege then null;
  end;
end;
$idempotent_scan_claim$;

reset role;
update public.scan_requests
set
  created_at = pg_catalog.now() - interval '3 minutes',
  expires_at = pg_catalog.now() + interval '6 days'
where user_id = '11111111-1111-1111-1111-111111111111'
  and request_id = 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee';

set role authenticated;
do $idempotent_scan_grace$
declare
  recovery_claim record;
begin
  select * into strict recovery_claim
  from public.begin_scan_request('aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee');
  if recovery_claim.claim_status <> 'recover'
     or recovery_claim.can_abandon is distinct from true
     or recovery_claim.provider_custom_id::text <>
       pg_catalog.current_setting('rocio.test.provider_custom_id') then
    raise exception 'old pending scan did not enter safe abandonment recovery';
  end if;
end;
$idempotent_scan_grace$;

reset role;
set role service_role;
do $idempotent_scan_complete$
declare
  completed boolean;
begin
  completed := public.complete_scan_request(
    '11111111-1111-1111-1111-111111111111',
    'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee',
    '{"success":true,"provider":"plant_id","suggestions":[],"quota":5,"remaining":2}'::jsonb,
    200,
    'Rosa',
    0.9,
    0
  );
  if completed is distinct from true then
    raise exception 'service role could not atomically complete the scan';
  end if;
end;
$idempotent_scan_complete$;

reset role;
set role authenticated;
do $idempotent_scan_replay$
declare
  replay record;
  audit_count integer;
begin
  select * into strict replay
  from public.begin_scan_request('aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee');
  if replay.claim_status <> 'replay'
     or replay.http_status <> 200
     or replay.response_payload <> '{"success":true,"provider":"plant_id","suggestions":[],"quota":5,"remaining":2}'::jsonb then
    raise exception 'completed scan did not replay its bounded response';
  end if;

  select count(*) into audit_count
  from public.scan_results
  where request_id = 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee';
  if audit_count <> 1 then
    raise exception 'scan completion did not create exactly one audit row';
  end if;
end;
$idempotent_scan_replay$;

-- Once the seven-day replay window expires, the same UUID is a fresh claim.
-- The prior audit row must remain visible as history without retaining the
-- unique replay key, so a second successful completion can write a new audit.
reset role;
update public.scan_requests
set
  created_at = pg_catalog.now() - interval '8 days',
  expires_at = pg_catalog.now() - interval '1 day'
where user_id = '11111111-1111-1111-1111-111111111111'
  and request_id = 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee';

set role authenticated;
do $expired_scan_reclaim$
declare
  reclaimed record;
  prior_provider_custom_id bigint :=
    pg_catalog.current_setting('rocio.test.provider_custom_id')::bigint;
begin
  select * into strict reclaimed
  from public.begin_scan_request('aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee');

  if reclaimed.claim_status <> 'claimed'
     or reclaimed.quota <> 5
     or reclaimed.remaining <> 1
     or reclaimed.provider_custom_id is null
     or reclaimed.provider_custom_id = prior_provider_custom_id then
    raise exception 'expired scan request was not reclaimed as a fresh quota-bound operation';
  end if;

  if (select count(*)
      from public.scan_results
      where user_id = auth.uid()
        and request_id is null
        and top_name = 'Rosa') <> 1
     or exists (
       select 1
       from public.scan_results
       where user_id = auth.uid()
         and request_id = 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee'
     ) then
    raise exception 'expiry did not preserve history while releasing the replay key';
  end if;
end;
$expired_scan_reclaim$;

reset role;
set role service_role;
do $reclaimed_scan_complete$
declare
  completed boolean;
begin
  completed := public.complete_scan_request(
    '11111111-1111-1111-1111-111111111111',
    'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee',
    '{"success":true,"provider":"plant_id","suggestions":[{"scientific_name":"Rosa chinensis"}],"quota":5,"remaining":1}'::jsonb,
    200,
    'Rosa chinensis',
    0.95,
    1
  );
  if completed is distinct from true then
    raise exception 'reclaimed scan request could not be completed';
  end if;
end;
$reclaimed_scan_complete$;

reset role;
set role authenticated;
do $reclaimed_scan_replay$
declare
  replay record;
begin
  select * into strict replay
  from public.begin_scan_request('aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee');

  if replay.claim_status <> 'replay'
     or replay.remaining <> 1
     or replay.response_payload <>
       '{"success":true,"provider":"plant_id","suggestions":[{"scientific_name":"Rosa chinensis"}],"quota":5,"remaining":1}'::jsonb
     or (select count(*)
         from public.scan_results
         where user_id = auth.uid()) <> 2
     or (select count(*)
         from public.scan_results
         where user_id = auth.uid()
           and request_id = 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee') <> 1 then
    raise exception 'recompleted scan did not preserve old history and replay the new result';
  end if;
end;
$reclaimed_scan_replay$;

-- Pruning an expired pending request is a hard ledger deletion. A delayed
-- provider completion for that removed claim must return false, not recreate
-- either the replay row or an audit result.
do $expiring_pending_scan$
declare
  pending_claim record;
begin
  select * into strict pending_claim
  from public.begin_scan_request('bbbbbbbb-cccc-4ddd-8eee-ffffffffffff');

  if pending_claim.claim_status <> 'claimed'
     or pending_claim.remaining <> 0 then
    raise exception 'pending scan fixture did not consume the final quota slot';
  end if;
end;
$expiring_pending_scan$;

reset role;
update public.scan_requests
set
  created_at = pg_catalog.now() - interval '8 days',
  expires_at = pg_catalog.now() - interval '1 day'
where user_id = '11111111-1111-1111-1111-111111111111'
  and request_id = 'bbbbbbbb-cccc-4ddd-8eee-ffffffffffff';

set role authenticated;
do $prune_expired_pending_scan$
declare
  denied_claim record;
begin
  select * into strict denied_claim
  from public.begin_scan_request('cccccccc-dddd-4eee-8fff-aaaaaaaaaaaa');

  if denied_claim.claim_status <> 'quota_exhausted'
     or denied_claim.quota <> 5
     or denied_claim.remaining <> 0
     or denied_claim.provider_custom_id is not null then
    raise exception 'post-prune quota exhaustion returned an unsafe claim';
  end if;
end;
$prune_expired_pending_scan$;

reset role;
do $expired_pending_hard_delete$
begin
  if exists (
    select 1
    from public.scan_requests
    where user_id = '11111111-1111-1111-1111-111111111111'
      and request_id in (
        'bbbbbbbb-cccc-4ddd-8eee-ffffffffffff',
        'cccccccc-dddd-4eee-8fff-aaaaaaaaaaaa'
      )
  ) then
    raise exception 'expired or quota-denied scan request was not physically deleted';
  end if;
end;
$expired_pending_hard_delete$;

set role service_role;
do $late_completion_after_prune$
declare
  completed boolean;
begin
  completed := public.complete_scan_request(
    '11111111-1111-1111-1111-111111111111',
    'bbbbbbbb-cccc-4ddd-8eee-ffffffffffff',
    '{"success":false,"error":"provider_unavailable","remaining":0}'::jsonb,
    502
  );
  if completed is distinct from false then
    raise exception 'completion recreated an expired pending scan request';
  end if;
end;
$late_completion_after_prune$;

reset role;
do $late_completion_left_no_rows$
begin
  if exists (
    select 1
    from public.scan_requests
    where user_id = '11111111-1111-1111-1111-111111111111'
      and request_id = 'bbbbbbbb-cccc-4ddd-8eee-ffffffffffff'
  ) or exists (
    select 1
    from public.scan_results
    where user_id = '11111111-1111-1111-1111-111111111111'
      and request_id = 'bbbbbbbb-cccc-4ddd-8eee-ffffffffffff'
  ) then
    raise exception 'late completion recreated a pruned scan row';
  end if;
end;
$late_completion_left_no_rows$;

set role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub',
  '22222222-2222-2222-2222-222222222222',
  false
);

do $quota_isolation$
begin
  if exists (
    select 1
    from public.scan_usage
    where user_id = '11111111-1111-1111-1111-111111111111'
  ) then
    raise exception 'scan_usage RLS exposed another account''s quota';
  end if;
end;
$quota_isolation$;

select pg_catalog.set_config(
  'request.jwt.claim.sub',
  '11111111-1111-1111-1111-111111111111',
  false
);

-- Arbitrary plants retain a non-null legacy sentinel for mixed-version
-- clients, while the versioned identity remains authoritative. Malformed JSON
-- and far-future active timestamps are rejected before they can poison
-- offline synchronization.
do $arbitrary_plant_validation$
begin
  begin
    insert into public.garden_plants (
      id, user_id, flower_id, nickname, added_at, last_watered_at, status, notes,
      updated_at, garden_epoch
    ) values (
      '10101010-1010-1010-1010-101010101010',
      auth.uid(),
      '__arbitrary__',
      'Missing identity',
      pg_catalog.clock_timestamp(),
      pg_catalog.clock_timestamp(),
      'healthy',
      '',
      pg_catalog.clock_timestamp(),
      (select garden_epoch from public.profiles where id = auth.uid())
    );
    raise exception 'live row without a bundled ID or identity unexpectedly succeeded';
  exception
    when check_violation then null;
  end;

  begin
    insert into public.garden_plants (
      id, user_id, flower_id, nickname, added_at, last_watered_at, status, notes,
      updated_at, garden_epoch, identity, care_profile
    ) values (
      '20202020-2020-2020-2020-202020202020',
      auth.uid(),
      '__arbitrary__',
      'Unknown identity field',
      pg_catalog.clock_timestamp(),
      pg_catalog.clock_timestamp(),
      'healthy',
      '',
      pg_catalog.clock_timestamp(),
      (select garden_epoch from public.profiles where id = auth.uid()),
      '{"source":"manual","common_name":"Aloe","unbounded_payload":"no"}'::jsonb,
      '{"source":"manual"}'::jsonb
    );
    raise exception 'identity with an unsupported field unexpectedly succeeded';
  exception
    when check_violation then null;
  end;

  begin
    insert into public.garden_plants (
      id, user_id, flower_id, nickname, added_at, last_watered_at, status, notes,
      updated_at, garden_epoch, identity, care_profile
    ) values (
      '30303030-3030-3030-3030-303030303030',
      auth.uid(),
      '__arbitrary__',
      'Impossible care',
      pg_catalog.clock_timestamp(),
      pg_catalog.clock_timestamp(),
      'healthy',
      '',
      pg_catalog.clock_timestamp(),
      (select garden_epoch from public.profiles where id = auth.uid()),
      '{"source":"manual","common_name":"Aloe"}'::jsonb,
      '{"source":"manual","water_amount_ml":10001}'::jsonb
    );
    raise exception 'out-of-range care profile unexpectedly succeeded';
  exception
    when check_violation then null;
  end;

  begin
    insert into public.garden_plants (
      id, user_id, flower_id, nickname, added_at, last_watered_at, status, notes,
      updated_at, garden_epoch, identity, care_profile
    ) values (
      '40404040-4040-4040-4040-404040404040',
      auth.uid(),
      '__arbitrary__',
      'Future clock plant',
      pg_catalog.clock_timestamp(),
      pg_catalog.clock_timestamp(),
      'healthy',
      '',
      pg_catalog.clock_timestamp() + interval '2 days',
      (select garden_epoch from public.profiles where id = auth.uid()),
      '{"source":"manual","common_name":"Aloe"}'::jsonb,
      '{"source":"manual"}'::jsonb
    );
    raise exception 'far-future active row unexpectedly succeeded';
  exception
    when check_violation then
      if sqlerrm <> 'garden_updated_at_too_far_in_future' then
        raise;
      end if;
  end;

  begin
    insert into public.garden_plants (
      id, user_id, flower_id, nickname, added_at, last_watered_at, status, notes,
      updated_at, garden_epoch, identity, care_profile
    ) values (
      '50505050-5050-5050-5050-505050505050',
      auth.uid(),
      '__arbitrary__',
      'Unknown care source',
      pg_catalog.clock_timestamp(),
      pg_catalog.clock_timestamp(),
      'healthy',
      '',
      pg_catalog.clock_timestamp(),
      (select garden_epoch from public.profiles where id = auth.uid()),
      '{"source":"manual","common_name":"Aloe"}'::jsonb,
      '{"source":"provider"}'::jsonb
    );
    raise exception 'unsupported care source unexpectedly succeeded';
  exception
    when check_violation then null;
  end;

  begin
    insert into public.garden_plants (
      id, user_id, flower_id, nickname, added_at, last_watered_at, status, notes,
      updated_at, garden_epoch, identity, care_profile
    ) values (
      '60606060-6060-6060-6060-606060606060',
      auth.uid(),
      '__arbitrary__',
      'Unknown light preference',
      pg_catalog.clock_timestamp(),
      pg_catalog.clock_timestamp(),
      'healthy',
      '',
      pg_catalog.clock_timestamp(),
      (select garden_epoch from public.profiles where id = auth.uid()),
      '{"source":"manual","common_name":"Aloe"}'::jsonb,
      '{"source":"manual","light_preference":"bright indirect"}'::jsonb
    );
    raise exception 'unsupported light preference unexpectedly succeeded';
  exception
    when check_violation then null;
  end;

  begin
    insert into public.garden_plants (
      id, user_id, flower_id, nickname, added_at, last_watered_at, status, notes,
      updated_at, garden_epoch, identity, care_profile
    ) values (
      '70707070-7070-7070-7070-707070707070',
      auth.uid(),
      '__arbitrary__',
      'Invalid fetched date',
      pg_catalog.clock_timestamp(),
      pg_catalog.clock_timestamp(),
      'healthy',
      '',
      pg_catalog.clock_timestamp(),
      (select garden_epoch from public.profiles where id = auth.uid()),
      '{"source":"manual","common_name":"Aloe"}'::jsonb,
      '{"source":"manual","fetched_at":"definitely-not-a-date"}'::jsonb
    );
    raise exception 'invalid fetched_at timestamp unexpectedly succeeded';
  exception
    when check_violation then null;
  end;

  begin
    insert into public.garden_plants (
      id, user_id, flower_id, nickname, added_at, last_watered_at, status, notes,
      updated_at, garden_epoch, identity, care_profile
    ) values (
      '71717171-7171-7171-7171-717171717171',
      auth.uid(),
      '__arbitrary__',
      'Postgres-only fetched date',
      pg_catalog.clock_timestamp(),
      pg_catalog.clock_timestamp(),
      'healthy',
      '',
      pg_catalog.clock_timestamp(),
      (select garden_epoch from public.profiles where id = auth.uid()),
      '{"source":"manual","common_name":"Aloe"}'::jsonb,
      '{"source":"manual","fetched_at":"2026-07-20 12:00:00 UTC"}'::jsonb
    );
    raise exception 'PostgreSQL-only fetched_at spelling unexpectedly succeeded';
  exception
    when check_violation then null;
  end;

  if rocio_private.is_swift_iso8601_timestamp('2026-02-30T12:00:00Z') then
    raise exception 'invalid leap-day fetched_at unexpectedly succeeded';
  end if;
  if rocio_private.is_swift_iso8601_timestamp('infinity') then
    raise exception 'infinity fetched_at unexpectedly succeeded';
  end if;
  if not rocio_private.is_swift_iso8601_timestamp(
    '2026-07-20T12:00:00.123456789+14:00'
  ) then
    raise exception 'valid RFC3339 fetched_at unexpectedly failed';
  end if;
end;
$arbitrary_plant_validation$;

insert into public.garden_plants (
  id, user_id, flower_id, nickname, added_at, last_watered_at, status, notes,
  updated_at, garden_epoch, identity, care_profile, schema_version
) values (
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
  '11111111-1111-1111-1111-111111111111',
  '__arbitrary__',
  'Fresh monstera',
  '2026-01-01 00:00:00+00',
  '2026-01-01 00:00:00+00',
  'healthy',
  'Keep this note',
  '2026-07-20 12:00:00+00',
  (select garden_epoch from public.profiles where id = auth.uid()),
  '{
    "source":"plant_id",
    "source_id":"a1b2c3d4",
    "common_name":"Swiss cheese plant",
    "scientific_name":"Monstera deliciosa",
    "rank":"species",
    "name_locale":"en"
  }'::jsonb,
  '{
    "source":"plant_id",
    "watering_preference":"medium",
    "light_preference":"partial",
    "fetched_at":"2026-07-20T12:00:00Z"
  }'::jsonb,
  1
);

insert into public.watering_events (user_id, plant_id, watered_at)
values (
  '11111111-1111-1111-1111-111111111111',
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
  '2026-07-20 11:00:00+00'
);

-- An out-of-order offline upsert must succeed as a no-op, not overwrite the
-- newer cloud row and not remain stuck in the client retry queue.
insert into public.garden_plants (
  id, user_id, flower_id, nickname, added_at, last_watered_at, status, notes, updated_at,
  garden_epoch
) values (
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
  '11111111-1111-1111-1111-111111111111',
  'rosa',
  'Stale rose',
  '2026-01-01 00:00:00+00',
  '2026-01-01 00:00:00+00',
  'needsWater',
  'Stale note',
  '2026-07-19 12:00:00+00',
  (select garden_epoch from public.profiles where id = auth.uid())
)
on conflict (id) do update
set nickname = excluded.nickname,
    status = excluded.status,
    notes = excluded.notes,
    updated_at = excluded.updated_at,
    garden_epoch = excluded.garden_epoch;

do $stale$
begin
  if not exists (
    select 1
    from public.garden_plants
    where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
      and nickname = 'Fresh monstera'
      and notes = 'Keep this note'
      and updated_at = '2026-07-20 12:00:00+00'::timestamptz
      and flower_id = '__arbitrary__'
      and identity ->> 'source_id' = 'a1b2c3d4'
      and identity ->> 'scientific_name' = 'Monstera deliciosa'
      and care_profile ->> 'watering_preference' = 'medium'
      and schema_version = 1
  ) then
    raise exception 'arbitrary plant was not preserved or stale upsert changed it';
  end if;
end;
$stale$;

-- A newer-schema client may update after this client fetched the row. A later
-- v2 write must then succeed as a no-op instead of dropping v3 data.
update public.garden_plants
set schema_version = 3,
    nickname = 'Future schema plant',
    notes = 'Future-only state',
    updated_at = '2026-07-20 13:00:00+00'
where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

insert into public.garden_plants (
  id, user_id, flower_id, nickname, added_at, last_watered_at, status, notes,
  updated_at, garden_epoch, identity, care_profile, schema_version
) values (
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
  '11111111-1111-1111-1111-111111111111',
  '__arbitrary__',
  'Downgraded client',
  '2026-01-01 00:00:00+00',
  '2026-01-01 00:00:00+00',
  'healthy',
  'Would drop future state',
  '2026-07-20 14:00:00+00',
  (select garden_epoch from public.profiles where id = auth.uid()),
  '{"source":"manual","common_name":"Downgraded plant"}'::jsonb,
  '{"source":"manual"}'::jsonb,
  2
)
on conflict (id) do update
set flower_id = excluded.flower_id,
    nickname = excluded.nickname,
    notes = excluded.notes,
    updated_at = excluded.updated_at,
    garden_epoch = excluded.garden_epoch,
    identity = excluded.identity,
    care_profile = excluded.care_profile,
    schema_version = excluded.schema_version;

do $schema_downgrade$
begin
  if not exists (
    select 1
    from public.garden_plants
    where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
      and schema_version = 3
      and nickname = 'Future schema plant'
      and notes = 'Future-only state'
      and updated_at = '2026-07-20 13:00:00+00'::timestamptz
      and identity ->> 'source_id' = 'a1b2c3d4'
  ) then
    raise exception 'older client downgraded an active future-schema row';
  end if;
end;
$schema_downgrade$;

-- Deletion must win even with a bad/old device clock. The trigger owns the
-- canonical timestamp and scrubs user-authored content from the tombstone.
update public.garden_plants
set deleted_at = '2000-01-01 00:00:00+00',
    updated_at = '2000-01-01 00:00:00+00'
where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

do $deleted$
begin
  if not exists (
    select 1
    from public.garden_plants
    where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
      and deleted_at is not null
      and updated_at >= '2026-07-20 12:00:00+00'::timestamptz
      and flower_id = 'deleted'
      and nickname = 'Deleted plant'
      and notes = ''
      and identity is null
      and care_profile is null
      and schema_version = 1
  ) then
    raise exception 'delete did not create a fully scrubbed, authoritative tombstone';
  end if;

  if exists (
    select 1 from public.watering_events
    where user_id = '11111111-1111-1111-1111-111111111111'
      and plant_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
  ) then
    raise exception 'plant deletion retained its watering history';
  end if;
end;
$deleted$;

-- Even a future-dated offline upsert cannot clear an existing tombstone.
insert into public.garden_plants (
  id, user_id, flower_id, nickname, added_at, last_watered_at, status, notes, updated_at, deleted_at
) values (
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
  '11111111-1111-1111-1111-111111111111',
  'rosa',
  'Resurrected rose',
  '2026-01-01 00:00:00+00',
  '2026-01-01 00:00:00+00',
  'healthy',
  'Should never land',
  '2099-01-01 00:00:00+00',
  null
)
on conflict (id) do update
set flower_id = excluded.flower_id,
    nickname = excluded.nickname,
    notes = excluded.notes,
    updated_at = excluded.updated_at,
    deleted_at = excluded.deleted_at;

do $resurrection$
begin
  if exists (
    select 1
    from public.garden_plants
    where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
      and (deleted_at is null or nickname = 'Resurrected rose')
  ) then
    raise exception 'a later upsert resurrected a tombstoned plant';
  end if;
end;
$resurrection$;

-- A tombstone keeps its FK identity, but no client may recreate care history
-- behind it after deletion.
do $watering_tombstone$
begin
  begin
    insert into public.watering_events (user_id, plant_id, watered_at)
    values (
      '11111111-1111-1111-1111-111111111111',
      'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
      '2026-07-20 13:00:00+00'
    );
    raise exception 'watering a tombstoned plant unexpectedly succeeded';
  exception
    when check_violation then null;
  end;
end;
$watering_tombstone$;

-- A different account cannot observe or mutate the tombstone.
select pg_catalog.set_config(
  'request.jwt.claim.sub',
  '22222222-2222-2222-2222-222222222222',
  false
);

do $cross_user$
declare
  affected integer;
begin
  if exists (
    select 1 from public.garden_plants
    where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
  ) then
    raise exception 'RLS exposed another account''s tombstone';
  end if;

  update public.garden_plants
  set nickname = 'Cross-user mutation'
  where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  get diagnostics affected = row_count;
  if affected <> 0 then
    raise exception 'RLS allowed another account to mutate a tombstone';
  end if;

  begin
    insert into public.garden_plants (
      id, user_id, flower_id, nickname, added_at, last_watered_at, status, notes, updated_at
    ) values (
      'dddddddd-dddd-dddd-dddd-dddddddddddd',
      '11111111-1111-1111-1111-111111111111',
      'rosa',
      'Wrong owner',
      '2026-01-01 00:00:00+00',
      '2026-01-01 00:00:00+00',
      'healthy',
      '',
      '2026-07-20 12:00:00+00'
    );
    raise exception 'cross-user insert unexpectedly succeeded';
  exception
    when insufficient_privilege then null;
  end;
end;
$cross_user$;

select pg_catalog.set_config(
  'request.jwt.claim.sub',
  '11111111-1111-1111-1111-111111111111',
  false
);

-- Reset tombstones current rows and rotates a server epoch. Preserve the old
-- epoch so a future-dated offline row can prove that device clocks are not the
-- reset boundary.
insert into public.garden_plants (
  id, user_id, flower_id, nickname, added_at, last_watered_at, status, notes, updated_at,
  garden_epoch
) values (
  'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
  '11111111-1111-1111-1111-111111111111',
  'orquidea',
  'Office orchid',
  '2026-01-02 00:00:00+00',
  '2026-01-02 00:00:00+00',
  'healthy',
  '',
  '2026-01-02 00:00:00+00',
  (select garden_epoch from public.profiles where id = auth.uid())
);

insert into public.watering_events (user_id, plant_id, watered_at)
values (
  '11111111-1111-1111-1111-111111111111',
  'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
  '2026-01-02 01:00:00+00'
);

select pg_catalog.set_config(
  'rocio.test.pre_reset_epoch',
  (select garden_epoch::text from public.profiles where id = auth.uid()),
  false
);

select pg_catalog.set_config(
  'rocio.test.first_reset_epoch',
  public.reset_my_garden('99999999-9999-9999-9999-999999999999')::text,
  false
);

-- A plant created after the reset must survive a lost-response retry of the
-- exact same request_id.
insert into public.garden_plants (
  id, user_id, flower_id, nickname, added_at, last_watered_at, status, notes, updated_at,
  garden_epoch
) values (
  'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee',
  '11111111-1111-1111-1111-111111111111',
  'rosa',
  'Post-reset rose',
  '2026-07-21 00:00:00+00',
  '2026-07-21 00:00:00+00',
  'healthy',
  '',
  '2026-07-21 00:00:00+00',
  (select garden_epoch from public.profiles where id = auth.uid())
);

do $idempotent_reset$
declare
  retry_epoch uuid;
begin
  retry_epoch := public.reset_my_garden('99999999-9999-9999-9999-999999999999');

  if retry_epoch::text <> current_setting('rocio.test.first_reset_epoch') then
    raise exception 'retrying reset returned a different epoch';
  end if;

  if not exists (
    select 1 from public.garden_plants
    where id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee'
      and deleted_at is null
      and nickname = 'Post-reset rose'
  ) then
    raise exception 'retrying reset deleted a plant created after the first attempt';
  end if;

end;
$idempotent_reset$;

insert into public.garden_plants (
  id, user_id, flower_id, nickname, added_at, last_watered_at, status, notes, updated_at,
  garden_epoch
) values (
  'cccccccc-cccc-cccc-cccc-cccccccccccc',
  '11111111-1111-1111-1111-111111111111',
  'lavanda',
  'Offline lavender',
  '2099-01-03 00:00:00+00',
  '2099-01-03 00:00:00+00',
  'healthy',
  '',
  '2099-01-03 00:00:00+00',
  current_setting('rocio.test.pre_reset_epoch')::uuid
);

-- The INSERT trigger scrubs a stale proposal before conflict resolution. The
-- UPDATE trigger must still recognize its old epoch and preserve the newer
-- active row with the same UUID.
insert into public.garden_plants (
  id, user_id, flower_id, nickname, added_at, last_watered_at, status, notes, updated_at,
  garden_epoch
) values (
  'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee',
  '11111111-1111-1111-1111-111111111111',
  'rosa',
  'Stale conflicting rose',
  '2099-01-04 00:00:00+00',
  '2099-01-04 00:00:00+00',
  'sick',
  'Must not replace the new epoch row',
  '2099-01-04 00:00:00+00',
  current_setting('rocio.test.pre_reset_epoch')::uuid
)
on conflict (id) do update
set flower_id = excluded.flower_id,
    nickname = excluded.nickname,
    added_at = excluded.added_at,
    last_watered_at = excluded.last_watered_at,
    status = excluded.status,
    notes = excluded.notes,
    updated_at = excluded.updated_at,
    garden_epoch = excluded.garden_epoch,
    deleted_at = excluded.deleted_at;

do $reset$
begin
  if not exists (
    select 1 from public.garden_plants
    where id = 'cccccccc-cccc-cccc-cccc-cccccccccccc'
      and deleted_at is not null
      and flower_id = 'deleted'
      and nickname = 'Deleted plant'
      and notes = ''
  ) then
    raise exception 'reset epoch did not convert a future-dated stale insert into a scrubbed tombstone';
  end if;

  if not exists (
    select 1 from public.garden_plants
    where id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
      and deleted_at is not null
      and flower_id = 'deleted'
      and nickname = 'Deleted plant'
      and notes = ''
  ) then
    raise exception 'reset did not create a scrubbed tombstone';
  end if;

  if exists (
    select 1 from public.watering_events
    where user_id = '11111111-1111-1111-1111-111111111111'
  ) then
    raise exception 'garden reset retained watering history';
  end if;

  -- A was deleted individually, B by reset, and C was converted on insert.
  if (select count(*) from public.garden_plants
      where user_id = '11111111-1111-1111-1111-111111111111'
        and deleted_at is not null) <> 3 then
    raise exception 'expected individual-delete, reset, and stale-insert tombstones';
  end if;

  if (select count(*) from public.garden_plants
      where user_id = '11111111-1111-1111-1111-111111111111'
        and deleted_at is null) <> 1 then
    raise exception 'expected the post-reset plant to remain active';
  end if;

  if not exists (
    select 1 from public.garden_plants
    where id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee'
      and deleted_at is null
      and nickname = 'Post-reset rose'
      and notes = ''
  ) then
    raise exception 'stale upsert tombstoned or replaced a newer active UUID';
  end if;
end;
$reset$;

-- Permanent account deletion remains the hard-purge path.
select public.delete_my_account();
reset role;

do $account_purge$
begin
  if exists (
    select 1 from auth.users
    where id = '11111111-1111-1111-1111-111111111111'
  ) or exists (
    select 1 from public.profiles
    where id = '11111111-1111-1111-1111-111111111111'
  ) or exists (
    select 1 from public.garden_plants
    where user_id = '11111111-1111-1111-1111-111111111111'
  ) or exists (
    select 1 from public.garden_reset_requests
    where user_id = '11111111-1111-1111-1111-111111111111'
  ) or exists (
    select 1 from public.scan_requests
    where user_id = '11111111-1111-1111-1111-111111111111'
  ) or exists (
    select 1 from public.scan_results
    where user_id = '11111111-1111-1111-1111-111111111111'
  ) or exists (
    select 1 from public.scan_usage
    where user_id = '11111111-1111-1111-1111-111111111111'
  ) then
    raise exception 'delete_my_account did not physically purge garden and scan history';
  end if;
end;
$account_purge$;

set role service_role;
do $completion_after_account_purge$
declare
  completed boolean;
begin
  completed := public.complete_scan_request(
    '11111111-1111-1111-1111-111111111111',
    'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee',
    '{"success":false,"error":"account_deleted","remaining":0}'::jsonb,
    503
  );
  if completed is distinct from false then
    raise exception 'completion recreated scan data after account deletion';
  end if;
end;
$completion_after_account_purge$;
reset role;

rollback;

\echo 'PostgreSQL migration history: catalog, RLS, ACL, quota, tombstone, reset, and account purge checks passed.'
