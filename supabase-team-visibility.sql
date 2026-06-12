-- ============================================================
-- Pipeline · Roles & downline visibility migration
-- ------------------------------------------------------------
-- Adds a `user_profiles` table, hierarchical visibility helpers,
-- and updates the agents SELECT policy so leaders see their
-- downline and the owner sees everyone.
--
-- Run this once in your Supabase SQL editor. Safe to re-run.
-- ============================================================


-- 1. User profiles ----------------------------------------------------------
create table if not exists public.user_profiles (
  user_id       uuid primary key references auth.users(id) on delete cascade,
  email         text,
  display_name  text,
  role          text not null default 'member' check (role in ('owner', 'leader', 'member')),
  leader_id     uuid references public.user_profiles(user_id) on delete set null,
  created_at    timestamptz default now(),
  updated_at    timestamptz default now()
);

create index if not exists user_profiles_leader_idx on public.user_profiles (leader_id);
create index if not exists user_profiles_email_idx  on public.user_profiles (lower(email));


-- 2. Auto-create a profile row whenever a new auth user is created ----------
-- This is the trigger that grants ailchrismontoni@gmail.com the owner role
-- automatically the first time they sign up.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.user_profiles (user_id, email, display_name, role)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'name', split_part(new.email, '@', 1)),
    case when lower(new.email) = 'ailchrismontoni@gmail.com' then 'owner' else 'member' end
  )
  on conflict (user_id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();


-- 3. Backfill any users who already exist before this migration -------------
-- Idempotent: only sets owner role if the email matches; otherwise inserts as member.
insert into public.user_profiles (user_id, email, display_name, role)
select
  u.id,
  u.email,
  coalesce(u.raw_user_meta_data->>'name', split_part(u.email, '@', 1)),
  case when lower(u.email) = 'ailchrismontoni@gmail.com' then 'owner' else 'member' end
from auth.users u
on conflict (user_id) do update set
  role = case
    when lower(public.user_profiles.email) = 'ailchrismontoni@gmail.com' then 'owner'
    else public.user_profiles.role
  end;


-- 4. Helpers ----------------------------------------------------------------

-- Is the calling user the owner?
create or replace function public.is_owner()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.user_profiles
    where user_id = auth.uid() and role = 'owner'
  );
$$;

-- The set of user_ids whose agent rows the calling user is allowed to see:
--   - themselves
--   - recursive downline (people whose leader_id chains back to them)
--   - all users, if the caller is the owner
create or replace function public.visible_user_ids()
returns table (user_id uuid)
language sql
stable
security definer
set search_path = public
as $$
  with recursive downline as (
    select up.user_id from public.user_profiles up
    where up.user_id = auth.uid()
    union
    select up.user_id from public.user_profiles up
    join downline d on up.leader_id = d.user_id
  )
  select d.user_id from downline d
  union
  select up.user_id from public.user_profiles up
  where public.is_owner();
$$;


-- 5. RLS on user_profiles ---------------------------------------------------
-- Everyone signed in can read profiles (so the frontend can show owner names
-- on agent cards in team views). Only the user themselves or the owner can
-- mutate a profile (role assignment, leader assignment).
alter table public.user_profiles enable row level security;

drop policy if exists "user_profiles_select_any" on public.user_profiles;
create policy "user_profiles_select_any" on public.user_profiles
  for select to authenticated using (true);

drop policy if exists "user_profiles_insert_self" on public.user_profiles;
create policy "user_profiles_insert_self" on public.user_profiles
  for insert to authenticated with check (user_id = auth.uid() or public.is_owner());

drop policy if exists "user_profiles_update_self_or_owner" on public.user_profiles;
create policy "user_profiles_update_self_or_owner" on public.user_profiles
  for update to authenticated
  using (user_id = auth.uid() or public.is_owner())
  with check (user_id = auth.uid() or public.is_owner());

drop policy if exists "user_profiles_delete_owner_only" on public.user_profiles;
create policy "user_profiles_delete_owner_only" on public.user_profiles
  for delete to authenticated using (public.is_owner());


-- 6. Update agents SELECT policy --------------------------------------------
-- Replace the old "only your own" SELECT with a hierarchical one. The old
-- policy is named `agents_select_own` — drop it if it exists, then create the
-- new broader policy.
drop policy if exists "agents_select_own"     on public.agents;
drop policy if exists "agents_select_visible" on public.agents;

create policy "agents_select_visible" on public.agents
  for select to authenticated
  using (user_id in (select v.user_id from public.visible_user_ids() v));

-- INSERT / UPDATE / DELETE policies are intentionally left untouched: even
-- owners and leaders can only mutate THEIR OWN agents. They get read-only
-- access to everyone (or downline). Change this later if you want owner
-- write-anywhere by adding `or public.is_owner()` to those policies.


-- ============================================================
-- After running this script:
-- ------------------------------------------------------------
-- • Sign in as ailchrismontoni@gmail.com — your role will be 'owner'
-- • Promote someone to leader from the app (Manage members modal),
--   or directly via SQL:
--
--     update public.user_profiles set role = 'leader'
--     where email = 'them@example.com';
--
-- • Assign someone's upline:
--
--     update public.user_profiles set leader_id = (
--       select user_id from public.user_profiles where email = 'their-leader@example.com'
--     ) where email = 'them@example.com';
-- ============================================================
