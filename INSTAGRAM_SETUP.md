# Instagram Profile Integration

Pipeline can pull an agent's public Instagram profile picture and use it as
their Pipeline avatar. Here's how the pieces fit together — and what you need
to do to switch from the in-app demo fallback to the real Instagram Graph API.

## Architecture

```
Browser (index.html)
  └─ instagramService.fetchProfile(handle)
       ├─ tries  →  Supabase Edge Function: instagram-profile
       │                  └─ calls Meta Graph API server-side using
       │                     INSTAGRAM_GRAPH_TOKEN (held as a Supabase secret,
       │                     never exposed to the browser)
       └─ if the function isn't deployed or returns an error,
          falls back to a deterministic illustrated avatar
          (Dicebear "notionists") so the UI is still usable.
```

The token never touches the browser. The publishable / anon Supabase key in
`index.html` is fine to ship — it's gated by RLS.

## Step 1 — Run the schema migration

In the Supabase dashboard → **SQL Editor → New query**, paste the contents of
[`supabase-instagram-migration.sql`](./supabase-instagram-migration.sql) and
hit **Run**. Adds three columns to `public.agents`:

- `instagram_handle text`
- `profile_image_url text`
- `profile_image_source text default 'default'`

Safe to re-run; uses `add column if not exists`.

## Step 2 — Get a Meta Graph API token

You need a Meta business app with the **Instagram Graph API** enabled and a
**long-lived access token** tied to a business Instagram user. The token's
`business_discovery` permission lets you look up *any* public IG account's
profile picture, name, and recent media — but only handles that are themselves
linked to a Facebook page (typical for businesses, creators, and most
recruiters / agents using IG for marketing).

Docs: <https://developers.facebook.com/docs/instagram-api/guides/business-discovery>

You'll need two values:

- `INSTAGRAM_GRAPH_TOKEN` — your long-lived user access token
- `INSTAGRAM_BUSINESS_USER_ID` — the IG Business User ID the token is scoped to

## Step 3 — Deploy the Edge Function

Install the Supabase CLI and deploy the function stub at
[`supabase/functions/instagram-profile/index.ts`](./supabase/functions/instagram-profile/index.ts):

```bash
# Install once
brew install supabase/tap/supabase

# Set up the project
supabase login
supabase link --project-ref rwrkkatrqdcjjgcpcerj

# Store the secrets (never appear in code or in the browser)
supabase secrets set INSTAGRAM_GRAPH_TOKEN="EAA...your-long-lived-token..."
supabase secrets set INSTAGRAM_BUSINESS_USER_ID="178414...your-ig-business-user-id..."

# Deploy
supabase functions deploy instagram-profile
```

Once deployed, `instagramService.fetchProfile()` in the browser will hit your
function automatically — no code change needed. The "Demo preview" banner in
the Add Agent modal will switch to "Connected to Instagram."

## Step 4 — Test it

1. In Pipeline, click **+ Add Agent**
2. In the **Instagram handle** field, type any of:
   - `chris17montoni`
   - `@chris17montoni`
   - `https://instagram.com/chris17montoni`
3. Click **Fetch photo** (or press Enter in the field)
4. You'll see a preview chip with the photo, the cleaned `@handle`, and a
   green "Connected to Instagram" confirmation
5. Save the agent — the photo flows through to their avatar everywhere
   (card, row view, profile modal, drill-down list)
6. The `@handle` becomes a clickable chip in the meta-row that opens their
   real Instagram profile in a new tab

## Behavior with no token configured

- The Edge Function returns `503 { error: "...", configured: false }`
- The frontend service silently falls through to the Dicebear illustrated
  avatar fallback
- The UI shows an amber "Demo preview" status with a clear note that you need
  to deploy the function to fetch the real photo
- Everything else (saving, displaying, linking) still works end-to-end

## What's stored

For each agent:

| Column                  | Example                                                 |
|-------------------------|---------------------------------------------------------|
| `instagram_handle`      | `chris17montoni`                                        |
| `profile_image_url`     | `https://scontent.cdninstagram.com/v/t51.2885-19/...`   |
| `profile_image_source`  | `instagram` \| `manual` \| `upload` \| `default`       |

Source-of-truth precedence (if multiple are present):
- Instagram fetch result overrides a previously-uploaded photo
- Manual file upload after an IG fetch overrides the IG photo (last action wins)

## Privacy / ToS

This integration only fetches **public** business / creator account info via
the official Graph API's `business_discovery` endpoint. It does not scrape,
does not bypass rate limits, and does not store IG access tokens client-side.
