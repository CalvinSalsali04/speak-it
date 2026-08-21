export type RangeKey = "7d" | "30d" | "90d" | "all";

/**
 * Which source the rendered numbers came from. Declared here, in a module with
 * no server imports, so the client component never has to reach into
 * `dashboard-source.ts` (which transitively reads the PostHog API key).
 */
export type DashboardMode = "preview" | "live" | "unreachable";

/**
 * `null` means "this metric has no real source connected yet" and renders as
 * "—". It never means zero. Preview snapshots below populate every field;
 * live snapshots leave the App-Store-only metrics null on purpose.
 */
export type DashboardSnapshot = {
  label: string;
  comparison: string;
  kpis: {
    mrr: string | null;
    mrrDelta: string | null;
    paid: number;
    paidDelta: string | null;
    trials: number;
    trialsDelta: string | null;
    newUsers: number;
    newUsersDelta: string | null;
  };
  usefulLoop: number;
  usefulLoopDelta: string | null;
  funnel: Array<{ label: string; value: number; rate: string }>;
  activity: {
    dau: number;
    wau: number;
    mau: number;
    sessions: string;
    captures: string;
    completion: string;
  };
  retention: Array<{ label: string; value: number }> | null;
  acquisition: Array<{ label: string; value: number }> | null;
  /** Mutually exclusive states, most committed first. Sums to active installs. */
  lifecycle: Array<{ label: string; value: number; detail: string }>;
  /** Installs that created the optional on-device profile. */
  profilesCreated: number;
  trialConversion: number;
  planMix: { monthly: number; annual: number };
  revenue: {
    proceeds: string | null;
    churn: string | null;
    refunds: string | null;
    ltv: string | null;
  };
  product: Array<{
    label: string;
    value: string;
    detail: string;
    tone: "good" | "watch" | "neutral";
  }>;
};

export const snapshots: Record<RangeKey, DashboardSnapshot> = {
  "7d": {
    label: "Last 7 days",
    comparison: "vs previous 7 days",
    kpis: {
      mrr: "$112",
      mrrDelta: "+8.7%",
      paid: 47,
      paidDelta: "+4",
      trials: 19,
      trialsDelta: "+3",
      newUsers: 38,
      newUsersDelta: "+12.1%",
    },
    usefulLoop: 41.2,
    usefulLoopDelta: "+4.8 pts",
    funnel: [
      { label: "New users", value: 38, rate: "100%" },
      { label: "First capture", value: 31, rate: "82%" },
      { label: "Useful loop", value: 18, rate: "58%" },
      { label: "Trial started", value: 8, rate: "44%" },
      { label: "Became paid", value: 4, rate: "50%" },
    ],
    activity: {
      dau: 42,
      wau: 151,
      mau: 374,
      sessions: "3.1",
      captures: "4.6",
      completion: "68%",
    },
    retention: [
      { label: "Day 1", value: 46 },
      { label: "Day 7", value: 31 },
      { label: "Day 28", value: 19 },
    ],
    acquisition: [
      { label: "App Store search", value: 44 },
      { label: "Direct / unknown", value: 29 },
      { label: "Shared by a friend", value: 17 },
      { label: "Other", value: 10 },
    ],
    trialConversion: 36,
    planMix: { monthly: 66, annual: 34 },
    revenue: { proceeds: "$79", churn: "3.8%", refunds: "0.6%", ltv: "$21" },
    lifecycle: [
      { label: "Paid", value: 4, detail: "Active subscription" },
      { label: "Hit the free limit", value: 6, detail: "Used all 10 captures" },
      { label: "Habitual", value: 18, detail: "Reached the useful loop" },
      { label: "Activated", value: 31, detail: "Captured at least once" },
      { label: "Installed only", value: 7, detail: "No capture yet" },
    ],
    profilesCreated: 12,
    product: [
      { label: "Capture success", value: "96.8%", detail: "Voice or typed captures saved", tone: "good" },
      { label: "Needs review", value: "7.4%", detail: "Captures needing user correction", tone: "watch" },
      { label: "Memory reuse", value: "28.1%", detail: "Users returning to a saved memory", tone: "neutral" },
      { label: "Crash-free", value: "99.7%", detail: "Sessions without a crash", tone: "good" },
    ],
  },
  "30d": {
    label: "Last 30 days",
    comparison: "vs previous 30 days",
    kpis: {
      mrr: "$112",
      mrrDelta: "+18.4%",
      paid: 47,
      paidDelta: "+11",
      trials: 19,
      trialsDelta: "+6",
      newUsers: 128,
      newUsersDelta: "+24.6%",
    },
    usefulLoop: 38.6,
    usefulLoopDelta: "+3.2 pts",
    funnel: [
      { label: "New users", value: 128, rate: "100%" },
      { label: "First capture", value: 103, rate: "80%" },
      { label: "Useful loop", value: 57, rate: "55%" },
      { label: "Trial started", value: 26, rate: "46%" },
      { label: "Became paid", value: 15, rate: "58%" },
    ],
    activity: {
      dau: 42,
      wau: 151,
      mau: 374,
      sessions: "2.8",
      captures: "4.3",
      completion: "66%",
    },
    retention: [
      { label: "Day 1", value: 44 },
      { label: "Day 7", value: 29 },
      { label: "Day 28", value: 18 },
    ],
    acquisition: [
      { label: "App Store search", value: 41 },
      { label: "Direct / unknown", value: 31 },
      { label: "Shared by a friend", value: 19 },
      { label: "Other", value: 9 },
    ],
    trialConversion: 34,
    planMix: { monthly: 68, annual: 32 },
    revenue: { proceeds: "$164", churn: "4.1%", refunds: "0.8%", ltv: "$19" },
    lifecycle: [
      { label: "Paid", value: 15, detail: "Active subscription" },
      { label: "Hit the free limit", value: 21, detail: "Used all 10 captures" },
      { label: "Habitual", value: 57, detail: "Reached the useful loop" },
      { label: "Activated", value: 103, detail: "Captured at least once" },
      { label: "Installed only", value: 25, detail: "No capture yet" },
    ],
    profilesCreated: 39,
    product: [
      { label: "Capture success", value: "96.1%", detail: "Voice or typed captures saved", tone: "good" },
      { label: "Needs review", value: "8.2%", detail: "Captures needing user correction", tone: "watch" },
      { label: "Memory reuse", value: "25.4%", detail: "Users returning to a saved memory", tone: "neutral" },
      { label: "Crash-free", value: "99.6%", detail: "Sessions without a crash", tone: "good" },
    ],
  },
  "90d": {
    label: "Last 90 days",
    comparison: "vs previous 90 days",
    kpis: {
      mrr: "$112",
      mrrDelta: "+42.0%",
      paid: 47,
      paidDelta: "+29",
      trials: 19,
      trialsDelta: "+9",
      newUsers: 349,
      newUsersDelta: "+38.2%",
    },
    usefulLoop: 35.8,
    usefulLoopDelta: "+6.1 pts",
    funnel: [
      { label: "New users", value: 349, rate: "100%" },
      { label: "First capture", value: 269, rate: "77%" },
      { label: "Useful loop", value: 143, rate: "53%" },
      { label: "Trial started", value: 69, rate: "48%" },
      { label: "Became paid", value: 37, rate: "54%" },
    ],
    activity: {
      dau: 42,
      wau: 151,
      mau: 374,
      sessions: "2.5",
      captures: "3.9",
      completion: "63%",
    },
    retention: [
      { label: "Day 1", value: 41 },
      { label: "Day 7", value: 26 },
      { label: "Day 28", value: 16 },
    ],
    acquisition: [
      { label: "App Store search", value: 38 },
      { label: "Direct / unknown", value: 34 },
      { label: "Shared by a friend", value: 18 },
      { label: "Other", value: 10 },
    ],
    trialConversion: 31,
    planMix: { monthly: 71, annual: 29 },
    revenue: { proceeds: "$391", churn: "4.8%", refunds: "1.1%", ltv: "$17" },
    lifecycle: [
      { label: "Paid", value: 37, detail: "Active subscription" },
      { label: "Hit the free limit", value: 52, detail: "Used all 10 captures" },
      { label: "Habitual", value: 143, detail: "Reached the useful loop" },
      { label: "Activated", value: 269, detail: "Captured at least once" },
      { label: "Installed only", value: 80, detail: "No capture yet" },
    ],
    profilesCreated: 104,
    product: [
      { label: "Capture success", value: "94.9%", detail: "Voice or typed captures saved", tone: "good" },
      { label: "Needs review", value: "9.6%", detail: "Captures needing user correction", tone: "watch" },
      { label: "Memory reuse", value: "22.7%", detail: "Users returning to a saved memory", tone: "neutral" },
      { label: "Crash-free", value: "99.4%", detail: "Sessions without a crash", tone: "good" },
    ],
  },
  all: {
    label: "All time",
    comparison: "Everyone who has ever opened Speak It",
    kpis: {
      mrr: "$112",
      mrrDelta: null,
      paid: 47,
      paidDelta: null,
      trials: 19,
      trialsDelta: null,
      newUsers: 512,
      newUsersDelta: null,
    },
    usefulLoop: 33.4,
    usefulLoopDelta: null,
    funnel: [
      { label: "New users", value: 512, rate: "100%" },
      { label: "First capture", value: 388, rate: "76%" },
      { label: "Useful loop", value: 171, rate: "44%" },
      { label: "Trial started", value: 94, rate: "55%" },
      { label: "Became paid", value: 47, rate: "50%" },
    ],
    activity: {
      dau: 42,
      wau: 151,
      mau: 374,
      sessions: "2.4",
      captures: "3.7",
      completion: "62%",
    },
    retention: [
      { label: "Day 1", value: 40 },
      { label: "Day 7", value: 25 },
      { label: "Day 28", value: 15 },
    ],
    acquisition: [
      { label: "App Store search", value: 37 },
      { label: "Direct / unknown", value: 35 },
      { label: "Shared by a friend", value: 18 },
      { label: "Other", value: 10 },
    ],
    trialConversion: 30,
    planMix: { monthly: 72, annual: 28 },
    revenue: { proceeds: "$602", churn: "4.9%", refunds: "1.2%", ltv: "$17" },
    lifecycle: [
      { label: "Paid", value: 47, detail: "Active subscription" },
      { label: "Hit the free limit", value: 68, detail: "Used all 10 captures" },
      { label: "Habitual", value: 171, detail: "Reached the useful loop" },
      { label: "Activated", value: 388, detail: "Captured at least once" },
      { label: "Installed only", value: 124, detail: "No capture yet" },
    ],
    profilesCreated: 148,
    product: [
      { label: "Capture success", value: "94.6%", detail: "Voice or typed captures saved", tone: "good" },
      { label: "Needs review", value: "9.9%", detail: "Captures needing user correction", tone: "watch" },
      { label: "Memory reuse", value: "21.8%", detail: "Users returning to a saved memory", tone: "neutral" },
      { label: "Crash-free", value: "99.4%", detail: "Sessions without a crash", tone: "good" },
    ],
  },
};
