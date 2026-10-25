-- LookUp backend schema. All tables are service-role only (RLS on, no
-- policies): the app talks to Edge Functions, never to tables directly.

create table if not exists public.devices (
  id uuid primary key default gen_random_uuid(),
  token text not null unique,
  platform text not null check (platform in ('ios', 'android')),
  lat numeric(4, 1) not null,          -- rounded to 0.1° (~10 km)
  lon numeric(4, 1) not null,
  cell text not null,                  -- geohash-4
  kp_needed real not null,
  plus boolean not null default false,
  wake_me boolean not null default false,
  quiet_start int not null default 1380,
  quiet_end int not null default 330,
  utc_offset_min int not null default 0,
  updated_at timestamptz not null default now()
);
create index if not exists devices_plus_kp on public.devices (plus, kp_needed);
alter table public.devices enable row level security;

create table if not exists public.aurora_sent (
  device_id uuid not null references public.devices (id) on delete cascade,
  bucket timestamptz not null,
  sent_at timestamptz not null default now(),
  primary key (device_id, bucket)
);
alter table public.aurora_sent enable row level security;

create table if not exists public.orbit_cache (
  key text primary key,
  body jsonb not null,
  fetched_at timestamptz not null
);
alter table public.orbit_cache enable row level security;

create table if not exists public.analytics_events (
  id bigint generated always as identity primary key,
  install_id text not null,
  name text not null,
  at timestamptz not null,
  props jsonb not null default '{}'::jsonb,
  received_at timestamptz not null default now()
);
create index if not exists analytics_events_name_at on public.analytics_events (name, at);
alter table public.analytics_events enable row level security;

create table if not exists public.entitlements (
  install_id text primary key,
  platform text not null,
  product_id text not null,
  original_id text not null,
  active boolean not null,
  expires_at timestamptz,
  verified_at timestamptz not null
);
alter table public.entitlements enable row level security;

-- Spec section 10 metrics, ready to read in the dashboard.
create or replace view public.metrics_daily
with (security_invoker = true) as
select
  date_trunc('day', at) as day,
  count(*) filter (where name = 'app_open') as opens,
  count(distinct install_id) as active_installs,
  count(*) filter (where name = 'seen_yes') as seen_yes,
  count(*) filter (where name = 'seen_no') as seen_no,
  round(100.0 * count(*) filter (where name = 'seen_yes')
    / nullif(count(*) filter (where name in ('seen_yes', 'seen_no')), 0), 1) as alert_precision_pct,
  count(*) filter (where name = 'paywall_shown') as paywalls,
  count(*) filter (where name = 'purchase_completed') as purchases
from public.analytics_events
group by 1
order by 1 desc;

-- Housekeeping: aurora dedupe rows only matter for 3 hours.
create or replace function public.prune_lookup() returns void language sql as $$
  delete from public.aurora_sent where bucket < now() - interval '1 day';
  delete from public.analytics_events where at < now() - interval '400 days';
$$;
