# Bounded capture-startup diagnostic

Requires the local Xcode runtime and macOS 26.4+. Run:

```bash
./Tools/CaptureStartup/build.sh
./Tools/CaptureStartup/build/startup
```

The unoptimized DEBUG host harness calls the live production rules and runtime
interpreter functions. It has two fixed synthetic inputs, no microphone, no saved
store, no user captures, no reference-bank retrieval and no prewarming. It measures
first and second requests within one process using ContinuousClock. It does not
control system-model eviction and therefore cannot label the first request a cold
model. The model stage deliberately bypasses early literal certificates to isolate
that stage; it is not the full repository/persisted-row/UI pipeline. Only the
production model's availability and bounded timing/completion observer messages
are printed. A non-nil review result is not a successful semantic extraction.

Model calls use the app's twenty-second cancellation pattern. For unattended use,
wrap the process in an external finite timeout as well. Do not restart it in a
benchmark loop, kill system model services, or infer p95 from two requests.

October 13 development check on macOS 27.0 (26A428): the ordinary literal path
returned three products in 0.2942 and 0.0740 seconds. The isolated model stage took
7.7862 and 2.3350 seconds; its outline generations took 2.3748 and 1.2912 seconds.
Both outputs retained one review item. These are Mac/debug observations and do
not qualify iPhone capture accuracy, microphone readiness, last-word-to-visible-row
latency, battery or the benefit of prewarming. No shipping warmup change follows.
