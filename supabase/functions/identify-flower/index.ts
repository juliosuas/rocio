import { createClient } from "npm:@supabase/supabase-js@2";
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

const allowedOrigins = new Set([
  "https://juliosuas.github.io",
  "https://rocio-flower-care.lovable.app",
]);
const maxImageChars = 8 * 1024 * 1024;
const maxProviderTextChars = 200;
const maxProviderListItems = 16;

type PlantIdSuggestion = {
  name?: string;
  probability?: number;
  details?: {
    scientific_name?: string;
    common_names?: string[];
    synonyms?: string[];
  };
};

function safeText(value: unknown, maxChars = maxProviderTextChars) {
  return typeof value === "string" ? value.trim().slice(0, maxChars) : "";
}

function safeTextList(value: unknown) {
  if (!Array.isArray(value)) return [];
  return value
    .slice(0, maxProviderListItems)
    .map((item) => safeText(item, maxProviderTextChars))
    .filter(Boolean);
}

function safeProbability(value: unknown) {
  const probability = Number(value);
  return Number.isFinite(probability) ? Math.min(1, Math.max(0, probability)) : 0;
}

function corsHeaders(req: Request) {
  const origin = req.headers.get("origin");
  return {
    "Access-Control-Allow-Origin": origin && allowedOrigins.has(origin) ? origin : "https://juliosuas.github.io",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Vary": "Origin",
  };
}

function json(req: Request, payload: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders(req), "Content-Type": "application/json", "Cache-Control": "no-store" },
  });
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders(req) });
  if (req.method !== "POST") return json(req, { error: "method_not_allowed" }, 405);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const apiKey = Deno.env.get("PLANT_ID_API_KEY");
  const authorization = req.headers.get("authorization");
  if (!supabaseUrl || !anonKey || !serviceRoleKey || !apiKey) {
    return json(req, { error: "service_not_configured" }, 503);
  }
  if (!authorization?.startsWith("Bearer ")) return json(req, { error: "authentication_required" }, 401);

  // The user's JWT remains attached only to the RLS-scoped client. It authenticates
  // the caller and invokes the quota RPC without granting server privileges.
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: userData, error: userError } = await userClient.auth.getUser(authorization.slice(7));
  if (userError || !userData.user) return json(req, { error: "invalid_session" }, 401);

  // This client is server-only and never receives user-controlled headers. Its
  // sole use in this handler is writing the protected scan_results audit row.
  const adminClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  let body: { image?: string; consent?: boolean };
  try {
    body = await req.json();
  } catch {
    return json(req, { error: "invalid_json" }, 400);
  }

  if (body.consent !== true) return json(req, { error: "photo_consent_required" }, 400);
  const image = String(body.image || "").replace(/^data:image\/\w+;base64,/, "");
  if (!image) return json(req, { error: "missing_image" }, 400);
  if (image.length > maxImageChars) return json(req, { error: "image_too_large" }, 413);

  const { data: quotaRows, error: quotaError } = await userClient.rpc("consume_scan_quota");
  const quota = quotaRows?.[0];
  if (quotaError) return json(req, { error: "quota_unavailable" }, 503);
  if (!quota) return json(req, { error: "quota_unavailable" }, 503);
  if (!quota.allowed) {
    return json(req, { error: "quota_exhausted", quota: quota.quota, remaining: 0 }, 429);
  }

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 18_000);

  try {
    const response = await fetch("https://plant.id/api/v3/identification", {
      method: "POST",
      headers: { "Content-Type": "application/json", "Api-Key": apiKey },
      body: JSON.stringify({ images: [image], classification_level: "species", health: "auto" }),
      signal: controller.signal,
    });
    const providerData = await response.json().catch(() => ({}));
    if (!response.ok) {
      return json(req, { error: "provider_unavailable", remaining: quota.remaining }, 502);
    }

    const raw: PlantIdSuggestion[] = providerData?.result?.classification?.suggestions || [];
    const suggestions = raw.slice(0, 8).map((item) => ({
      name: safeText(item.name),
      probability: safeProbability(item.probability),
      scientific_name: safeText(item.details?.scientific_name || item.name),
      common_names: safeTextList(item.details?.common_names),
      synonyms: safeTextList(item.details?.synonyms),
    }));

    const { error: scanResultError } = await adminClient.from("scan_results").insert({
      user_id: userData.user.id,
      provider: "plant_id",
      top_name: suggestions[0]?.scientific_name || null,
      confidence: suggestions[0]?.probability ?? null,
      candidate_count: suggestions.length,
    });
    if (scanResultError) {
      return json(req, { error: "scan_result_unavailable", remaining: quota.remaining }, 503);
    }

    return json(req, {
      success: true,
      provider: "plant_id",
      suggestions,
      quota: quota.quota,
      remaining: quota.remaining,
    });
  } catch (error) {
    const code = error instanceof Error && error.name === "AbortError" ? "provider_timeout" : "provider_unavailable";
    return json(req, { error: code, remaining: quota.remaining }, 502);
  } finally {
    clearTimeout(timeout);
  }
});
