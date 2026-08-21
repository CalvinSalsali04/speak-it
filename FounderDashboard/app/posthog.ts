/**
 * Server-only PostHog reader for the founder dashboard.
 *
 * This module must never be imported from a `"use client"` file. It reads a
 * personal API key, and that key must not reach the browser.
 *
 * Every function fails soft. When PostHog is unconfigured, unreachable, slow,
 * or returns an unexpected shape, the caller keeps clearly labelled preview
 * data instead of rendering a wrong number as real business performance.
 */
import type { RangeKey } from "./dashboard-data";

/**
 * The time predicate for each range. "all" uses an always-true predicate so
 * every query keeps an identical shape rather than needing a variant with the
 * WHERE clause spliced out.
 */
const RANGE_WINDOWS: Record<RangeKey, string> = {
  "7d": "timestamp >= now() - INTERVAL 7 DAY",
  "30d": "timestamp >= now() - INTERVAL 30 DAY",
  "90d": "timestamp >= now() - INTERVAL 90 DAY",
  all: "true",
};

/**
 * Note the two different PostHog hosts. The iOS app *ingests* to
 * `us.i.posthog.com`; the query API this file reads lives on `us.posthog.com`.
 * Pointing POSTHOG_HOST at the ingestion host returns 404 for every query.
 */
const DEFAULT_QUERY_HOST = "https://us.posthog.com";
const QUERY_TIMEOUT_MS = 8_000;

export type PostHogConfig = {
  host: string;
  projectId: string;
  apiKey: string;
};

/** Raw counters read from PostHog. Ratios are derived later, not here. */
export type LiveMetrics = {
  newUsers: number;
  activeUsers: number;
  opens: number;
  capturingUsers: number;
  capturesSaved: number;
  capturesFailed: number;
  capturedItems: number;
  needsReviewItems: number;
  memoryUsers: number;
  tasksCompleted: number;
  tasksTouched: number;
  usefulLoopUsers: number;
  trialUsers: number;
  paidUsers: number;
  monthlyUsers: number;
  annualUsers: number;
  dau: number;
  wau: number;
  mau: number;
  firstCaptureUsers: number;
  profilesCreated: number;
  /** Mutually exclusive states. These sum to the number of active installs. */
  lifecycle: {
    paid: number;
    limitReached: number;
    habitual: number;
    activated: number;
    installedOnly: number;
  };
};

type EnvRecord = Record<string, unknown>;

/**
 * Reads config from the Cloudflare Worker binding first, then `process.env`.
 * The dynamic import keeps this file loadable outside a Worker (the Node test
 * runner imports the built bundle directly), where `cloudflare:workers` throws.
 */
async function readEnv(): Promise<EnvRecord> {
  const merged: EnvRecord = {};

  try {
    const workerModule = await import("cloudflare:workers");
    const workerEnv = (workerModule as { env?: EnvRecord }).env;
    if (workerEnv) Object.assign(merged, workerEnv);
  } catch {
    // Not running inside a Cloudflare Worker. Fall through to process.env.
  }

  try {
    if (typeof process !== "undefined" && process.env) {
      Object.assign(merged, process.env);
    }
  } catch {
    // No Node process global. Nothing further to read.
  }

  return merged;
}

function readString(source: EnvRecord, key: string): string | null {
  const value = source[key];
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

export async function readPostHogConfig(): Promise<PostHogConfig | null> {
  const source = await readEnv();

  const projectId = readString(source, "POSTHOG_PROJECT_ID");
  const apiKey = readString(source, "POSTHOG_API_KEY");
  if (!projectId || !apiKey) return null;

  // A project id is always numeric. Rejecting anything else keeps a typo from
  // being interpolated into the request path.
  if (!/^\d+$/.test(projectId)) return null;

  // Guard against pasting the ingestion key (`phc_…`) into the query slot.
  // The query API needs a personal API key, which PostHog prefixes `phx_`.
  if (apiKey.startsWith("phc_")) return null;

  const host = readString(source, "POSTHOG_HOST") ?? DEFAULT_QUERY_HOST;
  let parsedHost: URL;
  try {
    parsedHost = new URL(host);
  } catch {
    return null;
  }
  if (parsedHost.protocol !== "https:") return null;

  return {
    host: parsedHost.origin,
    projectId,
    apiKey,
  };
}

/** Runs one HogQL query. Returns `null` on any failure rather than throwing. */
async function runHogQL(
  config: PostHogConfig,
  query: string,
): Promise<unknown[][] | null> {
  try {
    const response = await fetch(
      `${config.host}/api/projects/${config.projectId}/query/`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${config.apiKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ query: { kind: "HogQLQuery", query } }),
        signal: AbortSignal.timeout(QUERY_TIMEOUT_MS),
      },
    );

    if (!response.ok) return null;

    const payload: unknown = await response.json();
    const results = (payload as { results?: unknown }).results;
    return Array.isArray(results) ? (results as unknown[][]) : null;
  } catch {
    // Network error, timeout, or malformed JSON. Caller falls back to preview.
    return null;
  }
}

function toCount(value: unknown): number {
  const parsed = typeof value === "string" ? Number(value) : value;
  if (typeof parsed !== "number" || !Number.isFinite(parsed) || parsed < 0) {
    return 0;
  }
  return parsed;
}

/**
 * One aggregate query per range.
 *
 * `distinct_id` is used rather than `person_id` on purpose: the iOS client
 * sends `$process_person_profile: false`, so there are no person profiles to
 * join against. The distinct id is an anonymous per-install UUID.
 *
 * The useful loop matches the definition shown in the UI: captured at least
 * twice, then completed a task or reopened a memory.
 */
function buildMetricsQuery(window: string): string {
  return `
SELECT
  uniqIf(distinct_id, event = 'app_installed') AS new_users,
  uniqIf(distinct_id, event = 'app_opened') AS active_users,
  countIf(event = 'app_opened') AS opens,
  uniqIf(distinct_id, event = 'capture_saved') AS capturing_users,
  countIf(event = 'capture_saved') AS captures_saved,
  countIf(event = 'capture_failed') AS captures_failed,
  sumIf(toFloat(properties.item_count), event = 'capture_saved') AS captured_items,
  sumIf(toFloat(properties.needs_review_count), event = 'capture_saved') AS needs_review_items,
  uniqIf(distinct_id, event = 'memory_collection_opened') AS memory_users,
  -- PostHog surfaces boolean properties as Nullable(String), so this must be
  -- compared to the literal 'true' rather than used as a bare condition.
  countIf(event = 'task_completion_changed' AND properties.completed = 'true') AS tasks_completed,
  countIf(event = 'task_completion_changed') AS tasks_touched,
  uniqIf(distinct_id, event = 'purchase_started') AS trial_users,
  uniqIf(distinct_id, event = 'purchase_completed') AS paid_users,
  uniqIf(distinct_id, event = 'purchase_completed' AND properties.plan = 'monthly') AS monthly_users,
  uniqIf(distinct_id, event = 'purchase_completed' AND properties.plan = 'annual') AS annual_users,
  uniqIf(distinct_id, event = 'app_opened' AND timestamp >= now() - INTERVAL 1 DAY) AS dau,
  uniqIf(distinct_id, event = 'app_opened' AND timestamp >= now() - INTERVAL 7 DAY) AS wau,
  uniqIf(distinct_id, event = 'app_opened' AND timestamp >= now() - INTERVAL 30 DAY) AS mau
FROM events
WHERE ${window}
  AND event IN (
    'app_installed', 'app_opened', 'capture_saved', 'capture_failed',
    'memory_collection_opened', 'task_completion_changed',
    'purchase_started', 'purchase_completed'
  )
`.trim();
}

function buildUsefulLoopQuery(window: string): string {
  return `
SELECT count() FROM (
  SELECT distinct_id
  FROM events
  WHERE ${window}
    AND event IN ('capture_saved', 'task_completion_changed', 'memory_collection_opened')
  GROUP BY distinct_id
  HAVING countIf(event = 'capture_saved') >= 2
     AND countIf(event IN ('task_completion_changed', 'memory_collection_opened')) >= 1
)
`.trim();
}

/**
 * Users whose first capture happened inside the window, used for the funnel
 * step between "new users" and "useful loop".
 */
function buildFirstCaptureQuery(window: string): string {
  return `
SELECT uniq(distinct_id)
FROM events
WHERE ${window}
  AND event = 'capture_saved'
`.trim();
}

/**
 * Buckets every install into exactly one lifecycle state, highest commitment
 * first, so the states are mutually exclusive and sum to the install count.
 */
function buildLifecycleQuery(window: string): string {
  return `
SELECT
  countIf(state = 'paid') AS paid,
  countIf(state = 'limit') AS limit_reached,
  countIf(state = 'habitual') AS habitual,
  countIf(state = 'activated') AS activated,
  countIf(state = 'installed') AS installed_only
FROM (
  SELECT
    distinct_id,
    multiIf(
      countIf(event = 'purchase_completed') > 0, 'paid',
      countIf(event = 'free_limit_reached') > 0, 'limit',
      countIf(event = 'capture_saved') >= 2
        AND countIf(event IN ('task_completion_changed', 'memory_collection_opened')) >= 1, 'habitual',
      countIf(event = 'capture_saved') >= 1, 'activated',
      'installed'
    ) AS state
  FROM events
  WHERE ${window}
  GROUP BY distinct_id
)
`.trim();
}

/** Installs that created the optional on-device profile. */
function buildProfilesQuery(window: string): string {
  return `
SELECT uniq(distinct_id)
FROM events
WHERE ${window}
  AND event = 'profile_created'
`.trim();
}

export async function fetchLiveMetrics(
  config: PostHogConfig,
  range: RangeKey,
): Promise<LiveMetrics | null> {
  const window = RANGE_WINDOWS[range];

  const [aggregate, usefulLoop, firstCapture, lifecycle, profiles] = await Promise.all([
    runHogQL(config, buildMetricsQuery(window)),
    runHogQL(config, buildUsefulLoopQuery(window)),
    runHogQL(config, buildFirstCaptureQuery(window)),
    runHogQL(config, buildLifecycleQuery(window)),
    runHogQL(config, buildProfilesQuery(window)),
  ]);

  const lifecycleRow = lifecycle?.[0] ?? [];

  const row = aggregate?.[0];
  if (!Array.isArray(row) || row.length < 18) return null;

  return {
    newUsers: toCount(row[0]),
    activeUsers: toCount(row[1]),
    opens: toCount(row[2]),
    capturingUsers: toCount(row[3]),
    capturesSaved: toCount(row[4]),
    capturesFailed: toCount(row[5]),
    capturedItems: toCount(row[6]),
    needsReviewItems: toCount(row[7]),
    memoryUsers: toCount(row[8]),
    tasksCompleted: toCount(row[9]),
    tasksTouched: toCount(row[10]),
    trialUsers: toCount(row[11]),
    paidUsers: toCount(row[12]),
    monthlyUsers: toCount(row[13]),
    annualUsers: toCount(row[14]),
    dau: toCount(row[15]),
    wau: toCount(row[16]),
    mau: toCount(row[17]),
    usefulLoopUsers: toCount(usefulLoop?.[0]?.[0]),
    firstCaptureUsers: toCount(firstCapture?.[0]?.[0]),
    profilesCreated: toCount(profiles?.[0]?.[0]),
    lifecycle: {
      paid: toCount(lifecycleRow[0]),
      limitReached: toCount(lifecycleRow[1]),
      habitual: toCount(lifecycleRow[2]),
      activated: toCount(lifecycleRow[3]),
      installedOnly: toCount(lifecycleRow[4]),
    },
  };
}
