# CI scripts

The scripts here are the single definition of each check. `.github/workflows/ci.yml`
calls them, `CLAUDE.md` points at them, and running one locally produces the same
evidence as the CI job.

| Script | What it does | Needs a simulator |
| --- | --- | --- |
| `corpus-gate.sh` | Builds `Tools/PipelineProbe` and `Tools/CorpusRunner`, replays the full semantic corpus, fails on any blocking regression | no |
| `unit-tests.sh [target]` | Runs `SpeakItTests` (default), one test class, or `SpeakItUITests` | yes |
| `release-build.sh` | Compiles the Release configuration for a generic iOS device, unsigned | no |
| `simulator-id.sh` | Picks the simulator `unit-tests.sh` uses; override with `SPEAKIT_SIMULATOR_ID` | — |
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
