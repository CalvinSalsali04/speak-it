# Synthetic speech replay

Local development tool for the shipping `SpeechRecognitionBackend.swift`.
No microphone, phone install, third-party service or real recording is needed.
Generated speech and seeded filtered noise are synthetic challenges, not evidence
about real speakers, accents, rooms, microphones or production accuracy.

```sh
./Tools/SpeechReplay/build.sh
./Tools/SpeechReplay/build/speech-replay --availability
python3 Tools/SpeechReplay/generate.py --out /tmp/SpeakItSyntheticAudio
./Tools/SpeechReplay/build/speech-replay --audio /tmp/SpeakItSyntheticAudio/AS02-Samantha-quiet.wav --output /tmp/speech-trace.json --realtime
```

`cases.json` freezes twelve development scripts. Generation makes 36 files:
two installed macOS voices, plus 20/10 dB synthetic noise for three scripts.
The manifest retains the input hash, generated audio hashes and pause placement.
The AS09 recordings contain noise, **not a competing speaker**; that part of
Claude's challenge remains unverified. Do not infer foreground-voice isolation.

File forwarding without `--realtime` feeds 100 ms buffers every 15 ms. It can
compare recognized words but cannot measure real endpointing or phone latency.
`--realtime` retains actual callback arrival times and input-audio progress.
Neither mode runs the app's microphone or endpoint orchestrator. Its trace can
be replayed through the existing DEBUG seam in `SpeechTranscriber` and the real
repository; `RecordedPartialEndpointReplayTests` preserves one actual cadence.
That test proves automatic single persistence for that trace, not microphone
capture, physical audio durability or final row pixels.

`--modern` compares Apple's installed `SpeechTranscriber` file module. It is an
experimental comparator, not the shipping recognizer or an engine preference.
It uses no recognition hints and does not install missing assets. Its historical
v1 `receivedFinal` field marked stream completion, including empty silence;
read the per-event final flags when distinguishing final text from no speech.

The October 13 run and original failures are retained in the original checkout's
`output/capture-confidence-20261013/`. All 36 shipping-backend replays completed;
raw word identity was 16/36. With the same accent/punctuation normalization on
both sides, DictationTranscriber and the alternate module each matched 18/36;
the alternate lost one existing match. Those are lexical comparisons of twelve
synthetic scripts, not semantic capture accuracy. The recognizer was not switched.
