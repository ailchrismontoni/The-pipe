-- ============================================================
-- Pipeline · Instagram integration migration
-- ------------------------------------------------------------
-- Run this in your Supabase project's SQL editor.
-- Adds three columns to the agents table for the Instagram
-- profile-picture feature. Safe to re-run.
-- ============================================================

alter table public.agents
  add column if not exists instagram_handle      text,
  add column if not exists profile_image_url     text,
  add column if not exists profile_image_source  text default 'default';

create index if not exists agents_instagram_handle_idx
  on public.agents (instagram_handle);

-- `profile_image_source` allowed values: 'instagram' | 'manual' | 'upload' | 'default'
-- We don't enforce a check constraint so it's forward-compatible with new sources.
