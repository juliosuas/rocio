\set ON_ERROR_STOP on

-- This fixture is intentionally applied after the foundation migration and
-- before every later migration. It proves that an upgrade preserves existing
-- account-owned data and backfills new synchronization columns correctly.
insert into auth.users (id, raw_user_meta_data)
values ('33333333-3333-3333-3333-333333333333', '{"locale":"en"}'::jsonb);

insert into public.garden_plants (
  id,
  user_id,
  flower_id,
  nickname,
  added_at,
  last_watered_at,
  status,
  notes,
  updated_at
)
values (
  'ffffffff-ffff-ffff-ffff-ffffffffffff',
  '33333333-3333-3333-3333-333333333333',
  'rosa',
  'Pre-upgrade rose',
  '2026-07-20T08:00:00Z',
  '2026-07-20T08:00:00Z',
  'healthy',
  'Existing care history',
  '2026-07-20T08:00:00Z'
);

insert into public.watering_events (
  id,
  user_id,
  plant_id,
  watered_at,
  created_at
)
values (
  '44444444-4444-4444-4444-444444444444',
  '33333333-3333-3333-3333-333333333333',
  'ffffffff-ffff-ffff-ffff-ffffffffffff',
  '2026-07-20T08:00:00Z',
  '2026-07-20T08:00:00Z'
);
