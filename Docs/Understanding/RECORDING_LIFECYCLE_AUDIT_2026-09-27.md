# Recording lifecycle audit — September 27, 2026

The observed 1.9-second cutoff is an app-owned automatic endpoint decision,
not a recognizer segment duration limit. In automatic mode,
`SpeechTranscriber.scheduleNaturalPauseFinish` fires a 1.9, 4, or 8-second
decision after stable words and calls `beginFinalization`. That calls
`stopAudioInput`, the only `audioEngine.stop()` site. A normal complete-sounding
sentence can therefore close the microphone while the speaker is still
thinking. A longer timeout would move the failure boundary, not remove it.

The ordinary in-app voice screen now selects continuous capture before it
requests the microphone. `SpeechTranscriber.automaticPauseDecision` is `nil`
in that mode, the view does not arm its no-speech timer, and it requires a
protected audio draft before starting. The visible **Continuous** control
switches to **Auto finish** only on a deliberate tap. Explicit pulse Finish
changes the state to finalizing immediately, stops input, drains accepted
frames, then asks the selected backend to finalize or uses protected-audio
recovery. Switching back to Auto finish cannot remove the sticky whole-file
verification requirement for that recording.

`DictationTranscriber` with `progressiveLongDictation` commits a finalized
segment to the transcript assembly and emits a nonfinal update while input is
open. It emits a whole-capture final only after the input stream closes.
The legacy `SFSpeech` callback treats an early `isFinal` as unexpected rather
than as user Finish. In continuous mode an early backend final/error leaves
recording and protected file active when possible and requires offline
recovery. These are source-code facts, not microphone observations.

| Stop source | Current behavior |
| --- | --- |
| Explicit pulse Finish or Save and Close | Finalization stops the engine and drains accepted frames. Legacy continuous capture uses full saved-audio recovery. |
| Automatic pause timer | Possible only after Auto finish was explicitly selected on the in-app screen, or in separate automatic entry points. The timer is still 1.9/4/8 seconds. |
| Backend segment final | Analyzer segment is assembled without stopping the engine. Unexpected whole backend final enters error/recovery handling. |
| Cancel, discard, reset, launch or permission failure | Resource reset can stop the engine; draft deletion is controlled separately by the view/draft store. |
| Missing input, buffer-copy, queue, conversion, file-write or audio-integrity failure | Continuous recording fails visibly and retains available protected source for recovery. |
| Platform interruption, route loss, media services reset | Recording stops or fails visibly; the app must not claim that audio after the interruption was recorded. |

The focused UI test confirmed the fresh screen shows **Continuous capture on**
before microphone permission and lets a tap select **Auto finish on**. Its
settled light-mode screenshot has separate, legible controls with at least a
44-point target. A unit assertion checks that the in-app default mode chooses
no natural-pause timer; it does not emulate actual microphone continuity.

The 120 supplied recording specifications remain unrun as microphone cases.
The existing physical runbook in
`Docs/Understanding/LONG_CAPTURE_DEVICE_QUALIFICATION_RUNBOOK.md` and the
pack's `docs/RECORDING_ACCEPTANCE_PLAN.md` should be combined into one
authorized iPhone session: default and deliberate Auto finish; 1.8, 1.9,
2.0, 2.1, 3, 5, 8, and 15-second pauses; quiet resumption and late correction;
quick explicit Finish; 59/61/90/180/300/360-second runs; backend availability;
frame drain, interruption, route change, lock/relaunch, and retained audio.
Record engine stop reason and frame counts, then compare audio, transcript,
persisted intentions, and on-screen status separately. No physical install or
microphone run was authorized in this task.


## October 1 software duration evidence

`testProtectedAudioFilesKeepEveryFrameAcrossSupportedDurationBoundaries` passed
for synthetic native CAF files of 59, 61, 90, 180, 300 and 360 seconds. It uses
the shipping audio processor, checks exact frame counts and per-second sample
markers after reusing input buffers, includes 15-second silent spans, drains
accepted writes and checks the <=45-second chunk plan covers every frame.
The targeted run also passed Continuous default/no automatic timer, Long-mode
Finish without recognized words and nonblocking Finish/drain controls.
This does not exercise the microphone, speech recognition, the private recovery
chunk writer, route changes or real elapsed recording. Those remain in the
single prepared device session; none is credited as passed by this test.
