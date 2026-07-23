const allowedOrigins = new Set([
  "https://juliosuas.github.io",
  "https://rocio-flower-care.lovable.app",
]);
const maxImageChars = 8 * 1024 * 1024;
const maxProviderTextChars = 200;
const maxProviderListItems = 16;
const maxReplayPayloadBytes = 112 * 1024;

type PlantIdSuggestion = {
  id?: string | number;
  name?: string;
  probability?: number;
  rank?: string;
  details?: {
    scientific_name?: string;
    common_names?: string[];
    synonyms?: string[];
    rank?: string;
    taxonomy?: Record<string, unknown>;
  };
};

type PlantIdBooleanResult = {
  binary?: boolean;
  probability?: number;
  threshold?: number;
};

type ClientOptions = {
  global?: { headers?: Record<string, string> };
  auth?: { persistSession?: boolean; autoRefreshToken?: boolean };
};

type QueryResult<T> = PromiseLike<{ data: T; error: unknown }>;

type ScanClaim = {
  claim_status?: unknown;
  quota?: unknown;
  remaining?: unknown;
  response_payload?: unknown;
  http_status?: unknown;
  provider_custom_id?: unknown;
  can_abandon?: unknown;
};

export type SupabaseClientLike = {
  auth: {
    getUser(token: string): QueryResult<{ user: { id: string } | null }>;
  };
  rpc(
    name: string,
    arguments_?: Record<string, unknown>,
  ): QueryResult<unknown>;
};

export type IdentifyFlowerDependencies = {
  createClient(
    url: string,
    key: string,
    options: ClientOptions,
  ): SupabaseClientLike;
  env(name: string): string | undefined;
  fetch(input: string | URL | Request, init?: RequestInit): Promise<Response>;
  scheduleTimeout(callback: () => void, delay: number): unknown;
  cancelTimeout(handle: unknown): void;
};

function safeText(value: unknown, maxChars = maxProviderTextChars) {
  if (typeof value !== "string") return "";
  // PostgreSQL jsonb rejects U+0000, and UTF-16 slicing can leave an unpaired
  // surrogate that jsonb also rejects. Normalize by Unicode code point before
  // any provider-controlled value reaches the durable replay payload.
  return Array.from(value.replaceAll("\u0000", "").trim())
    .slice(0, maxChars)
    .join("");
}

function safeIdentifier(value: unknown) {
  if (typeof value !== "string" && typeof value !== "number") return "";
  return Array.from(String(value).replaceAll("\u0000", "").trim())
    .slice(0, maxProviderTextChars)
    .join("");
}

function safeTextList(value: unknown) {
  if (!Array.isArray(value)) return [];
  return value
    .slice(0, maxProviderListItems)
    .map((item) => safeText(item, maxProviderTextChars))
    .filter(Boolean);
}

function safeTextMap(value: unknown) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return {};
  return Object.fromEntries(
    Object.entries(value)
      .slice(0, maxProviderListItems)
      .map(([key, item]) => [
        safeText(key, 80),
        safeText(item, maxProviderTextChars),
      ])
      .filter(([key, item]) => key && item),
  );
}

function safeProbability(value: unknown) {
  const probability = Number(value);
  return Number.isFinite(probability) ? Math.min(1, Math.max(0, probability)) : 0;
}

function safeOptionalProbability(value: unknown) {
  const probability = Number(value);
  return Number.isFinite(probability) ? Math.min(1, Math.max(0, probability)) : null;
}

function safePlantPresence(value: unknown) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const result = value as PlantIdBooleanResult;
  return {
    binary: typeof result.binary === "boolean" ? result.binary : null,
    probability: safeOptionalProbability(result.probability),
    threshold: safeOptionalProbability(result.threshold),
  };
}

function safeLocale(value: unknown) {
  const locale = safeText(value, 16).toLowerCase().split(/[-_]/)[0];
  return locale === "es" ? "es" : "en";
}

function safeRequestID(value: unknown) {
  if (typeof value !== "string") return "";
  const requestID = value.trim().toLowerCase();
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(
      requestID,
    )
    ? requestID
    : "";
}

function safeInteger(value: unknown) {
  return typeof value === "number" && Number.isSafeInteger(value) ? value : null;
}

function safeObject(value: unknown): Record<string, unknown> | null {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null;
}

function normalizedProviderResult(providerData: Record<string, unknown>) {
  const result = safeObject(providerData.result);
  const classification = safeObject(result?.classification);
  const raw = classification?.suggestions;
  if (!Array.isArray(raw)) throw new Error("invalid_provider_response");

  const suggestions = (raw as PlantIdSuggestion[]).slice(0, 8).map((item) => {
    const providerID = safeIdentifier(item.id);
    const rank = safeText(item.details?.rank || item.rank, 80);
    return {
      ...(providerID ? { id: providerID } : {}),
      name: safeText(item.name),
      probability: safeProbability(item.probability),
      scientific_name: safeText(item.details?.scientific_name || item.name),
      common_names: safeTextList(item.details?.common_names),
      synonyms: safeTextList(item.details?.synonyms),
      ...(rank ? { rank } : {}),
      taxonomy: safeTextMap(item.details?.taxonomy),
    };
  });
  return {
    suggestions,
    isPlant: safePlantPresence(result?.is_plant),
  };
}

function boundReplayPayload(payload: Record<string, unknown>) {
  const suggestions = Array.isArray(payload.suggestions)
    ? payload.suggestions as Array<Record<string, unknown>>
    : [];
  const payloadSize = () =>
    new TextEncoder().encode(JSON.stringify(payload)).byteLength;

  while (payloadSize() > maxReplayPayloadBytes) {
    let reduced = false;
    for (let index = suggestions.length - 1; index >= 0; index -= 1) {
      const suggestion = suggestions[index];
      const synonyms = suggestion.synonyms;
      if (Array.isArray(synonyms) && synonyms.length > 0) {
        synonyms.pop();
        reduced = true;
        break;
      }
      const taxonomy = safeObject(suggestion.taxonomy);
      const taxonomyKey = taxonomy ? Object.keys(taxonomy).at(-1) : undefined;
      if (taxonomy && taxonomyKey) {
        delete taxonomy[taxonomyKey];
        reduced = true;
        break;
      }
      const commonNames = suggestion.common_names;
      if (Array.isArray(commonNames) && commonNames.length > 0) {
        commonNames.pop();
        reduced = true;
        break;
      }
    }
    if (!reduced && suggestions.length > 1) {
      suggestions.pop();
      reduced = true;
    }
    if (!reduced) throw new Error("normalized_response_too_large");
  }
  return payload;
}

function corsHeaders(req: Request) {
  const origin = req.headers.get("origin");
  return {
    "Access-Control-Allow-Origin": origin && allowedOrigins.has(origin)
      ? origin
      : "https://juliosuas.github.io",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Vary": "Origin",
  };
}

function json(
  req: Request,
  payload: Record<string, unknown>,
  status = 200,
  extraHeaders: Record<string, string> = {},
) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: {
      ...corsHeaders(req),
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
      ...extraHeaders,
    },
  });
}

export function createIdentifyFlowerHandler(dependencies: IdentifyFlowerDependencies) {
  const {
    createClient,
    env,
    fetch,
    scheduleTimeout,
    cancelTimeout,
  } = dependencies;

  async function deleteProviderIdentification(accessToken: unknown, apiKey: string) {
    const token = safeIdentifier(accessToken);
    if (!token || !/^[A-Za-z0-9_-]+$/.test(token)) return;

    const controller = new AbortController();
    const timeout = scheduleTimeout(() => controller.abort(), 3_000);
    try {
      await fetch(`https://plant.id/api/v3/identification/${encodeURIComponent(token)}`, {
        method: "DELETE",
        headers: { "Api-Key": apiKey },
        signal: controller.signal,
      });
    } catch {
      // Provider objects and access tokens are never stored by Rocio. Deletion
      // is best-effort because a cleanup outage must not discard the bounded,
      // normalized replay result finalized in PostgreSQL.
    } finally {
      cancelTimeout(timeout);
    }
  }

  return async (req: Request) => {
    if (req.method === "OPTIONS") {
      return new Response("ok", { headers: corsHeaders(req) });
    }
    if (req.method !== "POST") {
      return json(req, { error: "method_not_allowed" }, 405);
    }

    const authorization = req.headers.get("authorization");
    if (!authorization?.startsWith("Bearer ")) {
      return json(req, { error: "authentication_required" }, 401);
    }

    const supabaseUrl = env("SUPABASE_URL");
    const anonKey = env("SUPABASE_ANON_KEY");
    if (!supabaseUrl || !anonKey) {
      return json(req, { error: "service_not_configured" }, 503);
    }

    // The user's JWT remains attached only to the RLS-scoped client. It authenticates
    // the caller and invokes the quota RPC without granting server privileges.
    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: userData, error: userError } =
      await userClient.auth.getUser(authorization.slice(7));
    if (userError || !userData.user) {
      return json(req, { error: "invalid_session" }, 401);
    }

    const serviceRoleKey = env("SUPABASE_SERVICE_ROLE_KEY");
    const apiKey = env("PLANT_ID_API_KEY");
    if (!serviceRoleKey || !apiKey) {
      return json(req, { error: "service_not_configured" }, 503);
    }

    // This client is server-only and never receives user-controlled headers. Its
    // sole use in this handler is writing the protected scan_results audit row.
    const adminClient = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    let body: Record<string, unknown>;
    try {
      const parsedBody = await req.json();
      const parsedObject = safeObject(parsedBody);
      if (!parsedObject) {
        return json(req, { error: "invalid_json" }, 400);
      }
      body = parsedObject;
    } catch {
      return json(req, { error: "invalid_json" }, 400);
    }

    if (body.consent !== true) {
      return json(req, { error: "photo_consent_required" }, 400);
    }
    const hasRequestID = Object.prototype.hasOwnProperty.call(body, "request_id");
    // Rocio 1.0 did not send request_id. Keep those installed binaries
    // functional through rollout, while noting that a replay from an old
    // client cannot reuse this server-generated UUID after transport loss.
    const requestID = hasRequestID
      ? safeRequestID(body.request_id)
      : crypto.randomUUID();
    if (!requestID) {
      return json(req, { error: "invalid_request_id" }, 400);
    }
    const image = String(body.image || "").replace(/^data:image\/\w+;base64,/, "");
    if (!image) return json(req, { error: "missing_image" }, 400);
    if (image.length > maxImageChars) {
      return json(req, { error: "image_too_large" }, 413);
    }
    const locale = safeLocale(body.locale || body.language);

    const { data: claimData, error: claimError } =
      await userClient.rpc("begin_scan_request", { p_request_id: requestID });
    const claim = Array.isArray(claimData)
      ? claimData[0] as ScanClaim | undefined
      : undefined;
    if (claimError || !claim) {
      return json(req, { error: "quota_unavailable" }, 503);
    }
    const quota = safeInteger(claim.quota);
    const remaining = safeInteger(claim.remaining);

    if (claim.claim_status === "replay") {
      const replayPayload = safeObject(claim.response_payload);
      const replayStatus = safeInteger(claim.http_status);
      const replayProviderCustomID = safeInteger(claim.provider_custom_id);
      if (!replayPayload || replayStatus === null ||
          replayStatus < 200 || replayStatus > 599 ||
          replayProviderCustomID === null || replayProviderCustomID <= 0) {
        return json(req, { error: "idempotency_unavailable" }, 503);
      }
      // Completion may have committed even when its HTTP response was lost.
      // A durable replay is the final opportunity to remove that provider
      // object without submitting or retrieving the photo again.
      await deleteProviderIdentification(replayProviderCustomID, apiKey);
      return json(req, replayPayload, replayStatus, {
        "X-Rocio-Idempotent-Replay": "true",
      });
    }
    if (claim.claim_status === "quota_exhausted") {
      return json(req, {
        error: "quota_exhausted",
        ...(quota === null ? {} : { quota }),
        remaining: 0,
      }, 429);
    }
    const providerCustomID = safeInteger(claim.provider_custom_id);
    const recoverPending = claim.claim_status === "recover";
    if (
      claim.claim_status !== "claimed" && !recoverPending ||
      quota === null ||
      remaining === null ||
      providerCustomID === null ||
      providerCustomID <= 0
    ) {
      return json(req, { error: "idempotency_unavailable" }, 503);
    }

    async function durableResponse(
      payload: Record<string, unknown>,
      status: number,
      audit: {
        topName?: string | null;
        confidence?: number | null;
        candidateCount?: number;
      } = {},
      cleanupIdentifier?: unknown,
    ) {
      const { data, error } = await adminClient.rpc("complete_scan_request", {
        p_user_id: userData.user.id,
        p_request_id: requestID,
        p_response_payload: payload,
        p_http_status: status,
        p_top_name: audit.topName ?? null,
        p_confidence: audit.confidence ?? null,
        p_candidate_count: audit.candidateCount ?? 0,
      });
      if (!error && data === false && cleanupIdentifier !== undefined) {
        // Account deletion can remove the ledger while Plant.id is still in
        // flight. A clean `false` is terminal (there is no row to recover), so
        // delete the now-known provider object before returning. RPC errors
        // remain recoverable and intentionally retain the provider object.
        await deleteProviderIdentification(cleanupIdentifier, apiKey);
      }
      if (error || data !== true) {
        return json(req, {
          error: status === 200
            ? "scan_result_unavailable"
            : "idempotency_unavailable",
          remaining,
        }, 503);
      }
      // Finalize the bounded replay record and audit row before deleting the
      // provider copy. If finalization fails, a retry can recover by custom_id.
      if (cleanupIdentifier !== undefined) {
        await deleteProviderIdentification(cleanupIdentifier, apiKey);
      }
      return json(req, payload, status);
    }

    async function completedProviderResponse(
      providerData: Record<string, unknown>,
    ) {
      const cleanupIdentifier =
        providerData.access_token ?? providerCustomID;
      let normalized;
      try {
        normalized = normalizedProviderResult(providerData);
      } catch {
        return await durableResponse({
          error: "provider_unavailable",
          remaining,
        }, 502, {}, cleanupIdentifier);
      }
      const payload = boundReplayPayload({
        success: true,
        provider: "plant_id",
        locale,
        is_plant: normalized.isPlant,
        suggestions: normalized.suggestions,
        quota,
        remaining,
      });
      return await durableResponse(payload, 200, {
        topName: normalized.suggestions[0]?.scientific_name || null,
        confidence: normalized.suggestions[0]?.probability ?? null,
        candidateCount: normalized.suggestions.length,
      }, cleanupIdentifier);
    }

    function providerURL(identifier?: number) {
      const url = new URL(identifier === undefined
        ? "https://plant.id/api/v3/identification"
        : `https://plant.id/api/v3/identification/${identifier}`);
      url.searchParams.set(
        "details",
        "common_names,taxonomy,rank,synonyms",
      );
      url.searchParams.set("language", locale);
      return url;
    }

    if (recoverPending) {
      const controller = new AbortController();
      const timeout = scheduleTimeout(() => controller.abort(), 18_000);
      try {
        const response = await fetch(providerURL(providerCustomID), {
          method: "GET",
          headers: { "Api-Key": apiKey },
          signal: controller.signal,
        });
        if (response.status === 202) {
          return json(req, {
            error: "scan_in_progress",
            quota,
            remaining,
          }, 409, { "Retry-After": "2" });
        }
        if (response.status === 404 && claim.can_abandon === true) {
          return await durableResponse({
            error: "provider_unavailable",
            remaining,
          }, 502, {}, providerCustomID);
        }
        if (response.status === 404) {
          return json(req, {
            error: "scan_in_progress",
            quota,
            remaining,
          }, 409, { "Retry-After": "2" });
        }
        if (!response.ok) {
          return json(req, {
            error: "provider_unavailable",
            remaining,
          }, 502);
        }
        const providerData = safeObject(await response.json()) ?? {};
        return await completedProviderResponse(providerData);
      } catch (error) {
        const code = error instanceof Error && error.name === "AbortError"
          ? "provider_timeout"
          : "provider_unavailable";
        return json(req, { error: code, remaining }, 502);
      } finally {
        cancelTimeout(timeout);
      }
    }

    const controller = new AbortController();
    const timeout = scheduleTimeout(() => controller.abort(), 18_000);
    let response: Response;
    let providerData: Record<string, unknown>;
    try {
      response = await fetch(providerURL(), {
        method: "POST",
        headers: { "Content-Type": "application/json", "Api-Key": apiKey },
        body: JSON.stringify({
          images: [image],
          classification_level: "all",
          custom_id: providerCustomID,
        }),
        signal: controller.signal,
      });
      providerData = response.ok
        ? safeObject(await response.json()) ?? {}
        : {};
    } catch (error) {
      const code = error instanceof Error && error.name === "AbortError"
        ? "provider_timeout"
        : "provider_unavailable";
      // The provider may have accepted a timed-out request. Leave the claim
      // pending so the next retry retrieves by custom_id instead of POSTing twice.
      return json(req, { error: code, remaining }, 502);
    } finally {
      cancelTimeout(timeout);
    }

    if (!response.ok) {
      return await durableResponse({
        error: "provider_unavailable",
        remaining,
      }, 502, {}, providerCustomID);
    }
    return await completedProviderResponse(providerData);
  };
}
