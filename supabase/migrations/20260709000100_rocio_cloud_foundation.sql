-- Rocio cloud foundation: account-owned garden data, scan quotas and minimal analytics.
-- Scanner images are intentionally never persisted.

create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  locale text not null default 'en' check (locale in ('en', 'es')),
  analytics_enabled boolean not null default true,
  plan text not null default 'free' check (plan in ('free', 'pro')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.garden_plants (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  flower_id text not null
    constraint garden_plants_flower_id_length check (char_length(btrim(flower_id)) between 1 and 80),
  nickname text not null
    constraint garden_plants_nickname_length check (char_length(btrim(nickname)) between 1 and 80),
  added_at timestamptz not null,
  last_watered_at timestamptz not null,
  status text not null check (status in ('healthy', 'needsWater', 'needsSun', 'sick')),
  notes text not null default ''
    constraint garden_plants_notes_length check (char_length(notes) <= 2000),
  updated_at timestamptz not null default now(),
  constraint garden_plants_owner_id_unique unique (user_id, id)
);

create index if not exists garden_plants_user_updated_idx
  on public.garden_plants(user_id, updated_at desc);

create or replace function public.reject_stale_garden_update()
returns trigger
language plpgsql
as $$
begin
  if new.updated_at < old.updated_at then
    return old;
  end if;
  return new;
end;
$$;

drop trigger if exists reject_stale_garden_update on public.garden_plants;
create trigger reject_stale_garden_update
  before update on public.garden_plants
  for each row execute procedure public.reject_stale_garden_update();

create table if not exists public.watering_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  plant_id uuid not null,
  watered_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  constraint watering_events_same_user_plant_fk
    foreign key (user_id, plant_id)
    references public.garden_plants(user_id, id)
    on delete cascade
);

create index if not exists watering_events_user_created_idx
  on public.watering_events(user_id, created_at desc);

create table if not exists public.scan_usage (
  user_id uuid not null references auth.users(id) on delete cascade,
  period_start date not null,
  used integer not null default 0 check (used between 0 and 50),
  updated_at timestamptz not null default now(),
  primary key (user_id, period_start)
);

create table if not exists public.scan_results (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  provider text not null
    constraint scan_results_provider_length check (char_length(btrim(provider)) between 1 and 40),
  top_name text
    constraint scan_results_top_name_length check (top_name is null or char_length(top_name) between 1 and 200),
  confidence numeric(6, 5)
    constraint scan_results_confidence_range check (confidence is null or confidence between 0 and 1),
  candidate_count integer not null default 0
    constraint scan_results_candidate_count_range check (candidate_count between 0 and 8),
  created_at timestamptz not null default now()
);

create index if not exists scan_results_user_created_idx
  on public.scan_results(user_id, created_at desc);

create table if not exists public.analytics_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null check (char_length(btrim(name)) between 1 and 80),
  properties jsonb not null default '{}'::jsonb
    constraint analytics_events_properties_object check (jsonb_typeof(properties) = 'object')
    constraint analytics_events_properties_size check (octet_length(properties::text) <= 16384),
  created_at timestamptz not null default now()
);

create index if not exists analytics_events_user_created_idx
  on public.analytics_events(user_id, created_at desc);

alter table public.profiles enable row level security;
alter table public.garden_plants enable row level security;
alter table public.watering_events enable row level security;
alter table public.scan_usage enable row level security;
alter table public.scan_results enable row level security;
alter table public.analytics_events enable row level security;

create policy "profiles_select_own" on public.profiles
  for select using (auth.uid() = id);
create policy "garden_plants_own" on public.garden_plants
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "watering_events_own" on public.watering_events
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "scan_usage_select_own" on public.scan_usage
  for select using (auth.uid() = user_id);
create policy "scan_results_select_own" on public.scan_results
  for select using (auth.uid() = user_id);
create policy "analytics_events_insert_own" on public.analytics_events
  for insert with check (
    auth.uid() = user_id
    and coalesce((select analytics_enabled from public.profiles where id = auth.uid()), true)
  );
create policy "analytics_events_select_own" on public.analytics_events
  for select using (auth.uid() = user_id);

create or replace function public.set_analytics_enabled(enabled boolean)
returns void
language plpgsql
security definer set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'authentication_required';
  end if;
  update public.profiles
  set analytics_enabled = enabled, updated_at = pg_catalog.now()
  where id = auth.uid();
end;
$$;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = ''
as $$
begin
  insert into public.profiles (id, locale)
  values (
    new.id,
    case
      when pg_catalog.lower(coalesce(new.raw_user_meta_data->>'locale', '')) = 'es' then 'es'
      else 'en'
    end
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

insert into public.profiles (id, locale)
select
  id,
  case
    when pg_catalog.lower(coalesce(raw_user_meta_data->>'locale', '')) = 'es' then 'es'
    else 'en'
  end
from auth.users
on conflict (id) do nothing;

create or replace function public.consume_scan_quota()
returns table(allowed boolean, used integer, quota integer, remaining integer)
language plpgsql
security definer set search_path = ''
as $$
declare
  current_uid uuid := auth.uid();
  current_period date := pg_catalog.date_trunc('month', pg_catalog.now())::date;
  current_plan text;
  max_scans integer;
  next_used integer;
begin
  if current_uid is null then
    raise exception 'authentication_required';
  end if;

  select plan into current_plan from public.profiles where id = current_uid;
  max_scans := case when current_plan = 'pro' then 50 else 5 end;

  insert into public.scan_usage(user_id, period_start, used)
  values (current_uid, current_period, 0)
  on conflict (user_id, period_start) do nothing;

  update public.scan_usage
  set used = scan_usage.used + 1, updated_at = pg_catalog.now()
  where user_id = current_uid
    and period_start = current_period
    and scan_usage.used < max_scans
  returning scan_usage.used into next_used;

  if next_used is null then
    select scan_usage.used into next_used
    from public.scan_usage
    where user_id = current_uid and period_start = current_period;
    return query select false, next_used, max_scans, 0;
  else
    return query select true, next_used, max_scans, greatest(0, max_scans - next_used);
  end if;
end;
$$;

create or replace function public.delete_my_account()
returns void
language plpgsql
security definer set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'authentication_required';
  end if;
  delete from auth.users where id = auth.uid();
end;
$$;

-- PostgREST table access is explicit. RLS remains the row-level boundary, while
-- table ACLs prevent clients from attempting operations the app never needs.
revoke all on table public.profiles from public, anon, authenticated;
revoke all on table public.garden_plants from public, anon, authenticated;
revoke all on table public.watering_events from public, anon, authenticated;
revoke all on table public.scan_usage from public, anon, authenticated;
revoke all on table public.scan_results from public, anon, authenticated;
revoke all on table public.analytics_events from public, anon, authenticated;

grant select on table public.profiles to authenticated;
grant select, insert, update, delete on table public.garden_plants to authenticated;
grant select, insert, update, delete on table public.watering_events to authenticated;
grant select on table public.scan_usage to authenticated;
grant select on table public.scan_results to authenticated;
grant select, insert on table public.analytics_events to authenticated;

-- Only trusted server code may write scan history. The service role still has
-- RLS bypass, so its key must never be shipped to Rocio clients.
grant insert on table public.scan_results to service_role;

revoke all on function public.reject_stale_garden_update() from public, anon, authenticated;
revoke all on function public.consume_scan_quota() from public, anon, authenticated;
revoke all on function public.delete_my_account() from public, anon, authenticated;
revoke all on function public.set_analytics_enabled(boolean) from public, anon, authenticated;
revoke all on function public.handle_new_user() from public, anon, authenticated;
grant execute on function public.consume_scan_quota() to authenticated;
grant execute on function public.delete_my_account() to authenticated;
grant execute on function public.set_analytics_enabled(boolean) to authenticated;
