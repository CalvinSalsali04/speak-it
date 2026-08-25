# Adaptive voice endpointing

**Status:** Implemented for beta validation  
**Decision date:** 2026-08-24  
**Audience:** Product, engineering, QA, and beta support

## Direct answer

Speak It should not use one silence timeout for every utterance. It should keep
the current fast path for wording that appears complete, but hold the microphone
substantially longer when the live transcript ends with a strong continuation
cue such as **at**, **and**, **to**, an article, a list opener, or a hesitation.

The implemented behavior is:

| Live evidence | At 2.1 seconds of pause | Base silence window | What ends the wait |
| --- | --- | --- | --- |
| Wording appears complete | Save normally | 2.1 seconds | Automatic save or an earlier pulse tap |
| Ending is ambiguous | Show **Still listening…** | 4 seconds | More speech resets the decision; a pulse tap finishes immediately; otherwise save at the cap |
| Wording appears clearly incomplete | Show **Still listening…** | 8 seconds | More speech resets the decision; a pulse tap finishes immediately; otherwise save at the cap |
| No recognized words | Keep the existing listening UI | 10 seconds | Speech begins, or the existing no-speech recovery/timeout runs |

For the exact beta report — “Remind me to pick up Ice wine at LCBO tomorrow.
At.” — the final spoken word **at** enters the clearly incomplete path. The
inserted period and capitalization do not change that decision. This is one
regression fixture, not the basis of the policy.

## Why this is not a one-example rule

The implementation does not search for the ice-wine sentence, LCBO, reminders,
or even a specific punctuation pattern. It combines five independent signal
families:

| Signal family | General question it answers | Safeguard |
| --- | --- | --- |
| Lexical/pragmatic tail | Does the current wording leave a connector, recipient, time, noun phrase, list, or hesitation open? | Uses categories of cues and three confidence tiers, not one phrase match |
| Transcript evolution | Did recognized words actually change? | Punctuation-only, capitalization-only, quote, and whitespace revisions no longer restart the timer or hide the prompt |
| Pause duration | How long has the current candidate silence lasted? | Each stable transcript gets a 2.1-, 4-, or 8-second base window; genuine new words reset it and raw audio can defer it only a bounded number of times |
| Fresh audio activity | Did sound resume before ASR published the new words? | May briefly defer a boundary, but only a bounded number of times because noise is not proof of speech |
| Explicit/system state | Did the person tap finish, or did capture fail or get interrupted? | Manual finish wins; unexpected backend stops use protected-recording recovery |

The test corpus covers short fragments, complete commands, completed recipients
and times, conjunctions, open noun phrases, hesitations, ambiguous prepositions,
questions, grammatical short answers, punctuation rewrites, and lexical ASR
revisions. The named beta example is retained because every real failure should
become a permanent regression, but it is only one row in that matrix.

## Why this design

Fixed silence endpointing forces a tradeoff: a shorter timeout feels responsive
but splits slow speech; a longer timeout protects slow speech but makes every
finished capture feel delayed. Microsoft documents exactly that failure mode
and describes semantic segmentation as a way to reduce short-pause
over-segmentation ([Microsoft Speech documentation](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/how-to-recognize-speech#change-how-silence-is-handled)).

Research on dynamic endpointing found that semantics and timing were the most
informative signals for deciding whether a silence was the end of a turn, and
that adaptive thresholds reduced latency relative to a fixed threshold
([Raux and Eskenazi, SIGDIAL 2008](https://aclanthology.org/W08-0101/)). The
current implementation is a small, deterministic, on-device version of that
principle: it combines the transcript's semantic tail, elapsed pause time, and
fresh audio activity.

Later work reaches the same architectural conclusion from different directions.
TurnGPT found that syntactic and pragmatic completeness contribute to turn-shift
prediction across multiple written and spoken-dialog datasets
([Ekstedt and Skantze, 2020](https://aclanthology.org/2020.findings-emnlp.268/)). Acoustic endpoint research also shows that background noise materially affects false endpoints
([Chang et al., Interspeech 2017](https://research.google/pubs/endpoint-detection-using-grid-long-short-term-memory-networks-for-streaming-speech-recognition/)). No single word list, punctuation mark, or audio threshold captures both kinds of evidence.

There also is no objectively correct binary label for every pause. Recent
SIGDIAL research describes an observed turn shift as one plausible outcome
among several when a turn is inherently ambiguous
([Kubo et al., 2026](https://aclanthology.org/2026.sigdial-1.2/)). Speak It's middle tier is the product expression of that uncertainty: wait longer than the fast path, but do not pretend to know the user will continue or listen indefinitely.

The 8-second base silence cap is intentionally conservative for clear incompleteness in a
capture product, where a cut-off can lose the user's intended reminder. An
ambiguous ending gets a 4-second middle window so phrases such as “count me in”
do not always incur the full delay. Modern semantic endpointing uses a similar
range: OpenAI's official Realtime API reference describes 2-, 4-, and 8-second
maximums for high-, medium-, and low-eagerness semantic VAD
([Realtime API reference](https://platform.openai.com/docs/api-reference/realtime-server-events/conversation/item/done)). This is a reference point, not evidence that eight seconds is universally optimal; beta metrics and device testing still decide whether Speak It should tune it.

Apple's SpeechAnalyzer separates audio input, result delivery, and session
control; the app explicitly decides when to finish analysis
([Apple SpeechAnalyzer documentation](https://developer.apple.com/documentation/speech/speechanalyzer)). That means Speak It, rather than the transcription
backend, must own the user-facing endpointing policy. The implementation keeps
that policy in `SpeechTranscriber`, shared by the legacy recognizer and the
iOS 26 analyzer path.

The legacy path has the same ownership boundary. Apple states that an
`SFSpeechAudioBufferRecognitionRequest` continuously analyzes appended audio and
stops only after the app explicitly calls `endAudio()`
([Apple audio-buffer request documentation](https://developer.apple.com/documentation/speech/sfspeechaudiobufferrecognitionrequest)). A thinking pause therefore does not create a backend-final event that can bypass the adaptive timer. On the analyzer path, final module results are assembled as stable transcript ranges, but they are not treated as the end of the user's turn; the backend reports overall completion only after Speak It closes and finalizes the input stream.

Google's streaming speech guidance separately models speech activity and the
timeout after speech ends; new speech restarts the end timeout
([Google Cloud voice activity timeouts](https://docs.cloud.google.com/speech-to-text/docs/voice-activity-events)). Speak It follows the same safety property. A new transcript always cancels and rebuilds the decision. Fresh microphone activity can also briefly rebase the timer when audio resumes before the recognizer publishes new words.

## Prompt decision

The cue is visual and concise:

> **Still listening…**  
> Take your time. Keep speaking, or tap the pulse when you're finished.

This is clearer than “Are you finished talking?” because the app is not opening
a separate yes/no turn. A spoken “yes” could become part of the captured thought,
and synthesized audio during recording could compete with the microphone or the
exclusive recording session. The visual status does not steal the speaking turn,
the pulse remains the immediate finish control, and the status is a polite
VoiceOver announcement when that accessibility service is active.

## What counts as likely incomplete

The first beta version uses local, deterministic English cues. The endpoint
classifier derives lowercase lexical tokens while treating punctuation and
symbols as boundaries. It therefore reads all of the following tails as the
same spoken ending, **at**:

- `tomorrow at.`
- `tomorrow. At.`
- `tomorrow, at…`
- `tomorrow. “At.”` or `tomorrow. 'At.'`
- `tomorrow (at).`
- `tomorrow.At.`

This normalization is used only for the endpoint decision. Speak It still
displays and persists the recognizer's complete original transcript, including
capitalization and punctuation.

The same lexical representation now controls whether a partial-result update
restarts the timer. If ASR changes `tomorrow at` into `Tomorrow. At.`, the
display updates but the pause clock and **Still listening…** state do not reset.
If ASR adds, removes, or replaces a word, the decision is cancelled and rebuilt
from the new wording. If a volatile result retracts all lexical content, the
pending automatic endpoint is cancelled rather than saving punctuation alone.
This addresses incremental-ASR instability without freezing real word
corrections; research on incremental ASR treats hypothesis stability, revision,
and latency as a three-way operating tradeoff
([Baumann, Atterer, and Schlangen, 2009](https://aclanthology.org/N09-1043.pdf)).

That separation is deliberate. Apple defines automatic punctuation as periods,
question marks, and commas the Speech framework adds to recognition results
([Apple `addsPunctuation`](https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/addspunctuation)). Google likewise describes automatic punctuation as inferred periods, commas, and question marks
([Google automatic punctuation](https://docs.cloud.google.com/speech-to-text/docs/automatic-punctuation)). Microsoft notes that partial recognition text is revisable and that punctuation is unavailable in partial results
([Microsoft captioning guidance](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/captioning-concepts#get-partial-results)). Punctuation is useful presentation, but it is not dependable proof that the speaker has yielded the turn.

The risk is larger in this product's exact scenario: recent primary research
reports that punctuation restoration remains difficult for spontaneous speech
with disfluencies, false starts, and backtracking
([Pulipaka, Sankar, and Dabre, 2025](https://aclanthology.org/2025.findings-ijcnlp.110/)).

- Connectors: **and, or, but, because, then, also, plus**.
- Strong open slots: **at** and **to**.
- Open noun phrases: **a, an, the, my, your, our, their**.
- Explicit hesitations: **um, uh, er, hmm**.
- Open capture frames: **remind me**, **remind me to**, **I need to**, **I want
  to**, **make sure**, **one more thing**, and similar phrases.
- Ambiguous prepositions, list markers, and fillers — such as **for, in, with,
  first, next, like, so, well** — receive the 4-second middle window because
  they can also complete grammatical thoughts.

The classifier deliberately favors avoiding cut-offs. A false positive costs a
few seconds and still offers tap-to-finish; a false negative can discard the
rest of the thought.

## Edge cases and expected behavior

| Edge case | Expected behavior | Remaining risk or rationale |
| --- | --- | --- |
| “Tomorrow at…” or “call my…” | Show the continuation cue and wait up to 8 seconds | Strong evidence that a value or noun is missing |
| “Tomorrow. At.”, quoted/parenthesized **at**, or missing whitespace around punctuation | Wait up to 8 seconds | Endpointing reads lexical words, not inferred formatting |
| “Buy milk and, um…” | Wait up to 8 seconds | Connector/filler punctuation is normalized |
| “Pick up ice wine at LCBO” | Save after 2.1 seconds | The place value completes the phrase |
| “Pick up ice wine at LCBO tomorrow at six” | Save after 2.1 seconds | The time value completes the phrase |
| “Who are you going with?” | May wait 4 seconds | Trailing prepositions can be grammatical in questions; the user can tap to finish |
| A complete clause followed by an unspoken intended second idea | Usually save after 2.1 seconds | No transcript can prove an idea the person has not started; future personalization may help |
| The speaker resumes at the timeout boundary | Continue listening | Transcript updates cancel the timer; fresh audio covers recognizer lag |
| Steady music, traffic, fan, or another speaker | Audio deferral is capped | Raw level is not a perfect voice detector, so noise must not keep the mic open forever |
| Recognizer rewrites the last few words | Reclassify from the newest full transcript | The previous task is cancelled |
| Recognizer changes only case, punctuation, quotes, or whitespace | Keep the existing pause clock and prompt state | Formatting is not new speech and cannot extend listening indefinitely |
| Recognizer retracts all lexical words | Cancel the pending automatic endpoint | Do not save punctuation or an empty volatile hypothesis |
| A backend stops unexpectedly | Use the protected-recording error/recovery path | Backend errors must not masquerade as an intentional end of turn |
| Backend reports final completion | Accept it only after Speak It has closed its input stream | Apple buffer recognition continues until the app explicitly ends audio; analyzer segment finality is not turn finality |
| Long silence after **Still listening…** | Save the partial wording at the 4- or 8-second cap | Saving known words is safer than discarding them or listening indefinitely |
| Manual pulse tap during a longer window | Finish immediately | Explicit user intent always wins |
| VoiceOver enabled | Announce the changed status politely | Verify on a physical device that the announcement does not disturb capture |
| Non-English speech | Falls back mostly to the fast path | The cue lexicon is English-first; locale-specific classifiers are follow-up work |

Apple offers a `SpeechDetector` VAD module, but explicitly warns that aggressive
VAD can drop audio containing speech and reduce transcription accuracy
([Apple `SpeechDetector`](https://developer.apple.com/documentation/speech/speechdetector)). Speak It therefore does not gate or discard captured audio based on its amplitude proxy. Audio activity can only defer a pending endpoint briefly; semantics and a finite deadline remain in control.

## Inclusion and evaluation safeguards

Text fixtures cannot establish that live recognition is equitable. Historical
research found materially different commercial-ASR error rates across speaker
groups, including on identical phrases
([Koenecke et al., PNAS 2020](https://doi.org/10.1073/pnas.1915768117)), while a newer voice-assistant dataset reports substantial individual variation and highlights slower speech, hesitations, and speech differences as endpointing risks
([Feng et al., LREC-COLING 2024](https://aclanthology.org/2024.lrec-main.1309/)). These sources do not measure the current Apple models or prove a specific present-day disparity in Speak It; they establish that a one-speaker or one-accent beta is not an adequate release test.

The real-device beta matrix must therefore cross utterance type with:

- fast, slow, and variable pacing, including long word-finding pauses;
- multiple English accents and dialects, ages, pitches, and voice qualities;
- stutters, repetitions, false starts, self-corrections, and other speech differences;
- quiet, café, traffic, fan, music, nearby speech, and Bluetooth conditions;
- short fragments, long dictation, lists, questions, reminders, names, places,
  dates, times, numbers, and deliberately incomplete thoughts.

Measure false cut-offs and unnecessary waiting separately for each condition.
Do not collect transcript content or infer demographic identity. Recruit varied
opt-in testers, let them self-describe only when necessary for an agreed study,
and keep endpoint telemetry content-free.

## Privacy and analytics

No transcript, final word, audio, name, reminder, or classification token may be
sent to analytics. If rollout instrumentation is added, it should use only a
closed content-free vocabulary, for example:

- endpoint policy: `fast`, `middle`, or `extended`;
- continuation cue shown: yes/no;
- speech resumed after cue: yes/no;
- finish source: automatic, pulse, recognizer final, interruption, or recovery;
- integer pause duration bucket.

The main beta success measure is the **false cut-off rate**: captures where the
person immediately retries or edits because the first capture ended mid-thought.
Because transcript content cannot be logged, collect that through an explicit
content-free tester question or an opt-in post-capture correction reason. Track
median time-to-save separately for fast, middle, and extended policies so protecting slow
speech does not silently make ordinary capture feel worse.

## Release gate

Before shipping, run the automated endpointing tests and physically test:

1. The exact ice-wine phrase with 3-, 5-, and 7-second thinking pauses after **at**.
2. Resuming at approximately 7.5 seconds, including over AirPods.
3. A complete one-line command to confirm the normal 2.1-second path is unchanged.
4. The 4-second middle path with “count me in”, “what I came for”, and “do it next”.
5. Auto-punctuated **at.**, fillers, lists, and a question ending in a preposition.
6. Quiet room, café noise, fan/traffic noise, another nearby speaker, and music leakage.
7. VoiceOver, Reduce Motion, Dynamic Type, screen locked/unlocked routes, interruption,
   Bluetooth route loss, and the protected-recording recovery path.
8. At least 30 alternating fast/middle/extended captures with zero clipped continuations,
   duplicate saves, stuck Live Activities, or microphones left active.
9. The broad utterance matrix above with multiple speakers rather than asking
   one tester to repeat the same sentence.
10. Punctuation-only live rewrites must not restart the pause clock; real word
    additions and corrections must reset and reclassify it.

Tune the token set or the 8-second cap from observed beta outcomes, not from raw
transcript logging. A future learned endpoint model is justified only if the
remaining false-negative and false-positive rates cannot be controlled with this
local policy and only if it preserves Speak It's local-first privacy contract.
