# CI scripts

The scripts here are the single definition of each check. `.github/workflows/ci.yml`
calls them, `CLAUDE.md` points at them, and running one locally produces the same
evidence as the CI job.

| Script | What it does | Needs a simulator |
| --- | --- | --- |
| `corpus-gate.sh` | Tests the scoring instrument, builds `Tools/PipelineProbe` and `Tools/CorpusRunner`, replays the full semantic corpus, fails on any blocking regression | no |
| `unit-tests.sh [target]` | Runs `SpeakItTests` (default), one test class, or `SpeakItUITests` | yes |
| `release-build.sh` | Compiles the Release configuration for a generic iOS device, unsigned | no |
| `simulator-id.sh` | Picks the simulator `unit-tests.sh` uses: `SPEAKIT_SIMULATOR_ID`, else a `SpeakIt-Slim-*` pool device, else a booted iPhone | — |
| `simulator-pool.sh [N]` | Creates or reuses `SpeakIt-Slim-1…N`, slims them with the profile below, boots them, prints their UDIDs | — |
| `slim-simulator.sh <udid>` | Applies `simslim-profile.json` to one simulator; a no-op without SimSlim, and refuses non-pool devices unless `SPEAKIT_SLIM_ANY=1` | — |
| `simslim-profile.json` | The SimSlim profile: every daemon category off, eight daemons kept (see its `description`) | — |
| `testflight.sh` | Archives with automatic signing and uploads to App Store Connect; dispatch-only workflow, not yet rehearsed | no |

Every script honours `DEVELOPER_DIR` and defaults it to `/Applications/Xcode.app`,
so nothing depends on the machine's `xcode-select`.

## Running the iOS job somewhere affordable

GitHub bills macOS runners at ten times the Linux rate, and a private repository on
the Free plan has 2,000 Linux-minutes a month, which is about 200 macOS minutes: one
or two unit-suite runs. The iOS job in `ci.yml` therefore runs on GitHub-hosted macOS
only when dispatched by hand. To run it on every pull request, register a
self-hosted runner on a Mac that has Xcode installed (see `CONTRIBUTING.md`) and set
the repository variable `IOS_RUNNER` to that runner's label.

## Slim simulators

A stock iOS 26.5 simulator boots about 200 background daemons and holds about
3.7 GB — Siri, Spotlight, photo analysis, wallpaper posters, iCloud, News,
Wallet — none of which a test run uses. On a 16 GB Mac that is three or four
simulators before swap takes over. [SimSlim](https://github.com/MobAI-App/simslim)
(MIT, `brew install mobai-app/tap/simslim`) writes persistent `launchctl
disable` overrides into one simulator's own launchd database; it needs no
`sudo`, touches nothing on the Mac, and `simslim off <udid>` restores stock.

Measured on this project, iPhone 17 / iOS 26.5, 2026-09-04:

| | processes | memory (phys_footprint) |
|---|---|---|
| stock | 202 | 3.74 GB |
| `simslim-profile.json` | 65 | 0.87 GB |

Wall clock for the unit suite (727 tests, build included) on the same day:
one stock simulator ~9 min as documented; one slim simulator 578 s; two slim
simulators via `SPEAKIT_SHARDS=2` 386–418 s.

The profile keeps eight daemons and nothing else, and each keep was measured
rather than assumed — which is the reason the profile is checked in instead of
left to `simslim on` defaults:

- `com.apple.mobileassetd`. NaturalLanguage loads its tagger and embedding
  assets through it. With it off, 13 unit tests — every one backed by
  `NLTagger` or `NLEmbedding` — fail while the same corpus passes on the host.
  Found by bisection over the categories, then the daemons of the one that
  mattered.
- The seven daemons SimSlim's `storekit` feature names (`storekitd`,
  `itunesstored`, the three `ams*` daemons, `passd`, `financed`). Without
  them the scheme's StoreKit configuration serves no products, the paywall
  falls back to its developer preview card, and the paywall UI test fails on
  the plan label.

With those kept, the unit suite is 721 of 721 and the UI suite passes.

```bash
Tools/CI/simulator-pool.sh 3                 # SpeakIt-Slim-1..3, slimmed and booted
SPEAKIT_SHARDS=3 Tools/CI/unit-tests.sh      # the unit suite across all three
SPEAKIT_SIMULATOR_ID=<udid> Tools/CI/unit-tests.sh SpeakItUITests   # and the UI suite beside it
```

What a slim simulator cannot do, and what to run stock instead:

- **Widgets and Live Activities** (`chronod`, `liveactivitiesd`, `PosterBoard`)
  are off, so the Today widget and the capture Live Activity do not render.
  Widget QA already needs a signed build; run it on a stock device.
- **Push and the App Store** are off; the StoreKit daemons are kept so the
  scheme's StoreKit configuration keeps serving products. A purchase
  rehearsal still belongs on a stock device.
- **Siri, Spotlight, Contacts, Calendar, Photos pickers** are off. Nothing in
  the automated suites reaches them.

Xcode's own parallel testing (`-parallel-testing-enabled`) clones the
destination simulator through CoreSimulator, and a CoreSimulator clone comes up
**stock**: measured 2026-09-04, `xcrun simctl clone` of a slim device booted
with 0 of 170 overrides in place (SimSlim's own `simslim clone` is what
preserves a profile). So the clones would eat the memory the profile saved.
The scheme keeps parallel testing off for that reason and one more: interrupted
runs leak clones into `~/Library/Developer/XCTestDevices` (131 of them, 427 GB
by `du`, were found on 2026-09-04). `SPEAKIT_SHARDS` uses named pool devices
instead, which stay slim, leak nothing, and name their device in every failure.
