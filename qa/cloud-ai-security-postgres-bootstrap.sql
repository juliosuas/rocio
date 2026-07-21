\set ON_ERROR_STOP on

begin;

-- A minimal Supabase-shaped environment for applying the repository's SQL
-- migrations to a stock PostgreSQL 16 server. Everything is rolled back by
-- cloud-ai-security-postgres.test.sql, including these cluster roles.
do $bootstrap$
begin
  if not exists (select 1 from pg_catalog.pg_roles where rolname = 'anon') then
    create role anon nologin;
  end if;
  if not exists (select 1 from pg_catalog.pg_roles where rolname = 'authenticated') then
    create role authenticated nologin;
  end if;
  if not exists (select 1 from pg_catalog.pg_roles where rolname = 'service_role') then
    create role service_role nologin bypassrls;
  end if;
end;
$bootstrap$;

create schema if not exists auth;

create table if not exists auth.users (
  id uuid primary key,
  raw_user_meta_data jsonb not null default '{}'::jsonb
);

create or replace function auth.uid()
returns uuid
language sql
stable
set search_path = ''
as $uid$
  select nullif(pg_catalog.current_setting('request.jwt.claim.sub', true), '')::uuid
$uid$;

grant usage on schema auth to anon, authenticated, service_role;
grant execute on function auth.uid() to anon, authenticated, service_role;
