-- ============================================================
-- Pipeline · Supabase schema + Row-Level Security
-- ------------------------------------------------------------
-- Run this once in your Supabase project's SQL editor:
--   https://supabase.com/dashboard/project/<id>/sql
-- It creates the `agents` table, enables RLS, and adds the
-- policies that scope every row to its owning user.
-- ============================================================

-- 1. Agents table -------------------------------------------------
create table if not exists public.agents (
  id                  uuid primary key default gen_random_uuid(),
  user_id             uuid references auth.users(id) on delete cascade not null,
  name                text not null,
  state               text,
  phone               text,
  email               text,
  onboarding_step     int  not null default 0,
  stage               text,
  progress            int  default 0,
  start_date          date,
  test_date           date,
  bg                  text default 'not-started',
  notes               text,
  photo               text,
  last_communication  timestamptz default now(),
  created_at          timestamptz default now(),
  updated_at          timestamptz default now()
);

create index if not exists agents_user_id_idx on public.agents(user_id);
create index if not exists agents_stage_idx   on public.agents(stage);

-- 2. Row-Level Security ------------------------------------------
alter table public.agents enable row level security;

-- A user can only see / mutate their own rows.
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

-- 3. updated_at trigger ------------------------------------------
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
-- When you're ready to support teams, add an `organizations`
-- table and an `organization_id` column on `agents`, then
-- update the RLS policies to scope on org membership instead
-- of (or in addition to) user_id. The current schema is
-- intentionally shaped so that change is additive.
-- ============================================================
