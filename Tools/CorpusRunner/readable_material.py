#!/usr/bin/env python3
"""What material this project may read, and how each kind of it is read.

One owner for the answer to "which sources exist", the way `corpus_paths`
owns "which corpus files exist and how a row is read". Both exist for the
same reason: a fact that every scan works out for itself fans its mistakes
out, and this directory has now produced that defect in two dimensions --
the corpora disagreeing on a column, and the sources disagreeing on what
counts as readable material.

It was split out of `connective-census.py` rather than designed, once a
second and third reader wanted the same walk. The census still owns the
question it asks; this owns the material it asks it of.

**The hyphen is the whole reason for the timing.** `connective-census.py`
and `everyday/leak-check.py` cannot be imported by statement, so every
consumer reached them through `importlib.util.spec_from_file_location` and a
hard-coded relative path. That works and it does not scale: by the time this
module was written, `swift_literals` had three such importers and the
comment beside it saying it "wants a home before a third reader imports it
by path" had been overtaken by the third reader.

WHAT IS AND IS NOT REFUSED HERE. `speechlab_files` refuses a sealed path two
ways, by SpeechLab's filename convention and against `corpus_paths.sealed()`.
`swift_utterances` deliberately refuses nothing, and the docstring there
says why and what pins the argument. The asymmetry is intentional and is the
kind of thing that reads as an oversight, so it is stated at the top too.
"""
import json
import os
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import corpus_paths  # noqa: E402


ROOT = pathlib.Path(__file__).resolve().parents[2]

#: Where SpeechLab keeps its material. Everything under here is walked rather
#: than listed, because a hand-written list is what this census got wrong on
#: its first two runs, in both directions at once: it named one of the ten
#: files that carry utterances, and it excluded `phase2/public/source-records`
#: on the grounds that the file "holds provenance, not utterances" -- a
#: conclusion produced entirely by reading only a `text` field from a file
#: whose field is called `utterance`.
#:
#: `corpus_paths` exists because exactly this happened to the leak check. The
#: lesson did not transfer on its own, so the rule is repeated here: ask the
#: directory, not your memory of it.
SPEECHLAB = "Tools/SpeechLab"

#: The gating corpus. `SpeakItTests/*.swift` holds roughly twice as many
#: distinct multi-word strings as every corpus file combined, and it is the
#: material this project reads and edits most. A census that says "readable
#: material" and leaves it out is the coverage claim this file exists to
#: distrust, made by this file. Found on review of the first version, which
#: counted 1908 utterances and called that readable material.
GATING = "SpeakItTests"

#: Field names that hold an utterance. Closed, and checked for completeness
#: below rather than assumed.
UTTERANCE_FIELDS = ("text", "utterance", "spoken_rendering")

#: What a field name looks like when it holds an utterance. A file carrying
#: none of `UTTERANCE_FIELDS` is skipped silently, which is correct for a
#: manifest and wrong for a schema that renamed its column -- and the second
#: is indistinguishable from the first at the point of skipping. So a skipped
#: file whose keys look like they hold speech fails the run instead.
LOOKS_LIKE_SPEECH = re.compile(
    r"utterance|text|sentence|transcript|rendering|phrase|wording",
    re.IGNORECASE)

#: Keys that match the pattern above and demonstrably do not hold an utterance.
#: Each costs a line, which is the point: the alternative is a pattern loose
#: enough to wave anything through.
NOT_SPEECH = frozenset({
    "text_hash",          # a digest of an utterance, not one
    "rendering_id",       # an identifier
    "rendering_count",
    "original_rendering_id",  # lineage identifier, not an utterance
    "repaired_rendering_id",  # lineage identifier, not an utterance
})


#: SpeechLab `.jsonl` files that `readers()` does not read, declared rather
#: than inferred. Twenty of the thirty-seven under `Tools/SpeechLab` are dropped
#: because `utterance_field` finds nothing in them, and until this list
#: existed that decision was made afresh on every run and recorded nowhere.
#:
#: **Not "holds no speech". Two of them do**, and the first draft of this list
#: said otherwise, because the audit behind it read top-level string values
#: and `utterance_field` reads top-level keys -- the same blind spot twice,
#: which is why nothing contradicted it. Caught in review. What each file
#: holds is written beside it now, and every nested occurrence in the tree,
#: in these twenty files and in the seventeen that are read, is accounted for by
#: `nested_declared_strings` below.
#:
#: The list earns its place anyway, and for the reason it was written: the
#: pattern in `LOOKS_LIKE_SPEECH` is a name-shaped net, so a corpus arriving
#: with its utterances under `line` or `said` matches nothing, drops silently,
#: and the census reports a smaller population in the same calm voice it
#: reports a correct one. `corpus_paths.unclassified()` solved exactly that
#: for `*.tsv` by making the classification **total**, and
#: `speechlab_unclassified()` below is that check one directory over.
#:
#: Paths are relative to the repository root, and a name here that turns out
#: to hold a top-level utterance field fails the run as loudly as one that is
#: missing. A list that can only be too short is the failure mode being fixed.
NOT_READ = {
    # 260 blueprint rows: ids, family labels, and `expected.items[].title`
    # with `facts[]` -- 254 distinct strings naming what the parser should
    # produce, which are contract labels and not anything anybody said.
    "Tools/SpeechLab/data/blueprints.jsonl",
    # 260 rows of `archetype` / `description`, machine-composed from the
    # family's own shape ("single-task with plain semantic context").
    "Tools/SpeechLab/data/family-definitions.jsonl",
    # 137 rows, the same shape one phase on. No nested strings at all.
    "Tools/SpeechLab/phase2/data/semantic-families.jsonl",
    # adjudication: a case id and a verdict per row, plus an annotator's
    # gloss under `review.intended_meaning` and its siblings -- 958 distinct
    # in the combined file. Analysis *about* a capture, in the annotator's
    # words, never the capture.
    "Tools/SpeechLab/phase2/adjudication/reviews.jsonl",
    "Tools/SpeechLab/phase2/adjudication/reviews/"
    "codex-blind-reviewer-a-20260914.jsonl",
    "Tools/SpeechLab/phase2/adjudication/reviews/"
    "codex-blind-reviewer-b-20260914.jsonl",
    "Tools/SpeechLab/phase2/adjudication/reviews/"
    "codex-blind-reviewer-c-20260914.jsonl",
    # 50 rows of the same blueprint shape as `data/blueprints.jsonl`, with
    # the contract nested one level under `blueprint`.
    "Tools/SpeechLab/artifacts/export-for-ai/blueprint-batch.jsonl",
    # HOLDS SPEECH, under `representatives[].text` and
    # `counterexamples[].text` -- 48 distinct, and every one of them is
    # already counted through another source, so reading it would add
    # nothing to the population. `nested_declared_strings` recomputes that.
    "Tools/SpeechLab/artifacts/export-for-ai/failure-pack.jsonl",
    # HOLDS SPEECH, under `capture_context.prior_turns[].text` -- 26
    # distinct, 17 of them counted nowhere else, and the same 17 turns sit
    # under `prior_turns` in four phase2 files this walk does read. Prior
    # turns are the conversation a blueprint sets up around the capture
    # rather than the capture, but that is a judgement and not the reason
    # this file is unread: it is unread because the reader looks at
    # top-level keys. See CONVERSATIONAL_CONTEXT.
    "Tools/SpeechLab/phase2/data/blueprints.jsonl",
    # Repair-review records contain annotator analysis rather than captured
    # speech. Their corresponding utterances are counted through the retained,
    # triaged, challenged, deferred, or excluded case views below this tree.
    "Tools/SpeechLab/phase2/repair/candidate-1/adjudication/reviews.jsonl",
    "Tools/SpeechLab/phase2/repair/candidate-1/decisions/"
    "codex-repair-reviewer-a-20260914.jsonl",
    "Tools/SpeechLab/phase2/repair/candidate-1/decisions/"
    "codex-repair-reviewer-b-20260914.jsonl",
    "Tools/SpeechLab/phase2/repair/candidate-1/decisions/"
    "codex-repair-reviewer-c-20260914.jsonl",
    # The repair map stores before/after evidence and lineage. Both utterance
    # values are already present in corpus case views, so this is provenance,
    # not another body of captured material.
    "Tools/SpeechLab/phase2/repair/candidate-1/repair-map.jsonl",
    "Tools/SpeechLab/phase2/repair/candidate-2/adjudication/reviews.jsonl",
    "Tools/SpeechLab/phase2/repair/candidate-2/decisions/"
    "codex-repair2-reviewer-a-20260915.jsonl",
    "Tools/SpeechLab/phase2/repair/candidate-2/decisions/"
    "codex-repair2-reviewer-b-20260915.jsonl",
    "Tools/SpeechLab/phase2/repair/candidate-2/decisions/"
    "codex-repair2-reviewer-c-20260915.jsonl",
    "Tools/SpeechLab/phase2/repair/candidate-2/repair-map.jsonl",
}

#: Container names whose contents are somebody else's turn in a conversation
#: the capture sits inside, rather than the capture. A blueprint sets up what
#: was said before the user spoke; those turns are material the project wrote
#: to give a capture a context, and counting them as captures would inflate
#: the population with the project's own stage directions.
#:
#: **This is a statement about the key, not about the file.** Four of the five
#: files carrying these turns are read, and read correctly, for the utterance
#: at their top level. A reader that descends and declines a named container
#: is still one rule, applied at every depth.
#:
#: **Matched as the string's immediate parent, never anywhere above it.** The
#: first version asked whether any segment of the key was a declared container,
#: which excuses a string at any depth below a turn -- so a corpus arriving at
#: `context.prior_turns[].nested_corpus[].text` is invisible to a sweep whose
#: whole claim is that it is total. That is a marker standing in for the
#: judgement it approximates, this codebase's recurring defect, arriving in the
#: one place the accounting is supposed to admit nothing. The narrower form
#: costs nothing: every live instance is `container.prior_turns[].text`, the
#: counts are identical either way, and the wider form bought only the hole.
#: Found by the core language thread grading this, by injecting that key into a
#: real file and watching the suite pass.
#:
#: Declared rather than derived, and the honesty is in the two directions it
#: is held: `nested_declared_strings` gives a string under one of these names
#: the reason CONVERSATION and gives a string under any other nested name no
#: reason at all, so an undeclared container carrying material nothing else
#: has counted fails the run; and `conversational_containers_missing` fails on
#: a name here that no longer appears anywhere in the tree, so this cannot
#: quietly become somewhere to put an inconvenient key. That is the bargain
#: `NOT_READ` and `speechlab_misdeclared` already make one level up.
CONVERSATIONAL_CONTEXT = frozenset({"prior_turns", "previous_turns"})

#: The sibling keys that make a string a span of its own row rather than a
#: separate utterance. These are markup offsets and the strings they cut out
#: are not sentences: the nine live ones include `'7 pm'` and `'8'`, so
#: descending would not merely add non-captures to the published population,
#: it would add **tokens**.
#:
#: Named, but never trusted: a holder carrying these is
#: only a span if the offsets actually cut the value out of the record's own
#: utterance, so markup that has drifted from the text it annotates reads as
#: unaccounted for and stops the run rather than being waved through.
SPAN_OFFSETS = ("start_index", "end_index")

#: Why a nested string is not a new utterance. Assigned in this order, so a
#: string gets the strongest reason available to it: what it is beats where
#: it sits, and both beat the bare fact that counting it would change nothing.
CONVERSATION = "inside a named conversational-context container"
SPAN = "a span of its own row's utterance, by its own offsets"
ALREADY_READ = "already read from this tree under another key"


#: Swift string literals, and the reason this is not a one-line regex.
#:
#: It used to be `re.findall(r'"([^"\\]{12,})"', text)` over the whole file,
#: which pairs quote characters left to right without knowing which of them
#: opens a literal. The closing quote of one literal and the opening quote of
#: the next are a perfectly good pair for that pattern whenever the code
#: between them is twelve characters long, so the scan drifts out of phase and
#: harvests the *gaps* instead of the strings. Whether any given utterance is
#: seen then depends on how many quote characters precede it in the file.
#:
#: It is not a rounding error. On `SpeakItTests/SemanticCorpusData*.swift` the
#: old pattern returned 2,465 strings, which reads as thorough, while missing
#: 1,128 of the 1,380 `corpusCase` utterances — 82% of the gating corpus — and
#: padding the count with 1,224 fragments of source code that are not strings
#: at all. Everyday F02 and W17 are `corpusCase` rows in `SemanticCorpusDataG`
#: and sit in the part it could not see, so the overlap check printed
#: `exact collisions 0` about a set with two verbatim rows in the regression
#: net. That is the failure this file exists to make impossible, and the
#: printed total is what hid it: 2,465 reads as more thorough than 2,101.
#:
#: A literal cannot span a line here, so scanning per line keeps an unbalanced
#: quote inside a comment from swallowing the rest of the file.
def swift_literals(text, minimum=12):
    out = []
    for line in text.splitlines():
        for found in re.findall(r'"((?:[^"\\]|\\.)*)"', line):
            if len(found) >= minimum:
                out.append(found)
    return out


def shown(path):
    """A path as a reader would name it, without raising on an outside path.

    `relative_to` throws for anything outside the repository, and every use of
    it here is inside an error message -- so a diagnostic about a stray file
    failed with a different error about the same file, and said nothing about
    what was actually wrong.
    """
    try:
        return path.relative_to(ROOT)
    except ValueError:
        return path


def speechlab_files():
    """Every `.jsonl` under SpeechLab, walked, with sealed paths refused.

    Walked rather than globbed: `rglob` does not descend a symlinked directory,
    and the claim here is about every file in a tree.
    """
    sealed = {p.resolve() for p in corpus_paths.sealed()}
    out = []
    for here, folders, files in os.walk(ROOT / SPEECHLAB, followlinks=True):
        for name in sorted(files):
            if not name.endswith(".jsonl"):
                continue
            path = pathlib.Path(here, name)
            if "sealed" in str(path.relative_to(ROOT)).lower():
                raise ValueError(
                    f"{shown(path)} is sealed by SpeechLab's "
                    f"filename convention and must not be read here")
            if path.resolve() in sealed:
                raise ValueError(
                    f"{shown(path)} is in corpus_paths.sealed()")
            out.append(path)
    return sorted(out)


def swift_utterances(root):
    """Multi-word Swift string literals from the whole gating corpus.

    **One source, not one per file.** Two hundred test files are not two
    hundred populations -- they are one, written here, and the finding this
    census keeps producing is precisely that a source count is not a
    population count. Collapsing them also keeps the empty-source refusal
    meaningful: most individual test files hold no multi-word literal at all,
    so a per-file canary would have to be switched off, and a canary with an
    exception is the check that stopped checking.

    Walked rather than globbed, since `rglob` does not descend a symlinked
    directory and the claim is about a tree.

    **There is deliberately no sealed-path refusal here**, unlike
    `speechlab_files`. One was written and then removed, because mutating it
    away changed no verdict: every path `corpus_paths.sealed()` can name is a
    `.tsv` under `Tools/CorpusRunner`, and this reader opens only `.swift`
    under `SpeakItTests`, so the branch cannot fire. A guard that cannot fire
    is worse than none -- it reads as protection and a test for it would make
    dead code look covered.

    Both facts are pinned in `SealedPathsAreRefusedByName`, so the guard comes
    back if either stops holding. **Both**, because the first version pinned
    only that `sealed()` names `.tsv` files: widening this reader to
    `(".swift", ".tsv")` passed the whole suite. A dead fallback and a dead
    refusal are not the same risk -- a fallback that never fires does nothing,
    a refusal that never fires reads a sealed path -- so a removal is worth
    exactly what its pin is worth, and half a pin is worth nothing. Caught by
    the evaluation thread asking which half had been written rather than
    taking the removal on trust.

    Note what this reader can legitimately count: a sealed capture that has
    been copied into tuned material is readable in fact once it sits in a file
    anybody opens, and counting a form in it is honest. Finding those is
    `leak-check.py`'s job, not this one's.

    Literal extraction is `swift_literals` above -- its twelve-character
    floor, its escape handling -- and `everyday/leak-check.py` imports it from
    here. A second implementation would be the defect
    `EveryCorpusReaderIsDeclared` exists for, one language over.

    Until this module existed that sentence read the other way round: the
    literal scanner lived in `leak-check.py`, this was the borrower, and the
    paragraph named it as the owner. The move reversed the direction and the
    paragraph did not follow, so the file written to establish one owner
    spent a commit naming the wrong one. Flagged in review rather than by any
    check here, because nothing holds a docstring to the imports above it --
    which is the same gap `TheMarkedListInTheBaselineIsRecomputed` closes for
    a figure and nobody has closed for a provenance claim.

    Single-word literals are dropped. They are overwhelmingly identifiers,
    keys and accessibility labels rather than anything anybody said. That is a
    judgement, and it is the only filter between this source and a large pile
    of non-speech, so it is stated here rather than buried in a comprehension.
    """
    for here, _folders, files in os.walk(root, followlinks=True):
        for name in sorted(files):
            if not name.endswith(".swift"):
                continue
            path = pathlib.Path(here, name)
            for literal in swift_literals(
                    path.read_text(encoding="utf-8", errors="ignore")):
                if len(literal.split()) > 1:
                    yield literal


def utterance_field(path):
    """Which field holds the utterance, or None when the file holds none.

    Raises when a file holds no known field but has one that looks like it
    should: that is a rename, and a rename skipped silently takes a whole
    corpus out of the denominator without changing a single line of output.

    **TOP LEVEL ONLY, both halves.** `record.get(field)` and `record.items()`
    see the keys of the record and nothing inside a list or a dict under them,
    so a corpus whose utterances are nested reads here as holding none -- and
    the rename refusal above, which exists precisely to stop a corpus going
    missing, is blind in the same place and so agrees. Two files in this tree
    are in that position today; `nested_declared_strings` accounts for every
    nested occurrence in the tree, in those two and in the files that are
    read, and says why each one is not a new utterance.

    Stated rather than fixed, and the measurement is now the reason rather
    than the deferral. Teaching this to descend would add 25 strings to the
    population and not one utterance: 17 are prior turns, and 8 are annotation
    spans cut out of their own row's text. So the limit stays, and the guard
    that matters is the one watching for a nested string that is neither.
    What is not acceptable is the limit being undocumented, which is how a
    declaration of "holds no speech" came to be written about a file that
    holds twenty-six strings of it.
    """
    keys = set()
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        record = json.loads(line)
        for field in UTTERANCE_FIELDS:
            if isinstance(record.get(field), str) and record[field]:
                return field
        keys.update(k for k, v in record.items() if isinstance(v, str))
    suspicious = sorted(k for k in keys
                        if k not in NOT_SPEECH and LOOKS_LIKE_SPEECH.search(k))
    if suspicious:
        raise ValueError(
            f"{shown(path)} carries no field named "
            f"{' or '.join(UTTERANCE_FIELDS)}, but has {suspicious} — either "
            f"a schema renamed its utterance column, in which case this "
            f"census has silently stopped counting a corpus, or the name is "
            f"a coincidence and belongs in NOT_SPEECH")
    return None


def tsv_utterances(path):
    """Every data row's utterance, from the one reader that knows the layout.

    This used to take column two and skip a row whose first cell read `id`,
    which is right for every devset and right by luck: the corpora here do not
    agree on a column, and a header is identified by the names it carries
    rather than by a cell reading `id`. It was the sixth reader to work the
    format out for itself, and `EveryCorpusReaderIsDeclared` caught it on the
    merge that introduced the list -- which is the list doing its job on the
    first file to arrive after it.

    Reading it right matters more here than in most readers. A census reports
    absence, so a reader that silently drops rows or picks up a header reports
    a form as rarer than it is, and the conclusion this tool exists to reach
    is exactly "there is not enough material". Every one of its failures looks
    like the finding.
    """
    for _number, _cid, utterance in corpus_paths.utterances(path):
        yield utterance


def jsonl_utterances(path, field=None):
    """Every utterance in a JSONL file, under whichever field carries them."""
    field = field or utterance_field(path)
    if field is None:
        return
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        value = json.loads(line).get(field)
        if isinstance(value, str) and value:
            yield value


def contained_sources(texts=None):
    """Pairs of sources where one's utterances are a subset of another's.

    Reported, not refused, and the distinction is worth the paragraph.

    This began as a refusal, written when the sources were a hand-declared
    pair and one turned out to be an exact subset of the other. Once the tree
    is walked instead of listed, the same check fires on twenty-eight pairs:
    SpeechLab keeps a dozen views of one utterance population -- candidates,
    accepted candidates, a review set, a stratified sample, an adjudicated
    copy -- and overlap between them is the design, not a mistake.

    What the original defect actually did was inflate the denominator, and
    deduplication fixes that on its own, whatever the sources overlap. So the
    refusal was guarding a property already held elsewhere, and keeping it
    would have meant either excluding real material or maintaining a list of
    permitted overlaps, which is a hand-written list again.

    It stays as output because a reader deciding how much independent evidence
    is here should see that twelve sources are not twelve populations.

    Reads every source a second time rather than reusing the census walk,
    because a guard sharing state with the thing it guards fails with it. The
    thing guarded here is the counted walk in `census()`, so independence from
    THAT is the property; independence from the other guard buys nothing.

    So the population is an argument, and the caller reads it once and hands
    the same one to both guards. The docstring claimed that before the code
    did it -- "two guards reading one independent copy" was written while each
    guard called `source_texts()` for itself, three reads of the tree where
    two are the design. Passing None still reads a fresh copy, which is what
    every test that calls these directly relies on.
    """
    texts = source_texts() if texts is None else texts
    out = []
    for a in texts:
        for b in texts:
            if a is not b and texts[a] and texts[a] <= texts[b]:
                out.append((a, b))
    return out


def source_texts():
    """`{path: frozenset of utterances}`, read fresh, keyed by full path.

    By path and never by name. `renderings.jsonl` exists twice under
    `Tools/SpeechLab`, so a dictionary keyed on the basename silently merges
    two sources into one and undercounts every figure derived from it -- the
    same defect `readable_pairs` had, one module over.
    """
    return {path: frozenset(read(path)) for path, read in readers()}


def reduce_to_bodies(texts):
    """`{utterances: [path]}` and the bodies inside no other, from `texts`.

    Separate from the guard that checks it, so the guard can be handed a
    reduction that is wrong -- which is the only way to know the guard runs.
    Same shape as `observation.self_check(measure)`, for the same reason.
    """
    bodies = {}
    for path, utterances in texts.items():
        bodies.setdefault(utterances, []).append(path)
    maximal = [body for body in bodies
               if not any(body < other for other in bodies)]
    return bodies, maximal


def independent_bodies(reduce=None, texts=None):
    """`(bodies, maximal)` — how many populations the sources amount to.

    `contained_sources` prints the pairs and leaves the reader arithmetic that
    cannot be done by eye: containment pairs over twenty-five sources is not a
    number anyone reduces while reading. This reduces it, because "the source
    count is not a count of independent bodies" is worth saying only if the
    count it is not is available. It is 25 sources, 22 distinct bodies and 12
    inside no other -- and one of those ten is two thirds of the material and
    is test fixtures, which is a different sentence from "twenty-five sources".

    Two steps, and the order is the whole difficulty. Sources holding the same
    utterances are one body, grouped FIRST; then a body wholly inside another
    is not a second population, by strict subset.

    Grouping first is not tidiness. Four SpeechLab files hold the same 818
    utterances, so asking each source "is it inside another" is true for every
    one of the four, all four drop and none survives -- a set that eliminates
    itself. That was the first version here, and it reported nine bodies
    rather than ten with nothing amiss in the output: a plausible number,
    moving the way a reader expects, naming no source. The only symptom was
    that the survivors covered 4683 of 5501 utterances. So the coverage is
    asserted rather than assumed, and `reduce` is an argument so a test can
    hand the guard the reduction it replaced and watch it raise.

    `reduce` stays the first parameter because the tests that hand it a wrong
    reduction pass it positionally, and `texts` arriving in front of it would
    have been read as the population.
    """
    texts = source_texts() if texts is None else texts
    bodies, maximal = (reduce or reduce_to_bodies)(texts)
    covered = frozenset().union(*maximal) if maximal else frozenset()
    union = frozenset().union(*texts.values()) if texts else frozenset()
    if covered != union:
        raise AssertionError(
            f"the {len(maximal)} maximal bodies cover {len(covered)} of "
            f"{len(union)} utterances; every source is inside a maximal body "
            f"by construction, so this means the reduction dropped one")
    return bodies, maximal


def speechlab_unclassified(files=None, declared=None):
    """Every SpeechLab `.jsonl` that is read by nobody and declared by nobody.

    Must be empty, and that is the whole value: `readers()` drops a file the
    moment `utterance_field` returns None, and a drop leaves no trace in any
    output. Twenty of the thirty-seven files under `Tools/SpeechLab` are dropped
    today, so the difference between "twenty checked files hold no speech" and
    "the census has silently stopped reading a corpus" is not visible anywhere
    a reader looks.

    `corpus_paths.unclassified()` made the same decision total for `*.tsv`
    after two scans got their file lists wrong in opposite directions. This is
    that check for the other arm of the walk: the classification is total, or
    it is a convention, and a convention omits silently.

    `files` and `declared` exist so a test can hand this a tree it controls
    and watch it report, the way `independent_bodies` takes `reduce`. Every
    caller in this repository passes neither, and a test asserts that, because
    a guard a caller can narrow is a guard the caller can switch off.
    """
    files = speechlab_files() if files is None else files
    declared = NOT_READ if declared is None else declared
    return sorted(path for path in files
                  if utterance_field(path) is None
                  and str(path.relative_to(ROOT)) not in declared)


def _strings(value, path="", holder=None):
    """Every `(dotted key, string, holder)` in a decoded JSON record, at depth.

    A list contributes `[]` to the key rather than an index, so the twenty-six
    strings under `capture_context.prior_turns[].text` report as one key.

    `holder` is the dict the string is a value of, which is what lets a
    caller ask the string's own siblings about it -- the offsets beside an
    annotation span, say. A list does not become a holder: its elements keep
    the dict above them, so a string in a list of strings is still held by the
    record that named the list.
    """
    if isinstance(value, dict):
        for key, inner in value.items():
            yield from _strings(inner, f"{path}.{key}" if path else key, value)
    elif isinstance(value, list):
        for inner in value:
            yield from _strings(inner, f"{path}[]", holder)
    elif isinstance(value, str) and value:
        yield path, value, holder


def _container_names(key):
    """The key's segments with any `[]` removed, for matching a container."""
    return [part.replace("[]", "") for part in key.split(".")]


def _is_a_span_of(holder, value, owner):
    """Whether `value`'s own offsets cut it out of `owner`, exactly.

    The verification is the point. Asking only whether a holder carries
    offsets would let markup that has drifted from the text it annotates
    through, and drifted markup is the case where a string under `text` really
    might be something nobody said. So the offsets must reconstruct the value
    from the record's own utterance, character for character, or this is
    False and the string goes to the caller unaccounted for.
    """
    start, end = (holder or {}).get(SPAN_OFFSETS[0]), (holder or {}).get(
        SPAN_OFFSETS[1])
    return (isinstance(owner, str) and isinstance(start, int)
            and isinstance(end, int) and owner[start:end] == value)


def nested_declared_strings(files=None, known=None):
    """Every nested occurrence of a declared utterance field, with its reason.

    Yields `(relative path, dotted key, string, reason)`, where `reason` is
    `CONVERSATION`, `SPAN`, `ALREADY_READ`, or **None** for a string this
    module cannot account for. None is the whole point of the function.

    `utterance_field` reads `record.get(field)` and `record.items()`, so the
    reader sees the top level and nothing under it, and so does the
    `LOOKS_LIKE_SPEECH` refusal that exists to catch a corpus going missing.
    Two guards agreeing is not two guards when both are blind the same way.
    What closes that is not a list of the files it happens to affect -- such a
    list can only name files `utterance_field` returns None for, so it is
    blind by construction to a nested key inside a file that has a top-level
    utterance column, which is where 8 of the 25 turned out to be. What closes
    it is making the accounting **total**, the way `corpus_paths.unclassified`
    made the `*.tsv` classification total after two scans got their file lists
    wrong in opposite directions.

    So this descends through every SpeechLab file, read and unread alike, and
    every string it finds under a name from `UTTERANCE_FIELDS` below the top
    level must have a reason it is not new speech. A string with none is a
    corpus that has arrived under a nested key, which is the thing worth being
    stopped by.

    **Total over strings, not over container names.** An undeclared container
    whose strings are all already read gets `ALREADY_READ` and passes. That is
    correct rather than a hole: reading it would move no figure. The guard
    fires on material, not on shape.

    **`ALREADY_READ` is set membership, not provenance.** A string gets it
    when an identical string is read somewhere in this tree, which is the right
    test for "would counting this move a figure" and is not what the label
    sounds like: a genuinely new nested utterance that happens to duplicate an
    existing one is absorbed by it and never reaches the residual. Correct for
    protecting a population, and worth knowing before anybody reads the 481 as
    a claim about where those strings came from.

    **`SPAN` is unreachable in the twenty files with no top-level utterance
    column.** `owner` is None there, so `_is_a_span_of` cannot return True and
    a span in such a file lands as unaccounted for. That is the right direction
    to fail in -- a span with no row to cut it out of is not something this
    module should wave through -- but reading `_is_a_span_of` alone suggests
    spans are recognised everywhere, and they are recognised only where there
    is an utterance to reconstruct them from.

    `known` is the population to count a string as already read against, and
    defaults to everything `readers()` reads. It is a parameter because
    computing it here would make this circular -- `readers()` is what produces
    it -- which is also why this is a test rather than a refusal inside
    `readers()`: every consumer would pay for a second full read of the tree.
    """
    files = speechlab_files() if files is None else files
    if known is None:
        known = frozenset().union(*source_texts().values())
    for path in files:
        top = utterance_field(path)
        for line in path.read_text(encoding="utf-8").splitlines():
            if not line.strip():
                continue
            record = json.loads(line)
            owner = record.get(top) if top else None
            for key, value, holder in _strings(record):
                leaf = key.split(".")[-1].replace("[]", "")
                if leaf not in UTTERANCE_FIELDS or "." not in key:
                    continue
                names = _container_names(key)
                if names[-2] in CONVERSATIONAL_CONTEXT:
                    reason = CONVERSATION
                elif _is_a_span_of(holder, value, owner):
                    reason = SPAN
                elif value in known:
                    reason = ALREADY_READ
                else:
                    reason = None
                yield str(shown(path)), key, value, reason


def nested_speech_unaccounted_for(files=None, known=None):
    """The nested strings with no reason: `{relative path: {key: strings}}`.

    Empty is the passing state, and a non-empty result is not a stylistic
    complaint. It says a file in this tree carries material under a name this
    project has committed to meaning "an utterance", nothing else in the tree
    has counted it, and it is neither somebody else's turn nor a span of the
    row it sits in -- so the census is reporting a population that is missing
    it, in the same calm voice it reports a correct one.
    """
    out = {}
    for name, key, value, reason in nested_declared_strings(files, known):
        if reason is None:
            out.setdefault(name, {}).setdefault(key, set()).add(value)
    return out


def conversational_containers_missing(files=None, declared=None):
    """Declared container names that appear nowhere in the tree.

    The half a declaration is never failed by, and the reason `NOT_READ` has
    `speechlab_misdeclared` beside it. A name that has been renamed out of the
    data goes on excusing nothing forever, and the comment above it goes on
    describing a tree that no longer exists -- which is how a list stops being
    checked at all. So a stale name is a failure, and the set stays as small
    as the data makes it.
    """
    files = speechlab_files() if files is None else files
    declared = CONVERSATIONAL_CONTEXT if declared is None else declared
    seen = set()
    for path in files:
        for line in path.read_text(encoding="utf-8").splitlines():
            if not line.strip():
                continue
            for key, _value, _holder in _strings(json.loads(line)):
                seen.update(_container_names(key))
    return sorted(name for name in declared if name not in seen)


def speechlab_misdeclared(files=None, declared=None):
    """Declared not-a-corpus names that are missing, or that do hold speech.

    The mirror of the check above, and it is the half that is easy to leave
    out. A list that can only be too short turns into somewhere to put a file
    that has become inconvenient: declare it, and the census stops counting it
    with no failure anywhere. So a declared name that `utterance_field` can
    read is a failure, and so is a name that is not on disk -- the second
    because a rename would otherwise leave the list describing a tree that no
    longer exists, which is how a list stops being checked at all.

    Returns `(name, why)` pairs, so the message says which of the two it is.
    """
    files = speechlab_files() if files is None else files
    declared = NOT_READ if declared is None else declared
    walked = {str(path.relative_to(ROOT)): path for path in files}
    out = []
    for name in sorted(declared):
        path = walked.get(name)
        if path is None:
            out.append((name, "is declared as holding no utterance, but the "
                              "walk does not reach it: renamed, deleted, or "
                              "moved out of the tree"))
            continue
        field = utterance_field(path)
        if field is not None:
            out.append((name, f"is declared as holding no utterance, but "
                              f"carries {field!r}: it is a corpus, and the "
                              f"census is not counting it"))
    return out


def readers():
    """(path, reader) for every declared source, in reading order.

    Refuses before it returns anything if the SpeechLab classification is not
    total. A dropped file changes every figure downstream and prints nothing,
    so the refusal belongs here rather than in a test: the census, the
    observation measure and the leak check all come through this function, and
    a guard held by one suite is a guard the other consumers do not have.

    The cost is that adding a metadata file to SpeechLab stops the census
    until somebody classifies it. That is the same bargain `speechlab_files`
    already makes for a sealed path and `utterance_field` for a renamed
    column, and it is one line to settle.
    """
    stray = speechlab_unclassified()
    if stray:
        raise ValueError(
            f"{len(stray)} SpeechLab file(s) hold no field named "
            f"{' or '.join(UTTERANCE_FIELDS)} and are not in NOT_READ, so "
            f"they are being dropped from every figure with no record: "
            f"{', '.join(str(shown(p)) for p in stray)} — read each one and "
            f"either "
            f"declare it or add its field to UTTERANCE_FIELDS")
    wrong = speechlab_misdeclared()
    if wrong:
        raise ValueError(
            "NOT_READ no longer describes the tree: "
            + "; ".join(f"{name} {why}" for name, why in wrong))
    readers = [(p, tsv_utterances) for p in corpus_paths.readable()]
    readers.append((ROOT / GATING, swift_utterances))
    for path in speechlab_files():
        field = utterance_field(path)
        if field is not None:
            readers.append((path, lambda p, f=field: jsonl_utterances(p, f)))
    return readers
