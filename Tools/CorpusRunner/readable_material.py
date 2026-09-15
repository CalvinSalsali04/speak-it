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
})


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
    dead code look covered. The two facts that make it unnecessary are pinned
    in `SealedPathsAreRefusedByName` instead, so if either stops holding the
    suite says so and the guard comes back.

    Note what this reader can legitimately count: a sealed capture that has
    been copied into tuned material is readable in fact once it sits in a file
    anybody opens, and counting a form in it is honest. Finding those is
    `leak-check.py`'s job, not this one's.

    Literal extraction comes from `leak-check.py`, which already owns what
    counts as a string literal in this codebase -- its twelve-character floor,
    its escape handling -- and is covered by its own suite. A second
    implementation here is the defect `EveryCorpusReaderIsDeclared` exists
    for, one language over.

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


def contained_sources():
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

    Reads every source a second time rather than reusing the walk, because a
    guard sharing state with the thing it guards fails with it.
    """
    texts = {}
    for path, read in readers():
        texts[path] = set(read(path))
    out = []
    for a in texts:
        for b in texts:
            if a is not b and texts[a] and texts[a] <= texts[b]:
                out.append((a, b))
    return out


def readers():
    """(path, reader) for every declared source, in reading order."""
    readers = [(p, tsv_utterances) for p in corpus_paths.readable()]
    readers.append((ROOT / GATING, swift_utterances))
    for path in speechlab_files():
        field = utterance_field(path)
        if field is not None:
            readers.append((path, lambda p, f=field: jsonl_utterances(p, f)))
    return readers
