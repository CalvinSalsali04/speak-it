# Contributing

How work moves through this repository. The product and privacy rules that
every change must respect are in `CLAUDE.md`; this file covers branches, checks,
CI, and releases.

## Branches and pull requests

- `main` is always shippable. Every shipped build is tagged `build-N-rc`.
- Work on a branch named for what it does: `fix/…`, `feat/…`, `chore/…`, `docs/…`.
  Use `wip/…` only for work that is explicitly unfinished and says so in its
  commit message.
- Open a pull request for every change to `main`. The template asks for the
  verification evidence and the product-contract checks; fill it in rather than
  deleting it.
- Commit titles are one imperative sentence; the body explains why, in the
  voice the existing history uses. Long-lived reasoning goes in
  `Docs/DECISIONS.md`, and limitations that ship go in `Docs/KNOWN_ISSUES.md`.
- Never force-push a branch someone else may have pulled, and never rewrite
  `main`.

## Checks to run before pushing

All checks are scripts under `Tools/CI/` so a local run and a CI run mean the
same thing. Each defaults `DEVELOPER_DIR` to `/Applications/Xcode.app`.

```bash
./Tools/CI/corpus-gate.sh        # rules-path regression net, ~1 minute, no simulator
./Tools/CI/unit-tests.sh         # the XCTest unit suite on a simulator, ~9 minutes
./Tools/CI/release-build.sh      # Release compile for a generic iOS device
```

Narrow the unit run while iterating:

```bash
./Tools/CI/unit-tests.sh SpeakItTests/TemporalFullPathTests
```

UI tests are slow and need a booted simulator:

```bash
./Tools/CI/unit-tests.sh SpeakItUITests
```

For the Node projects, run `npm run lint` and `npm test` inside
`FounderDashboard/`, and `npm test` inside `ReferralService/`.

Physical-device behaviour (Back Tap, microphone quality, interruptions, AirPods,
lock screen, notifications, purchases) still needs hands-on iPhone QA. Say so in
the pull request.

## Continuous integration

`.github/workflows/ci.yml` runs on every push to `main` and every pull request:

| Job | Runner | Runs when |
| --- | --- | --- |
| Secrets, workflow and shell lint | Linux | always |
| Founder dashboard (lint + tests) | Linux | `FounderDashboard/` changed |
| Referral service (tests) | Linux | `ReferralService/` changed |
| iOS app (corpus gate, unit tests, Release compile on `main`) | macOS | iOS files changed **and** a Mac runner is available (below) |

### Why the iOS job needs a Mac of its own

GitHub bills macOS runners at ten times the Linux rate. A private repository on
the Free plan has 2,000 Linux-minutes a month, which is about 200 macOS minutes:
roughly one unit-suite run. So the iOS job only runs on GitHub-hosted macOS when
you dispatch it by hand (Actions → CI → Run workflow), and otherwise waits for a
self-hosted runner.

To run it on every pull request, register this Mac (or any Mac with Xcode 26.6
at `/Applications/Xcode.app` and at least one iPhone simulator):

1. On GitHub: repository → Settings → Actions → Runners → New self-hosted
   runner → macOS / ARM64. Follow the download and `./config.sh` steps it
   prints, adding `--labels speakit-mac --unattended` to the configure command.
2. Install it as a service so it survives reboots:
   `./svc.sh install && ./svc.sh start` (a launchd agent; it runs while you are
   logged in, which the simulator needs anyway).
3. On GitHub: repository → Settings → Secrets and variables → Actions →
   Variables → new repository variable `IOS_RUNNER` with the value `speakit-mac`.

From then on the iOS job picks that label automatically. Self-hosted minutes are
free on every plan. The repository is private and only its owner opens pull
requests, so running third-party code on the runner is not a concern; keep it
that way before adding collaborators.

### Dependabot and secret scanning

Dependabot opens weekly pull requests for the two Node projects and for the
pinned GitHub Actions. Every action is pinned to a commit SHA with the version in
a comment; Dependabot keeps both in step. The hygiene job scans the full git
history with gitleaks; example configuration files are allow-listed in
`.gitleaks.toml`.

## Releases

1. Bump `CURRENT_PROJECT_VERSION` in every target of `SpeakIt.xcodeproj` (app,
   Live Activity extension, Share extension, UI tests) and `MARKETING_VERSION`
   when the user-facing version changes. The UI tests assert the values, so a
   mismatch fails the suite.
2. Add the build to `CHANGELOG.md` and record any decision in
   `Docs/DECISIONS.md`.
3. Run the three checks above and the UI tests; do the device QA in
   `Docs/CAPTURE_STRESS_TEST_PLAN.md` for anything that touches capture.
4. Tag the commit `build-N-rc` and push the tag.
5. Upload: archive from Xcode as today, or dispatch **TestFlight upload**
   (`.github/workflows/testflight.yml`) once the `ASC_KEY_ID`, `ASC_ISSUER_ID`,
   and `ASC_PRIVATE_KEY` secrets exist. That workflow has not yet been run end
   to end; treat its first run as a rehearsal. Leave `SPEAKIT_ANALYTICS_KEY`
   unset unless the build is meant to report analytics.

App Store Connect stays the source of truth for prices and availability; nothing
in this repository changes it.
