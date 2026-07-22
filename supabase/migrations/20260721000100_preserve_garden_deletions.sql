-- Preserve garden deletions across offline devices.
--
-- Rows are soft-deleted and scrubbed instead of being physically removed. A
-- per-account server epoch also rejects an insert that was created before a
-- reset but had never reached the cloud, without trusting a device clock.
-- Account deletion still cascades and physically removes every row through
-- delete_my_account().

alter table public.profiles
  add column if not exists garden_reset_at timestamptz,
  add column if not exists garden_epoch uuid not null default gen_random_uuid();

alter table public.garden_plants
  add column if not exists deleted_at timestamptz,
  add column if not exists garden_epoch uuid;

-- Existing cloud rows belong to the epoch assigned to their owner's profile.
-- New inserts that omit the epoch receive an unmatched UUID and are safely
-- tombstoned by the trigger, which makes older clients fail closed.
update public.garden_plants as plants
set garden_epoch = profiles.garden_epoch
from public.profiles as profiles
where profiles.id = plants.user_id
  and plants.garden_epoch is null;

alter table public.garden_plants
  alter column garden_epoch set default gen_random_uuid(),
  alter column garden_epoch set not null;

create index if not exists garden_plants_user_deleted_updated_idx
  on public.garden_plants(user_id, deleted_at, updated_at desc);

-- A reset request may be retried after the server commits but before the
-- client receives the response. Remember each request so retrying it returns
-- the same epoch instead of clearing plants created after the first attempt.
create table if not exists public.garden_reset_requests (
  user_id uuid not null references auth.users(id) on delete cascade,
  request_id uuid not null,
  garden_epoch uuid not null,
  created_at timestamptz not null default now(),
  primary key (user_id, request_id)
);

alter table public.garden_reset_requests enable row level security;

create or replace function public.reject_stale_garden_update()
returns trigger
language plpgsql
security definer set search_path = ''
as $$
declare
  current_uid uuid := auth.uid();
  reset_at timestamptz;
  current_epoch uuid;
  tombstone_at timestamptz;
begin
  if current_uid is null
     or current_uid <> new.user_id
     or (tg_op = 'UPDATE' and old.user_id <> new.user_id) then
    raise insufficient_privilege using message = 'garden_owner_mismatch';
  end if;

  if tg_op = 'INSERT' then
    -- INSERT takes the profile lock before it can acquire a conflicting plant
    -- row, matching reset's profile-then-plant lock order. UPDATE already owns
    -- the plant row and therefore reads the epoch without taking this lock.
    select profiles.garden_reset_at, profiles.garden_epoch
    into reset_at, current_epoch
    from public.profiles as profiles
    where profiles.id = new.user_id
    for share;

    if current_epoch is null then
      raise exception 'garden_profile_missing';
    end if;

    if new.garden_epoch is distinct from current_epoch then
      -- Persist a scrubbed tombstone instead of silently skipping the row. The
      -- client's authoritative fetch can then remove its stale offline copy in
      -- the same synchronization cycle.
      new.deleted_at := coalesce(reset_at, pg_catalog.clock_timestamp());
    end if;

    if new.deleted_at is not null then
      tombstone_at := pg_catalog.clock_timestamp();
      new.flower_id := 'deleted';
      new.nickname := 'Deleted plant';
      new.added_at := tombstone_at;
      new.last_watered_at := tombstone_at;
      new.status := 'healthy';
      new.notes := '';
      new.deleted_at := tombstone_at;
      new.updated_at := tombstone_at;
    end if;

    return new;
  end if;

  -- A stale or malicious upsert must be a successful no-op once this UUID is
  -- tombstoned. Also heal any legacy care history that was written after the
  -- tombstone before returning OLD so repeated deletes remain privacy-safe.
  if old.deleted_at is not null then
    delete from public.watering_events
    where watering_events.user_id = old.user_id
      and watering_events.plant_id = old.id;
    return old;
  end if;

  select profiles.garden_epoch
  into current_epoch
  from public.profiles as profiles
  where profiles.id = new.user_id;

  if current_epoch is null then
    raise exception 'garden_profile_missing';
  end if;

  -- Check the incoming epoch before treating deleted_at as an intentional
  -- delete. A stale INSERT ... ON CONFLICT is scrubbed by the INSERT trigger;
  -- this ordering keeps that excluded row from tombstoning a newer active row.
  if new.garden_epoch is distinct from current_epoch then
    return old;
  end if;

  -- Deletion wins even when the client clock is behind a later active update.
  if new.deleted_at is not null then
    -- The tombstone prevents resurrection, but per-plant care history is no
    -- longer user-visible and must not survive a delete/reset operation.
    delete from public.watering_events
    where watering_events.user_id = old.user_id
      and watering_events.plant_id = old.id;

    tombstone_at := pg_catalog.clock_timestamp();
    new.flower_id := 'deleted';
    new.nickname := 'Deleted plant';
    new.added_at := tombstone_at;
    new.last_watered_at := tombstone_at;
    new.status := 'healthy';
    new.notes := '';
    new.deleted_at := tombstone_at;
    new.updated_at := greatest(old.updated_at, tombstone_at);
    new.garden_epoch := current_epoch;
    return new;
  end if;

  if new.updated_at < old.updated_at then
    return old;
  end if;

  return new;
end;
$$;

drop trigger if exists reject_stale_garden_update on public.garden_plants;
create trigger reject_stale_garden_update
  before insert or update on public.garden_plants
  for each row execute procedure public.reject_stale_garden_update();

create or replace function public.reject_watering_for_deleted_plant()
returns trigger
language plpgsql
security definer set search_path = ''
as $$
declare
  current_uid uuid := auth.uid();
begin
  if current_uid is null or current_uid <> new.user_id then
    raise insufficient_privilege using message = 'watering_owner_mismatch';
  end if;

  -- The row lock serializes this insert with a concurrent plant delete
  -- or reset. Those operations purge history again after obtaining their
  -- exclusive row lock, so no event can survive behind a tombstone.
  perform 1
  from public.garden_plants as plants
  where plants.user_id = new.user_id
    and plants.id = new.plant_id
    and plants.deleted_at is null
  for share;

  if not found then
    raise check_violation using message = 'watering_requires_active_plant';
  end if;

  return new;
end;
$$;

drop trigger if exists reject_watering_for_deleted_plant on public.watering_events;
create trigger reject_watering_for_deleted_plant
  before insert on public.watering_events
  for each row execute procedure public.reject_watering_for_deleted_plant();

create or replace function public.reset_my_garden(request_id uuid)
returns uuid
language plpgsql
security definer set search_path = ''
as $$
declare
  current_uid uuid := auth.uid();
  reset_at timestamptz := pg_catalog.clock_timestamp();
  next_epoch uuid := gen_random_uuid();
begin
  if current_uid is null then
    raise exception 'authentication_required';
  end if;
  if request_id is null then
    raise exception 'reset_request_id_required';
  end if;

  -- Lock first, then check the deduplication ledger. Concurrent calls with the
  -- same request_id serialize here and return the first call's epoch.
  perform 1
  from public.profiles as profiles
  where profiles.id = current_uid
  for update;

  if not found then
    raise exception 'garden_profile_missing';
  end if;

  select requests.garden_epoch
  into next_epoch
  from public.garden_reset_requests as requests
  where requests.user_id = current_uid
    and requests.request_id = reset_my_garden.request_id;

  if found then
    return next_epoch;
  end if;

  next_epoch := gen_random_uuid();

  update public.profiles
  set garden_reset_at = reset_at,
      garden_epoch = next_epoch,
      updated_at = greatest(profiles.updated_at, reset_at)
  where id = current_uid;

  -- Tombstone first. The watering trigger uses FOR SHARE on each active plant,
  -- and the final purge runs after every plant lock has been acquired.
  update public.garden_plants
  set deleted_at = reset_at,
      updated_at = reset_at,
      garden_epoch = next_epoch
  where user_id = current_uid
    and deleted_at is null;

  delete from public.watering_events
  where watering_events.user_id = current_uid;

  insert into public.garden_reset_requests (user_id, request_id, garden_epoch)
  values (current_uid, request_id, next_epoch);

  return next_epoch;
end;
$$;

-- Physical DELETE would remove the only evidence that blocks resurrection.
-- Permanent account deletion remains available through delete_my_account().
revoke delete on table public.garden_plants from authenticated;
-- Watering events are append-only. Preventing UPDATE also keeps every writer
-- on the plant-then-event lock order used by deletion/reset.
revoke update on table public.watering_events from authenticated;
revoke all on table public.garden_reset_requests from public, anon, authenticated;

revoke all on function public.reject_stale_garden_update() from public, anon, authenticated;
revoke all on function public.reject_watering_for_deleted_plant() from public, anon, authenticated;
revoke all on function public.reset_my_garden(uuid) from public, anon, authenticated;
grant execute on function public.reset_my_garden(uuid) to authenticated;
