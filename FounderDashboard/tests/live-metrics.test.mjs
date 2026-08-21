/**
 * End-to-end verification of the live PostHog path without a PostHog account.
 *
 * The worker is rendered with POSTHOG_* set and `fetch` stubbed to return
 * canned query responses, which exercises config reading, request
 * construction, response parsing, metric derivation, and live rendering.
 *
 * What this cannot prove: that the HogQL itself is semantically correct
 * against a real project. Only a live project can answer that.
 */
import assert from "node:assert/strict";
import test from "node:test";

const OWNER_HEADERS = {
  accept: "text/html",
  "oai-authenticated-user-id": "user_test_owner",
  "oai-authenticated-user-email": "owner@example.com",
};

// One row of 18 aggregate counters, in the column order fetchLiveMetrics reads.
const AGGREGATE_ROW = [
  40,  // new_users
  35,  // active_users
  105, // opens
  28,  // capturing_users
  140, // captures_saved
  6,   // captures_failed
  200, // captured_items
  14,  // needs_review_items
  12,  // memory_users
  60,  // tasks_completed
  90,  // tasks_touched
  8,   // trial_users
  3,   // paid_users
  2,   // monthly_users
  1,   // annual_users
  9,   // dau
  22,  // wau
  35,  // mau
];

const USEFUL_LOOP_USERS = 15;
const FIRST_CAPTURE_USERS = 28;
const PROFILES_CREATED = 9;
// paid, limit_reached, habitual, activated, installed_only
const LIFECYCLE_ROW = [3, 5, 15, 13, 12];

function cannedResponseFor(query) {
  if (query.includes("new_users")) return { results: [AGGREGATE_ROW] };
  if (query.includes("multiIf")) return { results: [LIFECYCLE_ROW] };
  if (query.includes("profile_created")) return { results: [[PROFILES_CREATED]] };
  if (query.includes("HAVING")) return { results: [[USEFUL_LOOP_USERS]] };
  return { results: [[FIRST_CAPTURE_USERS]] };
}

/** Installs a fetch stub and records every request it receives. */
function stubPostHog({ status = 200 } = {}) {
  const calls = [];
  const original = globalThis.fetch;

  globalThis.fetch = async (url, init = {}) => {
    const body = JSON.parse(init.body ?? "{}");
    const query = body?.query?.query ?? "";
    calls.push({ url: `${url}`, headers: init.headers ?? {}, query });

    if (status !== 200) {
      return new Response("nope", { status });
    }
    return new Response(JSON.stringify(cannedResponseFor(query)), {
      status: 200,
      headers: { "content-type": "application/json" },
    });
  };

  return {
    calls,
    restore() {
      globalThis.fetch = original;
    },
  };
}

async function render() {
  const workerUrl = new URL("../dist/server/index.js", import.meta.url);
  workerUrl.searchParams.set("test", `${process.pid}-${Date.now()}-${Math.random()}`);
  const { default: worker } = await import(workerUrl.href);

  return worker.fetch(
    new Request("http://localhost/", { headers: OWNER_HEADERS }),
    { ASSETS: { fetch: async () => new Response("Not found", { status: 404 }) } },
    { waitUntil() {}, passThroughOnException() {} },
  );
}

function withPostHogEnv(fn) {
  return async (t) => {
    process.env.POSTHOG_PROJECT_ID = "12345";
    process.env.POSTHOG_API_KEY = "phx_test_personal_key";
    process.env.POSTHOG_HOST = "https://us.posthog.com";
    try {
      await fn(t);
    } finally {
      delete process.env.POSTHOG_PROJECT_ID;
      delete process.env.POSTHOG_API_KEY;
      delete process.env.POSTHOG_HOST;
    }
  };
}

test("renders live metrics derived from PostHog", withPostHogEnv(async () => {
  const posthog = stubPostHog();
  try {
    const response = await render();
    assert.equal(response.status, 200);
    const html = await response.text();

    assert.match(html, /Live data/);

    // Derived values, not raw counters: capture success 140/146, needs review
    // 14/200, memory reuse 12/35, useful loop 15/40.
    assert.match(html, /95\.9%/);
    assert.match(html, /7\.0%/);
    assert.match(html, /34\.3%/);
    assert.match(html, /37\.5/);

    // Ratios: opens/active = 3.0, captures/capturing = 5.0.
    assert.match(html, /3\.0/);
    assert.match(html, /5\.0/);

    // Raw counters that should surface directly.
    assert.match(html, /\b40\b/);

    // Lifecycle states render, and the total is their sum (3+5+15+13+12 = 48).
    assert.match(html, /Where everyone stands/);
    assert.match(html, /48 installs/);
    assert.match(html, /Hit the free limit/);
    assert.match(html, /Installed only/);
    assert.match(html, /9<\/b> created the optional on-device profile/);

    // Preview numbers must be completely absent in live mode.
    assert.doesNotMatch(html, /\$112/);
    assert.doesNotMatch(html, /\$164/);
    assert.doesNotMatch(html, /App Store search/);
  } finally {
    posthog.restore();
  }
}));

test("sends the personal key as a bearer token to the query API", withPostHogEnv(async () => {
  const posthog = stubPostHog();
  try {
    await render();

    // Five queries per range, four ranges (7d, 30d, 90d, all time).
    assert.equal(posthog.calls.length, 20);

    // All-time is expressed as an always-true predicate, not a window.
    const allTime = posthog.calls.filter((call) => /WHERE true\b/.test(call.query));
    assert.equal(allTime.length, 5);

    for (const call of posthog.calls) {
      assert.equal(call.url, "https://us.posthog.com/api/projects/12345/query/");
      assert.equal(call.headers.Authorization, "Bearer phx_test_personal_key");
      assert.equal(call.headers["Content-Type"], "application/json");
    }
  } finally {
    posthog.restore();
  }
}));

test("falls back to preview data when PostHog errors", withPostHogEnv(async () => {
  const posthog = stubPostHog({ status: 500 });
  try {
    const response = await render();
    assert.equal(response.status, 200);
    const html = await response.text();

    // A failed query must never render as real. Preview data returns, labelled.
    assert.match(html, /Preview data/);
    assert.match(html, /did not answer/);
    assert.match(html, /\$112/);
    assert.doesNotMatch(html, /Live data/);
  } finally {
    posthog.restore();
  }
}));

test("rejects an ingestion key pasted into the query slot", async () => {
  process.env.POSTHOG_PROJECT_ID = "12345";
  process.env.POSTHOG_API_KEY = "phc_this_is_the_wrong_key";
  const posthog = stubPostHog();
  try {
    const response = await render();
    const html = await response.text();

    // Config is rejected before any request is made.
    assert.equal(posthog.calls.length, 0);
    assert.match(html, /Preview data/);
  } finally {
    posthog.restore();
    delete process.env.POSTHOG_PROJECT_ID;
    delete process.env.POSTHOG_API_KEY;
  }
});
