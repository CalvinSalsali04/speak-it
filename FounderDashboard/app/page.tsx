import { getChatGPTUser, requireChatGPTUser, type ChatGPTUser } from "./chatgpt-auth";
import { buildDashboardView } from "./dashboard-source";
import { FounderDashboard } from "./FounderDashboard";

export const dynamic = "force-dynamic";

/**
 * `npm run dev` has no platform auth in front of it, so the sign-in route the
 * redirect targets does not exist locally. `import.meta.env.DEV` is replaced at
 * build time by Vite, so this fallback is compiled out of production entirely —
 * it cannot weaken the deployed site even if this file is edited carelessly.
 */
const LOCAL_DEV_OWNER: ChatGPTUser = {
  userId: "local-dev",
  displayName: "Local dev",
  email: "local development",
  fullName: null,
};

export default async function Home() {
  // Defence in depth. The Sites platform is expected to keep this deployment
  // private, but this page renders revenue and user numbers, so it refuses to
  // render at all without an authenticated owner rather than trusting that
  // configuration to stay correct.
  const owner = import.meta.env.DEV
    ? ((await getChatGPTUser()) ?? LOCAL_DEV_OWNER)
    : await requireChatGPTUser("/");

  // The PostHog key stays in the Worker and is never serialised into the props
  // handed to the client component.
  const view = await buildDashboardView();

  return (
    <FounderDashboard
      ownerName={owner.fullName?.split(" ")[0] ?? "Calvin"}
      ownerEmail={owner.email}
      snapshots={view.snapshots}
      mode={view.mode}
      awaitingFirstEvents={view.awaitingFirstEvents}
    />
  );
}
