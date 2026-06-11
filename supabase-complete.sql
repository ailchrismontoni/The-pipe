-- ============================================================
-- Pipeline · Complete Supabase setup
-- ------------------------------------------------------------
-- Paste this entire script into your Supabase SQL Editor and
-- click "Run". Safe to re-run as many times as you want — every
-- statement is idempotent.
--
-- Where to run it:
--   Supabase dashboard → SQL Editor → New query
--   https://supabase.com/dashboard/project/rwrkkatrqdcjjgcpcerj/sql
-- ============================================================


-- 1. Agents table -------------------------------------------------
create table if not exists public.agents (
  id                     uuid primary key default gen_random_uuid(),
  user_id                uuid references auth.users(id) on delete cascade not null,
  name                   text not null,
  state                  text,
  phone                  text,
  email                  text,
  onboarding_step        int  not null default 0,
  stage                  text,
  progress               int  default 0,
  start_date             date,
  test_date              date,
  bg                     text default 'not-started',
  notes                  text,
  photo                  text,
  last_communication     timestamptz default now(),
  -- Instagram integration
  instagram_handle       text,
  profile_image_url      text,
  profile_image_source   text default 'default',
  -- Audit
  created_at             timestamptz default now(),
  updated_at             timestamptz default now()
);

-- For existing databases, add the Instagram columns if they're missing.
-- (No-op if the table was created fresh by the block above.)
alter table public.agents
  add column if not exists instagram_handle      text,
  add column if not exists profile_image_url     text,
  add column if not exists profile_image_source  text default 'default';


-- 2. Indexes ------------------------------------------------------
create index if not exists agents_user_id_idx          on public.agents(user_id);
create index if not exists agents_stage_idx            on public.agents(stage);
create index if not exists agents_instagram_handle_idx on public.agents(instagram_handle);


-- 3. Row-Level Security ------------------------------------------
alter table public.agents enable row level security;

-- A user can only see / mutate their own rows. RLS enforces this at the
-- database boundary — even if the anon key leaks, no user can read or
-- write another user's agents.

drop policy if exists "agents_select_own" on public.agents;
create policy "agents_select_own"
  on public.agents
  for select
  using (auth.uid() = user_id);

drop policy if exists "agents_insert_own" on public.agents;
create policy "agents_insert_own"
  on public.agents
  for insert
  with check (auth.uid() = user_id);

drop policy if exists "agents_update_own" on public.agents;
create policy "agents_update_own"
  on public.agents
  for update
  using (auth.uid() = user_id);

drop policy if exists "agents_delete_own" on public.agents;
create policy "agents_delete_own"
  on public.agents
  for delete
  using (auth.uid() = user_id);


-- 4. updated_at trigger ------------------------------------------
-- Auto-updates `updated_at` on every row UPDATE so you always know
-- the last time an agent record was touched.

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists agents_set_updated_at on public.agents;
create trigger agents_set_updated_at
  before update on public.agents
  for each row execute function public.set_updated_at();


-- ============================================================
-- (Future) Organizations / multi-agency support
-- ------------------------------------------------------------
-- When you're ready to let agencies invite team members, add:
--
--   create table public.organizations (
--     id          uuid primary key default gen_random_uuid(),
--     name        text not null,
--     owner_id    uuid references auth.users(id) on delete cascade,
--     created_at  timestamptz default now()
--   );
--
--   create table public.organization_members (
--     organization_id  uuid references public.organizations(id) on delete cascade,
--     user_id          uuid references auth.users(id) on delete cascade,
--     role             text check (role in ('owner', 'admin', 'member')),
--     primary key (organization_id, user_id)
--   );
--
--   alter table public.agents
--     add column organization_id uuid references public.organizations(id);
--
-- Then update the RLS policies to also allow access when the user
-- is a member of the agent's organization. The current schema is
-- intentionally shaped so that change is purely additive — nothing
-- in the existing app breaks.
-- ============================================================
