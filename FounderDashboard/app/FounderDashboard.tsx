"use client";

import { useMemo, useState } from "react";
import type { DashboardMode, DashboardSnapshot, RangeKey } from "./dashboard-data";

type FounderDashboardProps = {
  ownerName: string;
  ownerEmail: string | null;
  snapshots: Record<RangeKey, DashboardSnapshot>;
  mode: DashboardMode;
  awaitingFirstEvents: boolean;
};

const ranges: Array<{ key: RangeKey; label: string }> = [
  { key: "7d", label: "7 days" },
  { key: "30d", label: "30 days" },
  { key: "90d", label: "90 days" },
  { key: "all", label: "All time" },
];

/** A metric with no connected source renders as an em dash, never as zero. */
function show(value: string | number | null): string {
  if (value === null) return "—";
  return `${value}`;
}

function MetricCard({
  eyebrow,
  value,
  delta,
  detail,
  featured = false,
  showTrend,
}: {
  eyebrow: string;
  value: string | number | null;
  delta: string | null;
  detail: string;
  featured?: boolean;
  showTrend: boolean;
}) {
  return (
    <article className={`metric-card${featured ? " metric-card-featured" : ""}`}>
      <div className="metric-card-topline">
        <p>{eyebrow}</p>
        {delta ? <span className="metric-delta">{delta}</span> : null}
      </div>
      <strong>{show(value)}</strong>
      <span className="metric-detail">{detail}</span>
      {/* Decorative only. Hidden against live numbers so a fixed rising shape
          is never read as a real trend. */}
      {showTrend ? (
        <div className="spark-bars" aria-hidden="true">
          {[31, 42, 38, 54, 48, 67, 72, 64, 81, 76, 88, 94].map((height, index) => (
            <i key={index} style={{ height: `${height}%` }} />
          ))}
        </div>
      ) : null}
    </article>
  );
}

function SectionHeading({
  kicker,
  title,
  detail,
}: {
  kicker: string;
  title: string;
  detail?: string;
}) {
  return (
    <div className="section-heading">
      <div>
        <p>{kicker}</p>
        <h2>{title}</h2>
      </div>
      {detail ? <span>{detail}</span> : null}
    </div>
  );
}

function NotConnected({ children }: { children: React.ReactNode }) {
  return (
    <p className="unavailable-note">
      <span aria-hidden="true">—</span>
      {children}
    </p>
  );
}

export function FounderDashboard({
  ownerName,
  ownerEmail,
  snapshots,
  mode,
  awaitingFirstEvents,
}: FounderDashboardProps) {
  const [range, setRange] = useState<RangeKey>("30d");
  const [showConnections, setShowConnections] = useState(false);
  const snapshot = snapshots[range];
  const isLive = mode === "live";
  const maxFunnel = useMemo(
    () => Math.max(1, ...snapshot.funnel.map((step) => step.value)),
    [snapshot],
  );
  const lifecycleTotal = useMemo(
    () => snapshot.lifecycle.reduce((sum, state) => sum + state.value, 0),
    [snapshot],
  );

  const status = isLive
    ? {
        className: "live-pill",
        label: awaitingFirstEvents ? "Live · no events yet" : "Live data",
        detail: awaitingFirstEvents
          ? "Connected to product analytics. Nothing received yet."
          : "Speak It events · anonymous product analytics",
      }
    : {
        className: "preview-pill",
        label: "Preview data",
        detail:
          mode === "unreachable"
            ? "Analytics is configured but did not answer. Showing preview data."
            : "Live sources are ready to connect",
      };

  const productAnalyticsStatus = isLive ? "Connected" : "Not connected";

  return (
    <main>
      <header className="site-header">
        <a className="brand" href="#top" aria-label="Speak It founder dashboard home">
          <span className="brand-mark" aria-hidden="true">
            <i />
            <i />
            <i />
            <i />
            <i />
          </span>
          <span>
            Speak It
            <small>Founder view</small>
          </span>
        </a>
        <nav aria-label="Dashboard sections">
          <a href="#growth">Growth</a>
          <a href="#product">Product</a>
          <a href="#subscriptions">Subscriptions</a>
        </nav>
        <button
          className="owner-button"
          type="button"
          onClick={() => setShowConnections((value) => !value)}
          aria-expanded={showConnections}
          aria-controls="connections"
        >
          <span className="owner-avatar">{ownerName.slice(0, 1).toUpperCase()}</span>
          <span className="owner-copy">
            <strong>{ownerName}</strong>
            <small>{ownerEmail ?? "Private owner access"}</small>
          </span>
          <span aria-hidden="true">⌄</span>
        </button>
      </header>

      <div className="dashboard" id="top">
        <section className="hero">
          <div>
            <div className="status-line">
              <span className={status.className}><i /> {status.label}</span>
              <span>{status.detail}</span>
            </div>
            <h1>Good morning, {ownerName}.</h1>
            <p>The clearest view of whether Speak It is growing—and becoming a habit.</p>
          </div>
          <div className="range-picker" aria-label="Dashboard date range">
            {ranges.map((item) => (
              <button
                key={item.key}
                type="button"
                className={range === item.key ? "active" : ""}
                aria-pressed={range === item.key}
                onClick={() => setRange(item.key)}
              >
                {item.label}
              </button>
            ))}
          </div>
        </section>

        {showConnections ? (
          <section className="connection-drawer" id="connections">
            <div>
              <span className="source-icon apple">A</span>
              <div><strong>App Store Connect</strong><small>Trials, paid plans, proceeds, refunds</small></div>
              <span className="not-connected">Not connected</span>
            </div>
            <div>
              <span className="source-icon product">S</span>
              <div><strong>Private product analytics</strong><small>Activation, retention, feature use—never your users’ words</small></div>
              <span className={isLive ? "connected" : "not-connected"}>
                {productAnalyticsStatus}
              </span>
            </div>
          </section>
        ) : null}

        <section className="metric-grid" aria-label="Key business metrics">
          <MetricCard
            eyebrow="Monthly recurring revenue"
            value={snapshot.kpis.mrr}
            delta={snapshot.kpis.mrrDelta}
            detail={isLive ? "Needs App Store Connect" : snapshot.comparison}
            featured
            showTrend={!isLive}
          />
          <MetricCard
            eyebrow="Active paid"
            value={snapshot.kpis.paid}
            delta={snapshot.kpis.paidDelta}
            detail={isLive ? "Completed purchases in range" : "Verified active subscriptions"}
            showTrend={!isLive}
          />
          <MetricCard
            eyebrow="In trial now"
            value={snapshot.kpis.trials}
            delta={snapshot.kpis.trialsDelta}
            detail={isLive ? "Purchases started in range" : "Trials not yet converted or expired"}
            showTrend={!isLive}
          />
          <MetricCard
            eyebrow="New users"
            value={snapshot.kpis.newUsers}
            delta={snapshot.kpis.newUsersDelta}
            detail={snapshot.label}
            showTrend={!isLive}
          />
        </section>

        <section className="north-star">
          <div className="north-star-copy">
            <span className="section-kicker">North star</span>
            <h2>The useful loop</h2>
            <p>People who capture at least twice, then complete a task or return to a memory.</p>
          </div>
          <div className="north-star-score">
            <strong>{snapshot.usefulLoop}%</strong>
            {snapshot.usefulLoopDelta ? <span>{snapshot.usefulLoopDelta}</span> : null}
          </div>
          <div className="north-star-track" aria-label={`${snapshot.usefulLoop}% of new users reached the useful loop`}>
            <i style={{ width: `${Math.min(100, snapshot.usefulLoop)}%` }} />
          </div>
          <p className="north-star-insight"><b>Why it matters:</b> this measures delivered value, not just opens or taps.</p>
        </section>

        <div className="two-column" id="growth">
          <section className="panel funnel-panel">
            <SectionHeading kicker="Growth" title="From download to paid" detail={snapshot.label} />
            <div className="funnel" role="list" aria-label="New user conversion funnel">
              {snapshot.funnel.map((step, index) => (
                <div className="funnel-row" role="listitem" key={step.label}>
                  <div className="funnel-label">
                    <span>{index + 1}</span>
                    <strong>{step.label}</strong>
                  </div>
                  <div className="funnel-bar-wrap">
                    <i style={{ width: `${(step.value / maxFunnel) * 100}%` }} />
                  </div>
                  <b>{step.value}</b>
                  <small>{step.rate}</small>
                </div>
              ))}
            </div>
            {isLive ? null : (
              <div className="callout watch">
                <span aria-hidden="true">!</span>
                <p><strong>Biggest opportunity</strong>Help more first-time capturers reach the useful loop.</p>
              </div>
            )}
          </section>

          <section className="panel activity-panel">
            <SectionHeading kicker="Users" title="Active and returning" detail="Anonymous installs" />
            <div className="active-users">
              <div><strong>{snapshot.activity.dau}</strong><span>Daily active</span></div>
              <div><strong>{snapshot.activity.wau}</strong><span>Weekly active</span></div>
              <div><strong>{snapshot.activity.mau}</strong><span>Monthly active</span></div>
            </div>
            <div className="retention">
              <h3>New-user retention</h3>
              {snapshot.retention ? (
                snapshot.retention.map((item) => (
                  <div className="retention-row" key={item.label}>
                    <span>{item.label}</span>
                    <div><i style={{ width: `${item.value}%` }} /></div>
                    <strong>{item.value}%</strong>
                  </div>
                ))
              ) : (
                <NotConnected>Cohort retention is not wired up yet.</NotConnected>
              )}
            </div>
            <div className="compact-stats">
              <div><strong>{snapshot.activity.sessions}</strong><span>Sessions / user</span></div>
              <div><strong>{snapshot.activity.captures}</strong><span>Captures / active user</span></div>
              <div><strong>{snapshot.activity.completion}</strong><span>Task completion</span></div>
            </div>
          </section>
        </div>

        <section className="panel lifecycle-panel">
          <SectionHeading
            kicker="Users"
            title="Where everyone stands"
            detail={`${lifecycleTotal} ${lifecycleTotal === 1 ? "install" : "installs"}`}
          />
          <div className="lifecycle" role="list" aria-label="User lifecycle states">
            {snapshot.lifecycle.map((state) => (
              <div className="lifecycle-row" role="listitem" key={state.label}>
                <div className="lifecycle-label">
                  <strong>{state.label}</strong>
                  <small>{state.detail}</small>
                </div>
                <div className="lifecycle-bar">
                  <i style={{ width: `${(state.value / Math.max(1, lifecycleTotal)) * 100}%` }} />
                </div>
                <b>{state.value}</b>
              </div>
            ))}
          </div>
          <div className="lifecycle-footnote">
            <span>
              <b>{snapshot.profilesCreated}</b> created the optional on-device profile
            </span>
            <span>
              Speak It has no accounts. States are counted per install, so a
              delete and reinstall starts over.
            </span>
          </div>
        </section>

        <section className="panel acquisition-panel">
          <SectionHeading kicker="Acquisition" title="Where new users come from" detail="App Store attribution" />
          {snapshot.acquisition ? (
            <div className="acquisition-layout">
              <div className="acquisition-bars">
                {snapshot.acquisition.map((item) => (
                  <div className="acquisition-row" key={item.label}>
                    <span>{item.label}</span>
                    <div><i style={{ width: `${item.value}%` }} /></div>
                    <strong>{item.value}%</strong>
                  </div>
                ))}
              </div>
              <div className="insight-card">
                <span>Best signal</span>
                <strong>Friend shares retain 1.7× better</strong>
                <p>Sharing is worth encouraging even before adding a formal referral program.</p>
              </div>
            </div>
          ) : (
            <NotConnected>
              App Store attribution needs App Store Connect. Product analytics
              cannot see where a download came from.
            </NotConnected>
          )}
        </section>

        <div className="two-column" id="subscriptions">
          <section className="panel subscription-panel">
            <SectionHeading kicker="Subscriptions" title="Trial and plan health" detail={isLive ? "From purchase events" : "Apple-verified"} />
            <div className="trial-score">
              <div className="ring" style={{ "--score": `${snapshot.trialConversion * 3.6}deg` } as React.CSSProperties}>
                <span>{snapshot.trialConversion}%</span>
              </div>
              <div><strong>Trial-to-paid conversion</strong><p>Of eligible trials that ended in this period.</p></div>
            </div>
            <div className="plan-mix">
              <div className="plan-mix-heading"><span>Plan mix</span><b>{snapshot.planMix.annual}% annual</b></div>
              <div className="plan-track" aria-label={`${snapshot.planMix.monthly}% monthly and ${snapshot.planMix.annual}% annual`}>
                <i style={{ width: `${snapshot.planMix.monthly}%` }} />
                <i style={{ width: `${snapshot.planMix.annual}%` }} />
              </div>
              <div className="plan-legend"><span><i />$1.99 monthly · {snapshot.planMix.monthly}%</span><span><i />Annual · {snapshot.planMix.annual}%</span></div>
            </div>
          </section>

          <section className="panel revenue-panel">
            <SectionHeading kicker="Business" title="Revenue quality" detail={snapshot.label} />
            <div className="revenue-grid">
              <div><span>Estimated proceeds</span><strong>{show(snapshot.revenue.proceeds)}</strong><small>After Apple’s commission</small></div>
              <div><span>Monthly churn</span><strong>{show(snapshot.revenue.churn)}</strong><small>Paid plans lost</small></div>
              <div><span>Refund rate</span><strong>{show(snapshot.revenue.refunds)}</strong><small>Of paid transactions</small></div>
              <div><span>Projected LTV</span><strong>{show(snapshot.revenue.ltv)}</strong><small>At current retention</small></div>
            </div>
            {isLive ? (
              <NotConnected>
                Revenue is Apple-verified only. Connect App Store Connect to fill this in.
              </NotConnected>
            ) : (
              <div className="callout good"><span aria-hidden="true">✓</span><p><strong>Healthy signal</strong>Annual-plan share is moving in the right direction.</p></div>
            )}
          </section>
        </div>

        <section className="panel product-panel" id="product">
          <SectionHeading kicker="Product quality" title="Does the app feel effortless?" detail="No thought content collected" />
          <div className="product-grid">
            {snapshot.product.map((item) => (
              <article key={item.label}>
                <div><span>{item.label}</span><i className={item.tone} /></div>
                <strong>{item.value}</strong>
                <p>{item.detail}</p>
              </article>
            ))}
          </div>
          <div className="privacy-strip">
            <span className="privacy-mark" aria-hidden="true">◉</span>
            <div><strong>Private by design</strong><p>The dashboard measures actions and outcomes. It never receives recordings, transcripts, task titles, memory text, names, or search queries.</p></div>
          </div>
        </section>

        {isLive ? null : (
          <section className="focus-section">
            <SectionHeading kicker="Founder focus" title="What deserves attention next" detail="Ranked by likely impact" />
            <div className="focus-grid">
              <article><span>01</span><div><strong>Improve the second-use moment</strong><p>Users who capture twice are much more likely to return. Make the first saved result invite one natural follow-up.</p></div><b>High impact</b></article>
              <article><span>02</span><div><strong>Reduce “Needs review” below 6%</strong><p>The correction flow is the clearest friction point between capture and trust.</p></div><b>Watch</b></article>
              <article><span>03</span><div><strong>Show annual value at the right moment</strong><p>Offer annual after a user has completed a useful loop—not before they experience value.</p></div><b>Test</b></article>
            </div>
          </section>
        )}

        <section className="sources-section">
          <div>
            <span className="section-kicker">Data sources</span>
            <h2>One dashboard, two truths.</h2>
            <p>Apple verifies the money. Anonymous product analytics explains the behavior.</p>
          </div>
          <div className="source-cards">
            <article><span className="source-icon apple">A</span><div><strong>App Store Connect</strong><p>Downloads, current trials, paid plans, conversion, churn, refunds, proceeds.</p></div><b>Ready to connect</b></article>
            <article><span className="source-icon product">S</span><div><strong>Speak It events</strong><p>Activation, useful loops, feature adoption, capture quality, retention.</p></div><b>{isLive ? "Connected" : "Ready to connect"}</b></article>
          </div>
        </section>

        <footer>
          <span>Speak It · Founder dashboard</span>
          <span>{isLive ? "Live data" : "Preview data"} · {snapshot.label}</span>
        </footer>
      </div>
    </main>
  );
}
