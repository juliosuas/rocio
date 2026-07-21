\set ON_ERROR_STOP on

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

  if pg_catalog.has_function_privilege('authenticated', 'public.reject_stale_garden_update()', 'EXECUTE')
     or pg_catalog.has_function_privilege('authenticated', 'public.reject_watering_for_deleted_plant()', 'EXECUTE') then
    raise exception 'authenticated can execute an internal trigger function';
  end if;

  if pg_catalog.has_table_privilege('authenticated', 'public.garden_reset_requests', 'SELECT')
     or pg_catalog.has_table_privilege('authenticated', 'public.garden_reset_requests', 'INSERT')
     or not (select relrowsecurity from pg_catalog.pg_class where oid = 'public.garden_reset_requests'::regclass) then
    raise exception 'garden reset deduplication ledger is exposed';
  end if;

  if pg_catalog.has_table_privilege('authenticated', 'public.watering_events', 'UPDATE') then
    raise exception 'watering events are not append-only';
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

insert into public.garden_plants (
  id, user_id, flower_id, nickname, added_at, last_watered_at, status, notes, updated_at,
  garden_epoch
) values (
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
  '11111111-1111-1111-1111-111111111111',
  'rosa',
  'Fresh rose',
  '2026-01-01 00:00:00+00',
  '2026-01-01 00:00:00+00',
  'healthy',
  'Keep this note',
  '2026-07-20 12:00:00+00',
  (select garden_epoch from public.profiles where id = auth.uid())
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
      and nickname = 'Fresh rose'
      and notes = 'Keep this note'
      and updated_at = '2026-07-20 12:00:00+00'::timestamptz
  ) then
    raise exception 'stale upsert changed the newer live row';
  end if;
end;
$stale$;

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
  ) then
    raise exception 'delete did not create a scrubbed, authoritative tombstone';
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
  ) then
    raise exception 'delete_my_account did not physically purge tombstones and reset requests';
  end if;
end;
$account_purge$;

rollback;

\echo 'PostgreSQL migration history: catalog, RLS, ACL, tombstone, reset, and account purge checks passed.'
