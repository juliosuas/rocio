import assert from "node:assert/strict";
import test from "node:test";

import {
  createIdentifyFlowerHandler,
  type SupabaseClientLike,
} from "./handler.ts";

type ClaimRow = {
  claim_status: string;
  quota?: number | null;
  remaining?: number | null;
  response_payload?: Record<string, unknown> | null;
  http_status?: number | null;
  provider_custom_id?: number | null;
  can_abandon?: boolean;
};

type HarnessOptions = {
  user?: { id: string } | null;
  userError?: unknown;
  claimRows?: ClaimRow[] | null;
  claimError?: unknown;
  completionError?: unknown;
  completionFailures?: number;
  completionCommitsBeforeError?: boolean;
  completionData?: boolean;
  providerData?: Record<string, unknown>;
  providerStatus?: number;
  providerError?: Error;
  providerBodyError?: Error;
  cleanupError?: Error;
  environment?: Partial<Record<string, string | undefined>>;
};

type FetchCall = {
  url: string;
  method: string;
  body?: string;
};

const requestID = "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee";
const defaultEnvironment = {
  SUPABASE_URL: "https://example.supabase.co",
  SUPABASE_ANON_KEY: "anon-key",
  SUPABASE_SERVICE_ROLE_KEY: "server-key",
  PLANT_ID_API_KEY: "provider-key",
};

function makeHarness(options: HarnessOptions = {}) {
  const fetchCalls: FetchCall[] = [];
  const claimCalls: Array<Record<string, unknown>> = [];
  const completionCalls: Array<Record<string, unknown>> = [];
  const clientCreations: Array<{
    key: string;
    options: Record<string, unknown>;
  }> = [];
  const cancelledTimers: unknown[] = [];
  let timerID = 0;
  let quotaConsumptions = 0;
  let ledger: {
    state: "pending" | "completed";
    response?: Record<string, unknown>;
    status?: number;
  } | null = null;

  const userClient: SupabaseClientLike = {
    auth: {
      getUser: async () => ({
        data: {
          user: options.user === undefined
            ? { id: "user-123" }
            : options.user,
        },
        error: options.userError ?? null,
      }),
    },
    rpc: async (name, arguments_ = {}) => {
      assert.equal(name, "begin_scan_request");
      claimCalls.push(arguments_);
      if (options.claimError) {
        return { data: null, error: options.claimError };
      }
      if (options.claimRows !== undefined) {
        return { data: options.claimRows, error: null };
      }
      if (ledger?.state === "completed") {
        return {
          data: [{
            claim_status: "replay",
            quota: 5,
            remaining: 4,
            response_payload: ledger.response,
            http_status: ledger.status,
            provider_custom_id: 7001,
          }],
          error: null,
        };
      }
      if (ledger?.state === "pending") {
        return {
          data: [{
            claim_status: "recover",
            quota: 5,
            remaining: 4,
            provider_custom_id: 7001,
            can_abandon: false,
          }],
          error: null,
        };
      }

      ledger = { state: "pending" };
      quotaConsumptions += 1;
      return {
        data: [{
          claim_status: "claimed",
          quota: 5,
          remaining: 4,
          provider_custom_id: 7001,
        }],
        error: null,
      };
    },
  };

  const adminClient: SupabaseClientLike = {
    auth: {
      getUser: async () => ({ data: { user: null }, error: null }),
    },
    rpc: async (name, arguments_ = {}) => {
      assert.equal(name, "complete_scan_request");
      completionCalls.push(arguments_);
      if (options.completionCommitsBeforeError) {
        ledger = {
          state: "completed",
          response: arguments_.p_response_payload as Record<string, unknown>,
          status: arguments_.p_http_status as number,
        };
        return {
          data: null,
          error: new Error("completion response lost"),
        };
      }
      if (
        options.completionError ||
        completionCalls.length <= (options.completionFailures ?? 0)
      ) {
        return { data: null, error: options.completionError };
      }
      if (options.completionData === false) {
        return { data: false, error: null };
      }
      ledger = {
        state: "completed",
        response: arguments_.p_response_payload as Record<string, unknown>,
        status: arguments_.p_http_status as number,
      };
      return { data: true, error: null };
    },
  };

  const environment = { ...defaultEnvironment, ...options.environment };
  const handler = createIdentifyFlowerHandler({
    createClient: (_url, key, clientOptions) => {
      clientCreations.push({
        key,
        options: clientOptions as Record<string, unknown>,
      });
      return key === environment.SUPABASE_ANON_KEY ? userClient : adminClient;
    },
    env: (name) => environment[name as keyof typeof environment],
    fetch: async (input, init = {}) => {
      const url = String(input);
      const method = init.method ?? "GET";
      fetchCalls.push({
        url,
        method,
        body: typeof init.body === "string" ? init.body : undefined,
      });

      if (method === "DELETE") {
        if (options.cleanupError) throw options.cleanupError;
        return new Response(null, { status: 204 });
      }
      if (options.providerError) throw options.providerError;
      const response = new Response(JSON.stringify(options.providerData ?? {
        result: {
          classification: { suggestions: [] },
          is_plant: { binary: true, probability: 0.9, threshold: 0.5 },
        },
      }), {
        status: options.providerStatus ?? 200,
        headers: { "Content-Type": "application/json" },
      });
      if (options.providerBodyError) {
        Object.defineProperty(response, "json", {
          value: async () => {
            throw options.providerBodyError;
          },
        });
      }
      return response;
    },
    scheduleTimeout: () => ++timerID,
    cancelTimeout: (handle) => cancelledTimers.push(handle),
  });

  return {
    handler,
    fetchCalls,
    claimCalls,
    completionCalls,
    clientCreations,
    cancelledTimers,
    get quotaConsumptions() {
      return quotaConsumptions;
    },
  };
}

function scanBody(overrides: Record<string, unknown> = {}) {
  return {
    request_id: requestID,
    consent: true,
    image: "abc",
    ...overrides,
  };
}

function postRequest(
  body: unknown,
  authorization: string | null = "Bearer session-token",
) {
  const headers = new Headers({ "Content-Type": "application/json" });
  if (authorization !== null) headers.set("Authorization", authorization);
  return new Request("https://edge.example/identify-flower", {
    method: "POST",
    headers,
    body: typeof body === "string" ? body : JSON.stringify(body),
  });
}

async function bodyOf(response: Response) {
  return await response.json() as Record<string, unknown>;
}

test("handles preflight, unsupported methods, and missing authentication before dependencies", async () => {
  const harness = makeHarness();

  const preflight = await harness.handler(new Request(
    "https://edge.example/identify-flower",
    {
      method: "OPTIONS",
      headers: { Origin: "https://juliosuas.github.io" },
    },
  ));
  assert.equal(preflight.status, 200);
  assert.equal(
    preflight.headers.get("access-control-allow-origin"),
    "https://juliosuas.github.io",
  );

  const method = await harness.handler(new Request(
    "https://edge.example/identify-flower",
    { method: "GET" },
  ));
  assert.equal(method.status, 405);
  assert.deepEqual(await bodyOf(method), { error: "method_not_allowed" });

  const unauthenticated = await harness.handler(postRequest(scanBody(), null));
  assert.equal(unauthenticated.status, 401);
  assert.deepEqual(await bodyOf(unauthenticated), {
    error: "authentication_required",
  });
  assert.equal(harness.clientCreations.length, 0);
});

test("rejects an invalid session before parsing or sending the photo", async () => {
  const harness = makeHarness({ user: null });
  const response = await harness.handler(postRequest("not-json"));

  assert.equal(response.status, 401);
  assert.deepEqual(await bodyOf(response), { error: "invalid_session" });
  assert.equal(harness.fetchCalls.length, 0);
  assert.equal(harness.clientCreations.length, 1);
});

test("rejects invalid JSON, consent, request IDs, images, and oversized input", async () => {
  const cases: Array<{
    body: unknown;
    status: number;
    error: string;
  }> = [
    { body: "{", status: 400, error: "invalid_json" },
    {
      body: scanBody({ consent: false }),
      status: 400,
      error: "photo_consent_required",
    },
    {
      body: null,
      status: 400,
      error: "invalid_json",
    },
    {
      body: [scanBody()],
      status: 400,
      error: "invalid_json",
    },
    {
      body: { consent: true, image: "abc", request_id: null },
      status: 400,
      error: "invalid_request_id",
    },
    {
      body: scanBody({ request_id: "not-a-uuid" }),
      status: 400,
      error: "invalid_request_id",
    },
    {
      body: scanBody({ image: "" }),
      status: 400,
      error: "missing_image",
    },
    {
      body: scanBody({ image: "x".repeat(8 * 1024 * 1024 + 1) }),
      status: 413,
      error: "image_too_large",
    },
  ];

  for (const fixture of cases) {
    const harness = makeHarness();
    const response = await harness.handler(postRequest(fixture.body));
    assert.equal(response.status, fixture.status);
    assert.deepEqual(await bodyOf(response), { error: fixture.error });
    assert.equal(harness.fetchCalls.length, 0);
    assert.equal(harness.claimCalls.length, 0);
  }
});

test("keeps Rocio 1.0 bodies working with a server-generated request UUID", async () => {
  const harness = makeHarness();
  const response = await harness.handler(postRequest({
    consent: true,
    image: "abc",
  }));

  assert.equal(response.status, 200);
  assert.equal(harness.claimCalls.length, 1);
  const generated = harness.claimCalls[0].p_request_id;
  assert.equal(typeof generated, "string");
  assert.match(
    generated as string,
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/,
  );
  assert.equal(harness.completionCalls[0].p_request_id, generated);
});

test("fails closed when the atomic claim is unavailable or quota is exhausted", async (context) => {
  await context.test("claim RPC error", async () => {
    const harness = makeHarness({ claimError: new Error("database unavailable") });
    const response = await harness.handler(postRequest(scanBody()));
    assert.equal(response.status, 503);
    assert.deepEqual(await bodyOf(response), { error: "quota_unavailable" });
    assert.equal(harness.fetchCalls.length, 0);
  });

  await context.test("empty claim result", async () => {
    const harness = makeHarness({ claimRows: [] });
    const response = await harness.handler(postRequest(scanBody()));
    assert.equal(response.status, 503);
    assert.deepEqual(await bodyOf(response), { error: "quota_unavailable" });
    assert.equal(harness.fetchCalls.length, 0);
  });

  await context.test("quota exhausted", async () => {
    const harness = makeHarness({
      claimRows: [{
        claim_status: "quota_exhausted",
        quota: 5,
        remaining: 0,
        http_status: 429,
      }],
    });
    const response = await harness.handler(postRequest(scanBody()));
    assert.equal(response.status, 429);
    assert.deepEqual(await bodyOf(response), {
      error: "quota_exhausted",
      quota: 5,
      remaining: 0,
    });
    assert.equal(harness.fetchCalls.length, 0);
  });
});

test("a completed request replays without a second quota charge or provider call", async () => {
  const harness = makeHarness({
    providerData: {
      result: {
        classification: {
          suggestions: [{
            id: "plant-1",
            name: "Monstera",
            probability: 0.8,
            details: { scientific_name: "Monstera deliciosa" },
          }],
        },
        is_plant: { binary: true, probability: 0.9, threshold: 0.5 },
      },
    },
  });

  const first = await harness.handler(postRequest(scanBody()));
  const firstBody = await bodyOf(first);
  const retry = await harness.handler(postRequest(scanBody({ image: "different" })));
  const retryBody = await bodyOf(retry);

  assert.equal(first.status, 200);
  assert.equal(retry.status, 200);
  assert.deepEqual(retryBody, firstBody);
  assert.equal(retry.headers.get("x-rocio-idempotent-replay"), "true");
  assert.equal(harness.quotaConsumptions, 1);
  assert.equal(harness.claimCalls.length, 2);
  assert.deepEqual(harness.claimCalls[0], { p_request_id: requestID });
  assert.equal(
    harness.fetchCalls.filter((call) => call.method === "POST").length,
    1,
  );
  assert.equal(harness.completionCalls.length, 1);
});

test("an in-flight duplicate checks Plant.id by custom_id without a second POST", async () => {
  const harness = makeHarness({
    providerStatus: 404,
    claimRows: [{
      claim_status: "recover",
      quota: 5,
      remaining: 4,
      provider_custom_id: 7001,
      can_abandon: false,
    }],
  });
  const response = await harness.handler(postRequest(scanBody()));

  assert.equal(response.status, 409);
  assert.deepEqual(await bodyOf(response), {
    error: "scan_in_progress",
    quota: 5,
    remaining: 4,
  });
  assert.equal(response.headers.get("retry-after"), "2");
  assert.equal(harness.fetchCalls.length, 1);
  assert.equal(harness.fetchCalls[0].method, "GET");
  assert.ok(harness.fetchCalls[0].url.includes("/identification/7001"));
  assert.equal(harness.completionCalls.length, 0);
});

test("a Plant.id 202 remains pending without finalization or cleanup", async () => {
  const harness = makeHarness({
    providerStatus: 202,
    providerData: { status: "processing" },
    claimRows: [{
      claim_status: "recover",
      quota: 5,
      remaining: 4,
      provider_custom_id: 7001,
      can_abandon: false,
    }],
  });
  const response = await harness.handler(postRequest(scanBody()));

  assert.equal(response.status, 409);
  assert.deepEqual(await bodyOf(response), {
    error: "scan_in_progress",
    quota: 5,
    remaining: 4,
  });
  assert.equal(response.headers.get("retry-after"), "2");
  assert.equal(harness.fetchCalls.length, 1);
  assert.equal(harness.fetchCalls[0].method, "GET");
  assert.equal(harness.completionCalls.length, 0);
  assert.equal(
    harness.fetchCalls.some((call) => call.method === "DELETE"),
    false,
  );
});

test("a pending request recovers the provider result by custom_id", async () => {
  const harness = makeHarness({
    claimRows: [{
      claim_status: "recover",
      quota: 5,
      remaining: 4,
      provider_custom_id: 7001,
      can_abandon: false,
    }],
    providerData: {
      access_token: "recovered-token",
      result: {
        classification: {
          suggestions: [{
            id: "plant-1",
            name: "Monstera",
            probability: 0.8,
            details: { scientific_name: "Monstera deliciosa" },
          }],
        },
        is_plant: { binary: true, probability: 0.9, threshold: 0.5 },
      },
    },
  });
  const response = await harness.handler(postRequest(scanBody()));

  assert.equal(response.status, 200);
  assert.equal((await bodyOf(response)).success, true);
  assert.equal(
    harness.fetchCalls.filter((call) => call.method === "POST").length,
    0,
  );
  assert.equal(harness.fetchCalls[0].method, "GET");
  assert.equal(harness.fetchCalls[1].method, "DELETE");
  assert.equal(harness.completionCalls.length, 1);
});

test("an old 404 claim is terminally abandoned and cleaned up without a second POST", async () => {
  const harness = makeHarness({
    providerStatus: 404,
    providerBodyError: new SyntaxError("non-JSON provider error"),
    claimRows: [{
      claim_status: "recover",
      quota: 5,
      remaining: 4,
      provider_custom_id: 7001,
      can_abandon: true,
    }],
  });
  const response = await harness.handler(postRequest(scanBody()));

  assert.equal(response.status, 502);
  assert.deepEqual(await bodyOf(response), {
    error: "provider_unavailable",
    remaining: 4,
  });
  assert.equal(
    harness.fetchCalls.filter((call) => call.method === "POST").length,
    0,
  );
  assert.equal(harness.fetchCalls[0].method, "GET");
  assert.equal(harness.fetchCalls[1].method, "DELETE");
  assert.equal(harness.completionCalls.length, 1);
  assert.equal(harness.completionCalls[0].p_http_status, 502);
});

test("returns bounded arbitrary-plant identity data and cleans up the provider result", async () => {
  const longText = "x".repeat(240);
  const taxonomy = Object.fromEntries(
    Array.from({ length: 18 }, (_, index) => [
      `rank-${index}-${"k".repeat(90)}`,
      `${longText}-${index}`,
    ]),
  );
  const richSuggestion = {
    id: 42,
    name: `  ${longText}  `,
    probability: 9,
    details: {
      scientific_name: `  ${longText}  `,
      common_names: Array.from({ length: 18 }, (_, index) => ` common-${index} `),
      synonyms: Array.from({ length: 18 }, (_, index) => ` synonym-${index} `),
      rank: `  ${"r".repeat(100)}  `,
      taxonomy,
    },
  };
  const blankIdentitySuggestion = {
    id: "   ",
    name: "Monstera",
    probability: -1,
    rank: "   ",
    details: { scientific_name: "Monstera deliciosa" },
  };
  const harness = makeHarness({
    providerData: {
      access_token: "cleanup_token-123",
      result: {
        classification: {
          suggestions: [
            richSuggestion,
            blankIdentitySuggestion,
            ...Array.from({ length: 8 }, (_, index) => ({
              id: `plant-${index}`,
              name: `Plant ${index}`,
              probability: 0.5,
            })),
          ],
        },
        is_plant: {
          binary: "yes",
          probability: 4,
          threshold: -2,
        },
      },
    },
  });

  const response = await harness.handler(postRequest(scanBody({
    image: "data:image/jpeg;base64,aGVsbG8=",
    locale: "es-MX",
  })));
  const body = await bodyOf(response);

  assert.equal(response.status, 200);
  assert.equal(body.success, true);
  assert.equal(body.provider, "plant_id");
  assert.equal(body.locale, "es");
  assert.deepEqual(body.is_plant, {
    binary: null,
    probability: 1,
    threshold: 0,
  });

  const suggestions = body.suggestions as Array<Record<string, unknown>>;
  assert.equal(suggestions.length, 8);
  assert.equal(suggestions[0].id, "42");
  assert.equal((suggestions[0].name as string).length, 200);
  assert.equal((suggestions[0].scientific_name as string).length, 200);
  assert.equal((suggestions[0].rank as string).length, 80);
  assert.equal((suggestions[0].common_names as string[]).length, 16);
  assert.equal((suggestions[0].synonyms as string[]).length, 16);
  const boundedTaxonomy = suggestions[0].taxonomy as Record<string, string>;
  assert.equal(Object.keys(boundedTaxonomy).length, 16);
  assert.ok(Object.keys(boundedTaxonomy).every((key) => key.length <= 80));
  assert.ok(Object.values(boundedTaxonomy).every((value) => value.length <= 200));
  assert.equal("id" in suggestions[1], false);
  assert.equal("rank" in suggestions[1], false);
  assert.equal(suggestions[1].probability, 0);

  assert.equal(harness.fetchCalls[0].method, "POST");
  const providerURL = new URL(harness.fetchCalls[0].url);
  assert.equal(providerURL.searchParams.get("language"), "es");
  assert.equal(
    providerURL.searchParams.get("details"),
    "common_names,taxonomy,rank,synonyms",
  );
  assert.deepEqual(JSON.parse(harness.fetchCalls[0].body ?? "{}"), {
    images: ["aGVsbG8="],
    classification_level: "all",
    custom_id: 7001,
  });
  assert.equal(harness.fetchCalls[1].method, "DELETE");
  assert.ok(harness.fetchCalls[1].url.endsWith("/cleanup_token-123"));
  assert.equal(harness.completionCalls.length, 1);
  assert.deepEqual(harness.completionCalls[0], {
    p_user_id: "user-123",
    p_request_id: requestID,
    p_response_payload: body,
    p_http_status: 200,
    p_top_name: longText.slice(0, 200),
    p_confidence: 1,
    p_candidate_count: 8,
  });
  assert.equal(harness.cancelledTimers.length, 2);
});

test("preserves a valid no-plant result", async () => {
  const harness = makeHarness({
    providerData: {
      result: {
        classification: { suggestions: [] },
        is_plant: { binary: false, probability: 0.05, threshold: 0.5 },
      },
    },
  });
  const response = await harness.handler(postRequest(scanBody()));
  const body = await bodyOf(response);

  assert.equal(response.status, 200);
  assert.deepEqual(body.is_plant, {
    binary: false,
    probability: 0.05,
    threshold: 0.5,
  });
  assert.deepEqual(body.suggestions, []);
});

test("bounds the total multibyte replay payload before durable completion", async () => {
  const multibyte = "🌿".repeat(200);
  const suggestions = Array.from({ length: 8 }, (_, suggestionIndex) => ({
    id: `plant-${suggestionIndex}`,
    name: multibyte,
    probability: 0.9,
    details: {
      scientific_name: multibyte,
      common_names: Array.from({ length: 16 }, () => multibyte),
      synonyms: Array.from({ length: 16 }, () => multibyte),
      rank: multibyte,
      taxonomy: Object.fromEntries(
        Array.from({ length: 16 }, (_, index) => [
          `rank-${suggestionIndex}-${index}-${multibyte}`,
          multibyte,
        ]),
      ),
    },
  }));
  const harness = makeHarness({
    providerData: {
      result: {
        classification: { suggestions },
        is_plant: { binary: true, probability: 0.9, threshold: 0.5 },
      },
    },
  });

  const response = await harness.handler(postRequest(scanBody()));
  const body = await bodyOf(response);
  const encodedBytes = new TextEncoder().encode(JSON.stringify(body)).byteLength;

  assert.equal(response.status, 200);
  assert.ok(encodedBytes <= 112 * 1024);
  assert.equal(harness.completionCalls.length, 1);
  assert.ok(
    new TextEncoder().encode(JSON.stringify(
      harness.completionCalls[0].p_response_payload,
    )).byteLength <= 112 * 1024,
  );
  const bounded = body.suggestions as Array<Record<string, unknown>>;
  assert.equal(bounded.length, 8);
  assert.ok(bounded.some((suggestion) =>
    (suggestion.synonyms as unknown[]).length < 16
  ));
});

test("normalizes provider strings without NUL or broken surrogate boundaries", async () => {
  const boundaryText = `\u0000a${"🌿".repeat(250)}`;
  const harness = makeHarness({
    providerData: {
      result: {
        classification: {
          suggestions: [{
            id: `provider\u0000-${"🌿".repeat(250)}`,
            name: boundaryText,
            probability: 0.9,
            details: {
              scientific_name: boundaryText,
              taxonomy: {
                [`family\u0000-${"🌿".repeat(100)}`]: boundaryText,
              },
            },
          }],
        },
      },
    },
  });

  const response = await harness.handler(postRequest(scanBody()));
  const body = await bodyOf(response);
  const suggestion = (body.suggestions as Array<Record<string, unknown>>)[0];
  const name = suggestion.name as string;
  const providerID = suggestion.id as string;
  const taxonomy = suggestion.taxonomy as Record<string, string>;

  assert.equal(response.status, 200);
  assert.equal(name.includes("\u0000"), false);
  assert.equal(providerID.includes("\u0000"), false);
  assert.equal(Array.from(name).length, 200);
  assert.equal(Array.from(name).at(-1), "🌿");
  assert.doesNotThrow(() => encodeURIComponent(name));
  assert.doesNotThrow(() => encodeURIComponent(providerID));
  assert.ok(Object.entries(taxonomy).every(([key, value]) =>
    !key.includes("\u0000") &&
    !value.includes("\u0000") &&
    (() => {
      try {
        encodeURIComponent(key);
        encodeURIComponent(value);
        return true;
      } catch {
        return false;
      }
    })()
  ));
  const durableJSON = JSON.stringify(
    harness.completionCalls[0].p_response_payload,
  );
  assert.equal(durableJSON.includes("\\u0000"), false);
  assert.equal(durableJSON.includes("\\ud83c"), false);
});

test("provider cleanup failure does not discard a successful paid result", async () => {
  const harness = makeHarness({
    cleanupError: new Error("cleanup unavailable"),
    providerData: {
      access_token: "cleanup_token",
      result: {
        classification: {
          suggestions: [{
            id: "plant-1",
            name: "Monstera",
            probability: 0.8,
            details: { scientific_name: "Monstera deliciosa" },
          }],
        },
        is_plant: { binary: true, probability: 0.9, threshold: 0.5 },
      },
    },
  });

  const response = await harness.handler(postRequest(scanBody({
    language: "fr-FR",
  })));
  const body = await bodyOf(response);

  assert.equal(response.status, 200);
  assert.equal(body.success, true);
  assert.equal(body.locale, "en");
  assert.equal(
    harness.fetchCalls.filter((call) => call.method === "DELETE").length,
    1,
  );
  assert.equal(harness.completionCalls.length, 1);
});

test("keeps the provider timeout active through a stalled response body", async () => {
  const harness = makeHarness({
    providerBodyError: Object.assign(new Error("body aborted"), {
      name: "AbortError",
    }),
  });

  const response = await harness.handler(postRequest(scanBody()));

  assert.equal(response.status, 502);
  assert.deepEqual(await bodyOf(response), {
    error: "provider_timeout",
    remaining: 4,
  });
  assert.equal(harness.cancelledTimers.length, 1);
  assert.equal(harness.completionCalls.length, 0);
  assert.equal(
    harness.fetchCalls.some((call) => call.method === "DELETE"),
    false,
  );
});

test("leaves a recovered claim pending when its response body aborts", async () => {
  const harness = makeHarness({
    providerBodyError: Object.assign(new Error("recovery body aborted"), {
      name: "AbortError",
    }),
    claimRows: [{
      claim_status: "recover",
      quota: 5,
      remaining: 4,
      provider_custom_id: 7001,
      can_abandon: false,
    }],
  });

  const response = await harness.handler(postRequest(scanBody()));

  assert.equal(response.status, 502);
  assert.deepEqual(await bodyOf(response), {
    error: "provider_timeout",
    remaining: 4,
  });
  assert.equal(harness.fetchCalls[0].method, "GET");
  assert.equal(harness.completionCalls.length, 0);
  assert.equal(
    harness.fetchCalls.some((call) => call.method === "DELETE"),
    false,
  );
});

test("maps provider HTTP, malformed, timeout, and transport failures safely", async (context) => {
  const cases: Array<{
    name: string;
    options: HarnessOptions;
    error: string;
  }> = [
    {
      name: "provider non-OK",
      options: {
        providerStatus: 429,
        providerBodyError: new SyntaxError("non-JSON provider error"),
      },
      error: "provider_unavailable",
    },
    {
      name: "malformed provider classification",
      options: {
        providerData: {
          result: { classification: { suggestions: {} } },
        },
      },
      error: "provider_unavailable",
    },
    {
      name: "provider timeout",
      options: {
        providerError: Object.assign(new Error("aborted"), {
          name: "AbortError",
        }),
      },
      error: "provider_timeout",
    },
    {
      name: "provider transport unavailable",
      options: { providerError: new Error("network down") },
      error: "provider_unavailable",
    },
  ];

  for (const fixture of cases) {
    await context.test(fixture.name, async () => {
      const harness = makeHarness(fixture.options);
      const response = await harness.handler(postRequest(scanBody()));
      assert.equal(response.status, 502);
      assert.deepEqual(await bodyOf(response), {
        error: fixture.error,
        remaining: 4,
      });
      const uncertainTransport =
        fixture.name === "provider timeout" ||
        fixture.name === "provider transport unavailable";
      assert.equal(harness.completionCalls.length, uncertainTransport ? 0 : 1);
      if (!uncertainTransport) {
        assert.equal(harness.completionCalls[0].p_http_status, 502);
      }
    });
  }
});

test("fails closed when the atomic audit and replay finalization fails", async () => {
  const harness = makeHarness({
    completionError: new Error("audit insert failed"),
    providerData: {
      access_token: "cleanup_token",
      result: {
        classification: {
          suggestions: [{
            name: "Rose",
            probability: 0.7,
            details: { scientific_name: "Rosa" },
          }],
        },
      },
    },
  });
  const response = await harness.handler(postRequest(scanBody()));

  assert.equal(response.status, 503);
  assert.deepEqual(await bodyOf(response), {
    error: "scan_result_unavailable",
    remaining: 4,
  });
  assert.equal(harness.completionCalls.length, 1);
  assert.equal(
    harness.fetchCalls.some((call) => call.method === "DELETE"),
    false,
  );
});

test("cleans up a known provider object when account deletion removes the ledger", async () => {
  const harness = makeHarness({
    completionData: false,
    providerData: {
      access_token: "orphaned_after_account_delete",
      result: {
        classification: {
          suggestions: [{
            id: "plant-1",
            name: "Rose",
            probability: 0.7,
            details: { scientific_name: "Rosa" },
          }],
        },
      },
    },
  });

  const response = await harness.handler(postRequest(scanBody()));

  assert.equal(response.status, 503);
  assert.deepEqual(await bodyOf(response), {
    error: "scan_result_unavailable",
    remaining: 4,
  });
  assert.equal(harness.completionCalls.length, 1);
  assert.equal(
    harness.fetchCalls.filter((call) => call.method === "DELETE").length,
    1,
  );
  assert.ok(
    harness.fetchCalls.at(-1)?.url.endsWith(
      "/orphaned_after_account_delete",
    ),
  );
});

test("a finalization failure retries by provider GET without a second POST", async () => {
  const harness = makeHarness({
    completionFailures: 1,
    providerData: {
      access_token: "recover-after-database-error",
      result: {
        classification: {
          suggestions: [{
            id: "plant-1",
            name: "Rose",
            probability: 0.7,
            details: { scientific_name: "Rosa" },
          }],
        },
      },
    },
  });

  const first = await harness.handler(postRequest(scanBody()));
  const retry = await harness.handler(postRequest(scanBody()));

  assert.equal(first.status, 503);
  assert.equal(retry.status, 200);
  assert.equal(
    harness.fetchCalls.filter((call) => call.method === "POST").length,
    1,
  );
  assert.equal(
    harness.fetchCalls.filter((call) => call.method === "GET").length,
    1,
  );
  assert.equal(harness.fetchCalls.at(-1)?.method, "DELETE");
  assert.equal(harness.completionCalls.length, 2);

  const committedHarness = makeHarness({
    completionCommitsBeforeError: true,
    providerData: {
      result: {
        classification: {
          suggestions: [{
            id: "plant-1",
            name: "Rose",
            probability: 0.7,
            details: { scientific_name: "Rosa" },
          }],
        },
      },
    },
  });

  const committedFirst = await committedHarness.handler(
    postRequest(scanBody()),
  );
  const committedRetry = await committedHarness.handler(
    postRequest(scanBody()),
  );

  assert.equal(committedFirst.status, 503);
  assert.equal(committedRetry.status, 200);
  assert.equal(
    committedRetry.headers.get("X-Rocio-Idempotent-Replay"),
    "true",
  );
  assert.equal(
    committedHarness.fetchCalls.filter((call) => call.method === "POST")
      .length,
    1,
  );
  assert.equal(
    committedHarness.fetchCalls.filter((call) => call.method === "GET")
      .length,
    0,
  );
  const committedDeletes = committedHarness.fetchCalls.filter(
    (call) => call.method === "DELETE",
  );
  assert.equal(committedDeletes.length, 1);
  assert.ok(committedDeletes[0].url.endsWith("/7001"));
  assert.equal(committedHarness.completionCalls.length, 1);
  assert.equal(committedHarness.quotaConsumptions, 1);
});
