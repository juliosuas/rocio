import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const MAX_IMAGE_CHARS = 16 * 1024 * 1024;

type PlantIdSuggestion = {
  name?: string;
  probability?: number;
  details?: {
    scientific_name?: string;
    common_names?: string[];
    synonyms?: string[];
  };
};

function json(payload: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const apiKey = Deno.env.get("PLANT_ID_API_KEY");
  if (!apiKey) return json({ error: "missing_plant_id_secret" }, 500);

  let body: { image?: string; health?: boolean };
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }

  const image = String(body.image || "").replace(/^data:image\/\w+;base64,/, "");
  if (!image) return json({ error: "missing_image" }, 400);
  if (image.length > MAX_IMAGE_CHARS) return json({ error: "image_too_large" }, 413);

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 18_000);

  try {
    const response = await fetch("https://plant.id/api/v3/identification", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Api-Key": apiKey,
      },
      body: JSON.stringify({
        images: [image],
        classification_level: "species",
        health: body.health ?? "auto",
      }),
      signal: controller.signal,
    });

    const text = await response.text();
    let data: any = {};
    try { data = text ? JSON.parse(text) : {}; } catch { data = { raw: text }; }

    if (!response.ok) {
      return json({
        error: "plant_id_error",
        status: response.status,
        message: data?.message || data?.error || "Plant.id request failed",
      }, response.status >= 500 ? 502 : response.status);
    }

    const suggestions: PlantIdSuggestion[] = data?.result?.classification?.suggestions || [];
    return json({
      success: true,
      provider: "Plant.id",
      rawProviderCount: suggestions.length,
      suggestions: suggestions.slice(0, 8).map((item) => ({
        name: item.name || "",
        probability: Number(item.probability || 0),
        scientific_name: item.details?.scientific_name || item.name || "",
        common_names: item.details?.common_names || [],
        synonyms: item.details?.synonyms || [],
      })),
    });
  } catch (error) {
    const message = error instanceof Error && error.name === "AbortError"
      ? "Plant.id timeout"
      : error instanceof Error
        ? error.message
        : "Unknown Plant.id error";
    return json({ error: "provider_unavailable", message }, 502);
  } finally {
    clearTimeout(timeout);
  }
});
