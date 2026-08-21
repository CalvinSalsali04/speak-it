/**
 * Chooses what the dashboard renders: real PostHog numbers, or clearly
 * labelled preview data.
 *
 * The rule this file enforces: preview and live numbers are never mixed. In
 * live mode any metric PostHog cannot answer renders as `null` (shown as "—"),
 * never as a demo value. A founder must never read a fabricated number as real
 * business performance.
 */
import type { DashboardMode, DashboardSnapshot, RangeKey } from "./dashboard-data";
import { snapshots as previewSnapshots } from "./dashboard-data";
import { fetchLiveMetrics, readPostHogConfig, type LiveMetrics } from "./posthog";

export type DashboardView = {
  mode: DashboardMode;
  snapshots: Record<RangeKey, DashboardSnapshot>;
  /** True when PostHog answered but has not received any events yet. */
  awaitingFirstEvents: boolean;
};

const RANGE_KEYS: RangeKey[] = ["7d", "30d", "90d", "all"];

const RANGE_LABELS: Record<RangeKey, string> = {
  "7d": "Last 7 days",
  "30d": "Last 30 days",
  "90d": "Last 90 days",
  all: "All time",
};

const RANGE_COMPARISONS: Record<RangeKey, string> = {
  "7d": "No prior period to compare yet",
  "30d": "No prior period to compare yet",
  "90d": "No prior period to compare yet",
  all: "Everyone who has ever opened Speak It",
};

function percent(numerator: number, denominator: number): number {
  if (denominator <= 0) return 0;
  return (numerator / denominator) * 100;
}

function formatPercent(numerator: number, denominator: number): string {
  if (denominator <= 0) return "—";
  return `${percent(numerator, denominator).toFixed(1)}%`;
}

function formatRatio(numerator: number, denominator: number): string {
  if (denominator <= 0) return "—";
  return (numerator / denominator).toFixed(1);
}

function roundedPercent(numerator: number, denominator: number): number {
  return Math.round(percent(numerator, denominator));
}

/**
 * Maps raw PostHog counters onto the shape the UI renders.
 *
 * Revenue, acquisition, retention cohorts, and crash-free rate are absent on
 * purpose: PostHog cannot answer them from this app's content-free event
 * vocabulary. They stay `null` until App Store Connect is connected.
 */
function toLiveSnapshot(range: RangeKey, metrics: LiveMetrics): DashboardSnapshot {
  const captureAttempts = metrics.capturesSaved + metrics.capturesFailed;

  return {
    label: RANGE_LABELS[range],
    // Period-over-period comparison needs a second window of queries. Until
    // that exists, claiming a comparison would be inventing one.
    comparison: RANGE_COMPARISONS[range],
    kpis: {
      mrr: null,
      mrrDelta: null,
      paid: metrics.paidUsers,
      paidDelta: null,
      trials: metrics.trialUsers,
      trialsDelta: null,
      newUsers: metrics.newUsers,
      newUsersDelta: null,
    },
    usefulLoop: Number(percent(metrics.usefulLoopUsers, metrics.newUsers).toFixed(1)),
    usefulLoopDelta: null,
    funnel: [
      {
        label: "New users",
        value: metrics.newUsers,
        rate: metrics.newUsers > 0 ? "100%" : "—",
      },
      {
        label: "First capture",
        value: metrics.firstCaptureUsers,
        rate: formatPercent(metrics.firstCaptureUsers, metrics.newUsers),
      },
      {
        label: "Useful loop",
        value: metrics.usefulLoopUsers,
        rate: formatPercent(metrics.usefulLoopUsers, metrics.firstCaptureUsers),
      },
      {
        label: "Trial started",
        value: metrics.trialUsers,
        rate: formatPercent(metrics.trialUsers, metrics.usefulLoopUsers),
      },
      {
        label: "Became paid",
        value: metrics.paidUsers,
        rate: formatPercent(metrics.paidUsers, metrics.trialUsers),
      },
    ],
    activity: {
      dau: metrics.dau,
      wau: metrics.wau,
      mau: metrics.mau,
      sessions: formatRatio(metrics.opens, metrics.activeUsers),
      captures: formatRatio(metrics.capturesSaved, metrics.capturingUsers),
      completion: formatPercent(metrics.tasksCompleted, metrics.tasksTouched),
    },
    retention: null,
    acquisition: null,
    lifecycle: [
      { label: "Paid", value: metrics.lifecycle.paid, detail: "Active subscription" },
      {
        label: "Hit the free limit",
        value: metrics.lifecycle.limitReached,
        detail: "Used all 10 captures",
      },
      { label: "Habitual", value: metrics.lifecycle.habitual, detail: "Reached the useful loop" },
      { label: "Activated", value: metrics.lifecycle.activated, detail: "Captured at least once" },
      {
        label: "Installed only",
        value: metrics.lifecycle.installedOnly,
        detail: "No capture yet",
      },
    ],
    profilesCreated: metrics.profilesCreated,
    trialConversion: roundedPercent(metrics.paidUsers, metrics.trialUsers),
    planMix: {
      monthly: roundedPercent(
        metrics.monthlyUsers,
        metrics.monthlyUsers + metrics.annualUsers,
      ),
      annual: roundedPercent(
        metrics.annualUsers,
        metrics.monthlyUsers + metrics.annualUsers,
      ),
    },
    revenue: { proceeds: null, churn: null, refunds: null, ltv: null },
    product: [
      {
        label: "Capture success",
        value: formatPercent(metrics.capturesSaved, captureAttempts),
        detail: "Voice or typed captures saved",
        tone: "good",
      },
      {
        label: "Needs review",
        value: formatPercent(metrics.needsReviewItems, metrics.capturedItems),
        detail: "Captured items needing user correction",
        tone: "watch",
      },
      {
        label: "Memory reuse",
        value: formatPercent(metrics.memoryUsers, metrics.activeUsers),
        detail: "Active users returning to a saved memory",
        tone: "neutral",
      },
    ],
  };
}

/** True when PostHog is reachable but has not seen a single event yet. */
function isEmpty(metrics: LiveMetrics): boolean {
  return (
    metrics.newUsers === 0 &&
    metrics.activeUsers === 0 &&
    metrics.capturesSaved === 0 &&
    metrics.opens === 0
  );
}

export async function buildDashboardView(): Promise<DashboardView> {
  const config = await readPostHogConfig();

  if (!config) {
    return {
      mode: "preview",
      snapshots: previewSnapshots,
      awaitingFirstEvents: false,
    };
  }

  const results = await Promise.all(
    RANGE_KEYS.map((range) => fetchLiveMetrics(config, range)),
  );

  // A partial answer is not trustworthy enough to render as real. If any range
  // failed, show preview data and say the connection did not answer.
  if (results.some((metrics) => metrics === null)) {
    return {
      mode: "unreachable",
      snapshots: previewSnapshots,
      awaitingFirstEvents: false,
    };
  }

  const liveMetrics = results as LiveMetrics[];
  const live = {} as Record<RangeKey, DashboardSnapshot>;
  RANGE_KEYS.forEach((range, index) => {
    live[range] = toLiveSnapshot(range, liveMetrics[index]);
  });

  return {
    mode: "live",
    snapshots: live,
    awaitingFirstEvents: liveMetrics.every(isEmpty),
  };
}
