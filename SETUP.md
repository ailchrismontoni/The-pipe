# Pipeline — Setup

The Pipeline app uses **Supabase** for authentication and per-user data. The whole frontend
is still the single `index.html` you've been working with — Supabase is loaded from a CDN
at the top of the file.

## 1. Create a Supabase project

1. Sign up at <https://supabase.com> (free tier is fine).
2. Click **New project**, give it a name (e.g. `pipeline`), pick a region, set a database password.
3. Once it provisions, go to **Settings → API** and copy:
   - **Project URL** (looks like `https://xxxxxxxxxxxxx.supabase.co`)
   - **anon public key** (a long JWT — *not* the service role key)

## 2. Drop in your project URL + key

Open `index.html`, find this block near the top of the `<script>` tag:

```js
const SUPABASE_URL      = "YOUR_SUPABASE_URL";
const SUPABASE_ANON_KEY = "YOUR_SUPABASE_ANON_KEY";
```

Replace both strings with the values you copied. The anon key is safe to ship in the
browser — Row-Level Security (next step) is what actually protects your data.

## 3. Run the database schema

In your Supabase dashboard:

1. Open **SQL Editor → New query**.
2. Paste the contents of [`supabase-setup.sql`](./supabase-setup.sql) and run it.

This creates the `agents` table, indexes, an `updated_at` trigger, and four RLS policies
that scope every row to its owning user (`auth.uid() = user_id`).

## 4. (Optional) Auth settings

By default Supabase requires email confirmation. While developing, you can disable it under
**Authentication → Providers → Email → "Confirm email"** so accounts work immediately on signup.

## 5. Open the app

Open `index.html` in a browser. You should see the **Sign in to Pipeline** screen.

- Click **Create an account**, fill in the form, and submit.
- If email confirmation is on, confirm via the email link, then sign back in.
- The dashboard will load — your new account is seeded with the sample pipeline so you
  have something to play with right away.

## What's in the data model now

```text
auth.users          (managed by Supabase)
└─ id, email, …

public.agents
├─ id              uuid (PK)
├─ user_id         uuid → auth.users.id   ← Row-Level Security scopes everything by this
├─ name, state, phone, email
├─ onboarding_step, stage, progress
├─ start_date, test_date
├─ bg, notes, photo
├─ last_communication
└─ created_at, updated_at
```

Every read / write the app makes goes through Supabase's PostgREST API with the user's JWT.
RLS guarantees a user can only ever see or mutate rows where `user_id = auth.uid()`.

## Ready for teams later

The schema is intentionally shaped so you can add an `organizations` table and an
`organization_id` column on `agents` without breaking anything. When you're ready,
swap the RLS policies to check organization membership instead of (or in addition to)
`user_id`.
