import assert from "node:assert/strict";
import test from "node:test";

const OWNER_HEADERS = {
  accept: "text/html",
  "oai-authenticated-user-id": "user_test_owner",
  "oai-authenticated-user-email": "owner@example.com",
};

async function render(headers = OWNER_HEADERS) {
  const workerUrl = new URL("../dist/server/index.js", import.meta.url);
  workerUrl.searchParams.set("test", `${process.pid}-${Date.now()}`);
  const { default: worker } = await import(workerUrl.href);

  return worker.fetch(
    new Request("http://localhost/", { headers }),
    { ASSETS: { fetch: async () => new Response("Not found", { status: 404 }) } },
    { waitUntil() {}, passThroughOnException() {} },
  );
}

test("server-renders the Speak It founder dashboard for the owner", async () => {
  const response = await render();
  assert.equal(response.status, 200);
  assert.match(response.headers.get("content-type") ?? "", /^text\/html\b/i);

  const html = await response.text();
  assert.match(html, /<title>Speak It — Founder Dashboard<\/title>/i);
  assert.match(html, /Founder view/);
  assert.match(html, /The useful loop/);
  assert.match(html, /In trial now/);
  assert.match(html, /Active paid/);
  assert.match(html, /Private by design/);
  assert.match(html, /Preview data/);
  assert.doesNotMatch(html, /codex-preview|react-loading-skeleton|Your site is taking shape/i);
});

test("never serves metrics to an unauthenticated visitor", async () => {
  const response = await render({ accept: "text/html" });

  // The page must not render. It redirects to the platform sign-in instead.
  assert.notEqual(response.status, 200);
  assert.match(
    response.headers.get("location") ?? "",
    /^\/signin-with-chatgpt\?return_to=/,
  );
});

test("never leaks the PostHog key into the rendered page", async () => {
  const response = await render();
  const html = await response.text();

  // The query key is server-only. Neither it nor its env var name may appear
  // in markup shipped to the browser.
  assert.doesNotMatch(html, /phx_/);
  assert.doesNotMatch(html, /POSTHOG_API_KEY/);
});
