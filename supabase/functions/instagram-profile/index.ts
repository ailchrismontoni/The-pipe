// =============================================================================
// Supabase Edge Function: instagram-profile
// =============================================================================
//
// Purpose
//   Given a public Instagram handle, return that account's profile picture URL
//   and (optionally) display name. This file is a server-side proxy so we can
//   keep the Instagram / Meta access token off the browser.
//
// Deployment
//   1. Install the Supabase CLI:  brew install supabase/tap/supabase
//   2. Log in:                    supabase login
//   3. Link your project:         supabase link --project-ref rwrkkatrqdcjjgcpcerj
//   4. Set the secret token:      supabase secrets set INSTAGRAM_GRAPH_TOKEN=<your-token>
//                                 supabase secrets set INSTAGRAM_BUSINESS_USER_ID=<your-business-ig-user-id>
//   5. Deploy:                    supabase functions deploy instagram-profile
//
// Getting a token
//   You need a Meta / Facebook business app with the Instagram Graph API
//   enabled and a long-lived access token tied to a business Instagram user.
//   Docs: https://developers.facebook.com/docs/instagram-api/guides/business-discovery
//
//   The token has rate limits and only works for handles that have linked
//   their Instagram account to a Facebook page — typical for businesses,
//   creators, and most insurance agents who use IG for marketing.
//
// Request
//   POST /functions/v1/instagram-profile
//   Body: { "handle": "chris17montoni" }
//
// Response (success)
//   { "handle": "chris17montoni",
//     "profileImageUrl": "https://scontent.cdninstagram.com/...",
//     "displayName": "Chris Montoni" }
//
// Response (error)
//   { "error": "human-readable message" }   with appropriate HTTP status
// =============================================================================

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });

function normalizeHandle(raw: string): string | null {
  if (!raw) return null;
  let h = String(raw).trim();
  h = h.replace(/^https?:\/\/(www\.)?instagram\.com\//i, "");
  h = h.replace(/^@/, "");
  h = h.split(/[\/?#]/)[0];
  if (!/^[a-zA-Z0-9._]{1,30}$/.test(h)) return null;
  return h.toLowerCase();
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "Use POST" }, 405);

  let payload: { handle?: string };
  try {
    payload = await req.json();
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  const handle = normalizeHandle(payload.handle ?? "");
  if (!handle) {
    return json({ error: "Invalid Instagram handle" }, 400);
  }

  const token = Deno.env.get("INSTAGRAM_GRAPH_TOKEN");
  const igUserId = Deno.env.get("INSTAGRAM_BUSINESS_USER_ID");

  if (!token || !igUserId) {
    return json(
      {
        error:
          "Instagram Graph API not configured. Set INSTAGRAM_GRAPH_TOKEN and INSTAGRAM_BUSINESS_USER_ID via `supabase secrets set` and redeploy.",
        configured: false,
      },
      503,
    );
  }

  // -------------------------------------------------------------------------
  // Real Instagram Graph API call (business_discovery)
  // -------------------------------------------------------------------------
  const url =
    `https://graph.facebook.com/v18.0/${igUserId}` +
    `?fields=business_discovery.username(${encodeURIComponent(handle)})` +
    `{username,name,profile_picture_url}` +
    `&access_token=${encodeURIComponent(token)}`;

  try {
    const resp = await fetch(url);
    const data = await resp.json();

    if (!resp.ok || data.error) {
      const msg = data?.error?.message || `Instagram API error (${resp.status})`;
      return json({ error: msg }, resp.status || 502);
    }

    const bd = data?.business_discovery;
    if (!bd?.profile_picture_url) {
      return json(
        { error: `No public profile picture found for @${handle}` },
        404,
      );
    }

    return json({
      handle: bd.username || handle,
      profileImageUrl: bd.profile_picture_url,
      displayName: bd.name || null,
    });
  } catch (e) {
    return json({ error: (e as Error).message || "Fetch failed" }, 502);
  }
});
