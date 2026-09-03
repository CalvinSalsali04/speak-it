# Speak It founder dashboard

- This directory is the private founder-only analytics site, a Node project inside the Speak It monorepo. Run its `npm` commands from here; Git operations happen at the repository root, and its CI job lives in `.github/workflows/ci.yml`.
- It uses React 19, TypeScript, vinext, and Cloudflare tooling. Node.js 22.13+ is required.
- Dashboard metrics are preview/demo data until live App Store and content-free product analytics credentials are deliberately connected. Never present demo data as real business performance.
- Never expose PostHog keys, App Store credentials, user identifiers, emails, captured text, transcripts, task titles, memory text, or search terms in client-rendered code, logs, fixtures, screenshots, or commits.
- Keep this dashboard private. Do not deploy, change access policy, connect credentials, or mutate external analytics data unless the user explicitly asks in that task.
- Preserve the minimal visual language and make every card usable at mobile and desktop widths, with keyboard and screen-reader support.

## Data sources

- `app/dashboard-data.ts` holds preview/demo snapshots. `app/posthog.ts` reads real
  metrics; `app/dashboard-source.ts` decides which of the two the page renders.
- `app/posthog.ts` is server-only. Never import it, or any value derived from the
  API key, into a `"use client"` module.
- Preview and live numbers are never mixed. In live mode a metric with no
  connected source is `null` and renders as "—", never as a demo value or a zero.
- Revenue, App Store attribution, and crash-free rate cannot come from PostHog.
  They stay `null` until App Store Connect is connected.
- Configure with `POSTHOG_PROJECT_ID` and `POSTHOG_API_KEY` (a personal `phx_`
  key, not the app's `phc_` ingestion key). See `.dev.vars.example`. Any failure
  to read or query falls back to labelled preview data rather than a wrong number.

## Commands

```bash
npm install
npm run lint
npm test
npm run build
```

Run `npm run lint` plus `npm test` after code changes. `npm test` already includes a production build. Use `npm run dev` only for interactive local visual QA.
