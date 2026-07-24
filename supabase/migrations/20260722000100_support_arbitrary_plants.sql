-- Store arbitrary plants without forcing them into the bundled flower catalog.
--
-- Existing rows remain valid with their legacy flower_id and null JSON
-- profiles. New clients keep flower_id non-null for mixed-version decoders,
-- using __arbitrary__ while a versioned identity and care profile carry the
-- authoritative data. The JSON is intentionally small, typed, and limited to
-- fields the native client understands so garden synchronization cannot become
-- an unbounded document store.

create schema if not exists rocio_private;
revoke all on schema rocio_private from public;
grant usage on schema rocio_private to authenticated, service_role;

create or replace function rocio_private.is_swift_iso8601_timestamp(value text)
returns boolean
language plpgsql
immutable
strict
set search_path = ''
as $function$
begin
  if value !~
    '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]{1,9})?(Z|[+-]((0[0-9]|1[0-3]):[0-5][0-9]|14:00))$'
  then
    return false;
  end if;

  perform value::pg_catalog.timestamptz;
  return true;
exception
  when invalid_datetime_format or datetime_field_overflow then
    return false;
end;
$function$;

revoke all on function rocio_private.is_swift_iso8601_timestamp(text)
  from public;
grant execute on function rocio_private.is_swift_iso8601_timestamp(text)
  to authenticated, service_role;

alter table public.garden_plants
  add column if not exists identity jsonb,
  add column if not exists care_profile jsonb,
  add column if not exists schema_version smallint not null default 1;

alter table public.garden_plants
  add constraint garden_plants_schema_version_range
    check (schema_version between 1 and 100),
  add constraint garden_plants_live_identity_present
    check (
      deleted_at is not null
      or flower_id <> '__arbitrary__'
      or identity is not null
    ) not valid,
  add constraint garden_plants_identity_shape
    check (
      identity is null
      or (
        jsonb_typeof(identity) = 'object'
        and octet_length(identity::text) <= 4096
        and identity ? 'source'
        and jsonb_typeof(identity -> 'source') = 'string'
        and identity ->> 'source' in ('bundled', 'plant_id', 'manual')
        and identity ? 'common_name'
        and jsonb_typeof(identity -> 'common_name') = 'string'
        and char_length(btrim(identity ->> 'common_name')) between 1 and 200
        and (
          not identity ? 'source_id'
          or (
            jsonb_typeof(identity -> 'source_id') = 'string'
            and char_length(btrim(identity ->> 'source_id')) between 1 and 200
          )
        )
        and (
          not identity ? 'scientific_name'
          or (
            jsonb_typeof(identity -> 'scientific_name') = 'string'
            and char_length(btrim(identity ->> 'scientific_name')) between 1 and 200
          )
        )
        and (
          not identity ? 'rank'
          or (
            jsonb_typeof(identity -> 'rank') = 'string'
            and char_length(btrim(identity ->> 'rank')) between 1 and 80
          )
        )
        and (
          not identity ? 'name_locale'
          or (
            jsonb_typeof(identity -> 'name_locale') = 'string'
            and char_length(btrim(identity ->> 'name_locale')) between 2 and 32
          )
        )
        and (
          identity - array[
            'source',
            'source_id',
            'common_name',
            'scientific_name',
            'rank',
            'name_locale'
          ]::text[]
        ) = '{}'::jsonb
      )
    ) not valid,
  add constraint garden_plants_care_profile_shape
    check (
      care_profile is null
      or (
        jsonb_typeof(care_profile) = 'object'
        and octet_length(care_profile::text) <= 4096
        and care_profile ? 'source'
        and jsonb_typeof(care_profile -> 'source') = 'string'
        and care_profile ->> 'source' in ('bundled', 'plant_id', 'manual')
        and (
          case
            when not care_profile ? 'watering_interval_days' then true
            when jsonb_typeof(care_profile -> 'watering_interval_days') <> 'number' then false
            when (care_profile -> 'watering_interval_days')::text !~ '^[0-9]{1,3}$' then false
            else (care_profile ->> 'watering_interval_days')::integer between 1 and 365
          end
        )
        and (
          case
            when not care_profile ? 'water_amount_ml' then true
            when jsonb_typeof(care_profile -> 'water_amount_ml') <> 'number' then false
            when (care_profile -> 'water_amount_ml')::text !~ '^[0-9]{1,5}$' then false
            else (care_profile ->> 'water_amount_ml')::integer between 1 and 10000
          end
        )
        and (
          not care_profile ? 'watering_preference'
          or (
            jsonb_typeof(care_profile -> 'watering_preference') = 'string'
            and care_profile ->> 'watering_preference' in ('dry', 'medium', 'wet')
          )
        )
        and (
          not care_profile ? 'light_preference'
          or (
            jsonb_typeof(care_profile -> 'light_preference') = 'string'
            and care_profile ->> 'light_preference' in ('fullSun', 'partial', 'shade')
          )
        )
        and (
          not care_profile ? 'fetched_at'
          or (
            jsonb_typeof(care_profile -> 'fetched_at') = 'string'
            and char_length(btrim(care_profile ->> 'fetched_at')) between 10 and 40
            and rocio_private.is_swift_iso8601_timestamp(
              btrim(care_profile ->> 'fetched_at')
            )
          )
        )
        and (
          care_profile - array[
            'source',
            'watering_interval_days',
            'water_amount_ml',
            'watering_preference',
            'light_preference',
            'fetched_at'
          ]::text[]
        ) = '{}'::jsonb
      )
    ) not valid;

-- A client that understands an older active-row schema must never overwrite a
-- newer row after a fetch/write race. PostgreSQL orders same-event triggers by
-- name, so reject_stale_garden_update first validates ownership, epoch, delete,
-- and timestamp rules; this trigger then turns an active schema downgrade into
-- a successful no-op. Tombstones remain allowed and are scrubbed below.
create or replace function public.retain_garden_plant_schema()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.deleted_at is null
     and new.deleted_at is null
     and new.schema_version < old.schema_version then
    return old;
  end if;
  return new;
end;
$$;

drop trigger if exists retain_garden_plant_schema on public.garden_plants;
create trigger retain_garden_plant_schema
  before update on public.garden_plants
  for each row execute procedure public.retain_garden_plant_schema();

-- This trigger runs after both reject_stale_garden_update and
-- retain_garden_plant_schema. It removes all arbitrary-plant content from
-- tombstones before constraints and storage.
create or replace function public.scrub_garden_plant_profile()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.deleted_at is not null then
    new.identity := null;
    new.care_profile := null;
    new.schema_version := 1;
  end if;
  return new;
end;
$$;

drop trigger if exists scrub_garden_plant_profile on public.garden_plants;
create trigger scrub_garden_plant_profile
  before insert or update on public.garden_plants
  for each row execute procedure public.scrub_garden_plant_profile();

-- A staged rollout may already have profile columns on old tombstones. The
-- existing ownership trigger requires an authenticated JWT for every UPDATE,
-- while migrations run without a request JWT. Disable only that trigger for
-- this one backfill. PostgreSQL DDL is transactional, so any failure rolls the
-- trigger state back together with the migration.
alter table public.garden_plants
  disable trigger reject_stale_garden_update;

update public.garden_plants
set identity = null,
    care_profile = null,
    schema_version = 1
where deleted_at is not null;

alter table public.garden_plants
  enable trigger reject_stale_garden_update;

alter table public.garden_plants
  validate constraint garden_plants_live_identity_present,
  validate constraint garden_plants_identity_shape,
  validate constraint garden_plants_care_profile_shape;

-- Active rows use client timestamps for last-write-wins synchronization. Cap
-- clock skew so a compromised or badly configured device cannot make a row
-- effectively immutable with a far-future updated_at. Tombstones are exempt
-- because reject_stale_garden_update has already replaced their timestamp with
-- a canonical server value.
create or replace function public.validate_garden_plant_sync_time()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.deleted_at is null
     and new.updated_at > pg_catalog.clock_timestamp() + interval '24 hours' then
    raise check_violation using message = 'garden_updated_at_too_far_in_future';
  end if;
  return new;
end;
$$;

drop trigger if exists validate_garden_plant_sync_time on public.garden_plants;
create trigger validate_garden_plant_sync_time
  before insert or update on public.garden_plants
  for each row execute procedure public.validate_garden_plant_sync_time();

revoke all on function public.retain_garden_plant_schema() from public, anon, authenticated;
revoke all on function public.scrub_garden_plant_profile() from public, anon, authenticated;
revoke all on function public.validate_garden_plant_sync_time() from public, anon, authenticated;
