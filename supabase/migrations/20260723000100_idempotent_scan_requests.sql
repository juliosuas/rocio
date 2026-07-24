-- Give every consented cloud scan an at-most-once server claim. The ledger
-- stores only a bounded normalized response; it never stores the submitted
-- photo or the provider access token. Entries expire after seven days and are
-- pruned on the account's next scan request.

create table if not exists public.scan_requests (
  user_id uuid not null references auth.users(id) on delete cascade,
  request_id uuid not null,
  provider_custom_id bigint generated always as identity,
  state text not null default 'pending'
    constraint scan_requests_state check (state in ('pending', 'completed')),
  quota_limit integer
    constraint scan_requests_quota_limit_range check (quota_limit between 1 and 50),
  remaining integer
    constraint scan_requests_remaining_range check (
      remaining between 0 and 50
      and (quota_limit is null or remaining <= quota_limit)
    ),
  response_payload jsonb
    constraint scan_requests_response_object check (
      response_payload is null or pg_catalog.jsonb_typeof(response_payload) = 'object'
    )
    constraint scan_requests_response_size check (
      response_payload is null
      or pg_catalog.octet_length(response_payload::text) <= 131072
    ),
  http_status integer
    constraint scan_requests_http_status_range check (
      http_status is null or http_status between 200 and 599
    ),
  created_at timestamptz not null default pg_catalog.now(),
  completed_at timestamptz,
  expires_at timestamptz not null default (pg_catalog.now() + interval '7 days'),
  primary key (user_id, request_id),
  unique (provider_custom_id),
  constraint scan_requests_provider_custom_id_positive check (provider_custom_id > 0),
  constraint scan_requests_completion_shape check (
    (
      state = 'pending'
      and response_payload is null
      and http_status is null
      and completed_at is null
    )
    or (
      state = 'completed'
      and response_payload is not null
      and http_status is not null
      and completed_at is not null
    )
  ),
  constraint scan_requests_retention_window check (
    expires_at > created_at
    and expires_at <= created_at + interval '7 days'
  )
);

create index if not exists scan_requests_user_expiry_idx
  on public.scan_requests(user_id, expires_at);

alter table public.scan_requests enable row level security;

alter table public.scan_results
  add column if not exists request_id uuid;

create unique index if not exists scan_results_user_request_idx
  on public.scan_results(user_id, request_id)
  where request_id is not null;

create or replace function public.begin_scan_request(p_request_id uuid)
returns table(
  claim_status text,
  quota integer,
  remaining integer,
  response_payload jsonb,
  http_status integer,
  provider_custom_id bigint,
  can_abandon boolean
)
language plpgsql
security definer set search_path = ''
as $$
declare
  current_uid uuid := auth.uid();
  did_insert boolean := false;
  existing_request public.scan_requests%rowtype;
  quota_result record;
begin
  if current_uid is null then
    raise exception 'authentication_required';
  end if;
  if p_request_id is null then
    raise exception 'scan_request_id_required';
  end if;

  -- Completion locks the replay row before writing scan_results. Take the same
  -- lock order here so an in-flight completion cannot recreate a linked audit
  -- row after its expired request has been pruned.
  perform requests.request_id
  from public.scan_requests as requests
  where requests.user_id = current_uid
    and requests.expires_at <= pg_catalog.now()
  for update;

  -- scan_results is durable user-visible history, while request_id is only its
  -- seven-day idempotency link. Release expired links before deleting replay
  -- rows so a deliberately reused UUID can complete as a fresh operation.
  update public.scan_results as results
  set request_id = null
  where results.user_id = current_uid
    and exists (
      select 1
      from public.scan_requests as requests
      where requests.user_id = current_uid
        and requests.request_id = results.request_id
        and requests.expires_at <= pg_catalog.now()
    );

  delete from public.scan_requests as requests
  where requests.user_id = current_uid
    and requests.expires_at <= pg_catalog.now();

  insert into public.scan_requests (user_id, request_id)
  values (current_uid, p_request_id)
  on conflict (user_id, request_id) do nothing
  returning true into did_insert;

  if not coalesce(did_insert, false) then
    select requests.*
    into strict existing_request
    from public.scan_requests as requests
    where requests.user_id = current_uid
      and requests.request_id = p_request_id;

    if existing_request.state = 'completed' then
      return query
      select
        'replay'::text,
        existing_request.quota_limit,
        existing_request.remaining,
        existing_request.response_payload,
        existing_request.http_status,
        existing_request.provider_custom_id,
        false;
    else
      return query
      select
        'recover'::text,
        existing_request.quota_limit,
        existing_request.remaining,
        null::jsonb,
        null::integer,
        existing_request.provider_custom_id,
        existing_request.created_at <=
          pg_catalog.now() - interval '2 minutes';
    end if;
    return;
  end if;

  select *
  into strict quota_result
  from public.consume_scan_quota();

  if quota_result.allowed is distinct from true then
    delete from public.scan_requests as requests
    where requests.user_id = current_uid
      and requests.request_id = p_request_id;

    return query
    select
      'quota_exhausted'::text,
      quota_result.quota,
      0,
      null::jsonb,
      429,
      null::bigint,
      false;
    return;
  end if;

  update public.scan_requests as requests
  set
    quota_limit = quota_result.quota,
    remaining = quota_result.remaining
  where requests.user_id = current_uid
    and requests.request_id = p_request_id;

  return query
  select
    'claimed'::text,
    quota_result.quota,
    quota_result.remaining,
    null::jsonb,
    null::integer,
    (
      select requests.provider_custom_id
      from public.scan_requests as requests
      where requests.user_id = current_uid
        and requests.request_id = p_request_id
    ),
    false;
end;
$$;

create or replace function public.complete_scan_request(
  p_user_id uuid,
  p_request_id uuid,
  p_response_payload jsonb,
  p_http_status integer,
  p_top_name text default null,
  p_confidence numeric default null,
  p_candidate_count integer default 0
)
returns boolean
language plpgsql
security definer set search_path = ''
as $$
declare
  existing_request public.scan_requests%rowtype;
begin
  if p_user_id is null or p_request_id is null then
    raise exception 'scan_request_identity_required';
  end if;
  if p_response_payload is null
     or pg_catalog.jsonb_typeof(p_response_payload) <> 'object'
     or pg_catalog.octet_length(p_response_payload::text) > 131072 then
    raise exception 'scan_response_invalid';
  end if;
  if p_http_status < 200 or p_http_status > 599 then
    raise exception 'scan_response_status_invalid';
  end if;

  select requests.*
  into existing_request
  from public.scan_requests as requests
  where requests.user_id = p_user_id
    and requests.request_id = p_request_id
  for update;

  if not found then
    return false;
  end if;

  if existing_request.state = 'completed' then
    return existing_request.http_status = p_http_status
      and existing_request.response_payload = p_response_payload;
  end if;

  if p_http_status = 200 then
    insert into public.scan_results (
      user_id,
      request_id,
      provider,
      top_name,
      confidence,
      candidate_count
    )
    values (
      p_user_id,
      p_request_id,
      'plant_id',
      p_top_name,
      p_confidence,
      p_candidate_count
    );
  end if;

  update public.scan_requests as requests
  set
    state = 'completed',
    response_payload = p_response_payload,
    http_status = p_http_status,
    completed_at = pg_catalog.now()
  where requests.user_id = p_user_id
    and requests.request_id = p_request_id;

  return true;
end;
$$;

revoke all on table public.scan_requests
  from public, anon, authenticated, service_role;

revoke all on function public.begin_scan_request(uuid)
  from public, anon, authenticated;
grant execute on function public.begin_scan_request(uuid)
  to authenticated;

revoke all on function public.complete_scan_request(
  uuid, uuid, jsonb, integer, text, numeric, integer
) from public, anon, authenticated, service_role;
grant execute on function public.complete_scan_request(
  uuid, uuid, jsonb, integer, text, numeric, integer
) to service_role;
