# Public-data adapter audit

Verified 2026-09-13 from upstream project pages. No corpus was downloaded or
integrated during this audit.

## Status summary

| Dataset | Source and license evidence | Useful contribution | Mapping limit | Actual integration status |
|---|---|---|---|---|
| PRESTO | [Official repository](https://github.com/google-research-datasets/presto), CC BY 4.0 | Human-generated contextual dialogue; explicit disfluency, code-mixing, revision partitions; prior turns and seeded contacts/lists/notes | Its assistant-oriented semantic parses and conversation state do not define Speak It route, persistence, review, or notification behavior | Registry plus generic flat-JSONL staging only. Native records use `inputs` and nested `metadata.example_id`, so preprocessing or a native adapter is still required. |
| MASSIVE | [Official NOTICE](https://github.com/alexa/massive/blob/main/NOTICE.md), CC BY 4.0 | Broad multilingual single-turn wording, assistant requests, entities, questions, and code-switching | Foreign intent/slot labels do not determine Today vs Memory, item splitting, cancellation scope, or ambiguity policy | Registry plus generic staging adapter. The existing `Tools/UnderstandingLab` has limited MASSIVE-derived text, but SpeechLab has imported zero reviewed contracts. |
| Taskmaster | [Official repository](https://github.com/google-research-datasets/Taskmaster); [TM-1 license notice](https://github.com/google-research-datasets/Taskmaster/blob/master/TM-1-2019/README.md), CC BY 4.0 for TM-1 | Longer spoken/written task dialogues, repairs, cross-turn references, domain vocabulary, and more natural discourse | Dialogues are service transactions; turns cannot be flattened blindly into one Speak It capture. Release-specific licenses and capture boundaries need review | Registry plus generic staging adapter only. No native dialogue flattener or reviewed blueprint mappings. |
| SLURP text | [Official project/paper](https://aclanthology.org/2020.emnlp-main.588/) and MASSIVE's [NOTICE](https://github.com/alexa/massive/blob/main/NOTICE.md), which states SLURP text is CC BY 4.0 | Single-turn home-assistant language, entity variety, and paired speech/transcription research potential | Home-assistant actions and slots are not Speak It labels. Audio rights were not established by the evidence reviewed here | Text-only registry/staging adapter. Audio remains explicitly out of scope until its exact terms are verified. |

## Conversion contract

For every candidate, preserve dataset/release, source record ID, original text,
language, context, license, attribution, and modifications. A reviewer then:

1. decides whether the utterance is plausible as a Speak It capture;
2. authors a SpeechLab blueprint without consulting parser output;
3. explicitly sets item boundaries, routes, temporal/location/person scope,
   polarity/operations, and ambiguity policy;
4. marks uncertain cases `review` or `preserve-only`;
5. has a second reviewer approve safety-critical and ambiguous contracts;
6. only then links the source rendering to the reviewed blueprint.

Source intents remain provenance. They are never copied into expected Speak It
semantics. Until this workflow has produced reviewed pairs, none of the four
datasets should be described as integrated.
