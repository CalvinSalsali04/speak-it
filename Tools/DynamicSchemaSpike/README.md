# DynamicSchemaSpike

One question, asked narrowly, before any of it becomes architecture:

**Can `DynamicGenerationSchema` bound a span schema at runtime from the atom
count of the capture in front of us, and can the segment count be bounded the
same way?**

If yes, an out-of-range atom id is *unrepresentable* rather than merely
refusable, and a six-word capture cannot ask to become ten errands. If no, the
prototype uses a static generous range plus deterministic out-of-range
rejection, and that limitation gets written down rather than discovered later.

```bash
./Tools/DynamicSchemaSpike/spike.sh
```

## Why five programs instead of one

Each variant is compiled on its own, and the script reports which ones
compiled. A wrong guess about one API shape then costs one answer instead of
all of them — this is being written on a machine with no Swift toolchain, so
every shape here is a guess until a Mac says otherwise.

| | asks | needs a model |
|---|---|---|
| A1 | a runtime `.range` guide on `Int` | no |
| A2 | an `anyOf` enumeration of this capture's ids | no |
| B | runtime `minimumElements`/`maximumElements` on an array | no |
| C | are those bounds *honoured* when generating, not just accepted | yes |
| D | decode the ids, validate them, slice the original transcript | yes |

A1 is the preferred form. A2 is the fallback that needs no numeric guide at
all and bounds the ids by construction; it is here because if A1 is absent,
A2 is a better answer than a static range.

C and D print `SKIPPED` where there is no Apple Intelligence device, so the
first three answers are available on any Mac.

## What it does not do

It reads no corpus, touches no sealed set, and changes nothing in the app.
The captures are three constructed strings, one of which is `RO02`
(*"Sarah gave me her new number"*) — six atoms, which on the first device run
returned eleven segments and ten invented toiletry errands. Under a cap of
three it cannot. That is the falsifier worth watching in C and D.

## Atoms

`atoms.swift` holds the source-unit definition the rest of this work will use.
They are **atoms, never tokens**: Apple's tokenizer is Apple's business and we
never see one. An atom is a whitespace-delimited run of the original transcript
holding a `Range<String.Index>` into that exact string, so `atoms[3]...atoms[7]`
is one substring of one string. There is no byte offset anywhere, and a model
that is one atom off is visibly one word off rather than silently one byte off.

A transcript with no atoms yields no id range and never reaches the model. It
is still the user's capture and is still saved.
