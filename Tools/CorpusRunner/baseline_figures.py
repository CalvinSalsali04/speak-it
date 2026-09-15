#!/usr/bin/env python3
"""The population figures in `LANGUAGE_BASELINE.md`, emitted rather than typed.

`connective-census.py` already says the rule this file exists to enforce:
*a figure this project could compute and does not should grow the thing that
computes it.* The section this file owns ignored that rule. The population
total, the ten-row table of maximal populations, the by-kind table, the
per-set overlap table and the headline percentage all went in as prose, and
**nothing recomputed any of them.** One list in the same document sits behind
a marker and is checked on every run; these were not, and the difference was
never a decision anybody made.

WHAT GOES STALE, AND HOW QUIETLY. Every one of those figures moves when
anybody adds a multi-word string literal to `SpeakItTests`, because the gating
corpus is two thirds of the population. A pull request adding three test cases
moves the total, the gating row, all ten shares, three of the four by-kind
rows and the headline percentage -- and the document goes on stating the old
ones in the same confident voice.

That is measured, not feared. **#79 was a word-order fix in the parser and
touched no file in this directory**; it landed 43 test literals, moved the
population by 42 distinct utterances, and moved the development-set overlap
from 109 to 110 because one of its new tests is verbatim a `routed.tsv` row.
Every figure in the section was wrong within the hour and every check was
green. The overlap move is the section's own thesis -- a row that motivated a
fix becomes the test for that fix -- arriving as a fresh instance that nothing
recorded.

SO THE FIGURES ARE NOT MARKED, THEY ARE GENERATED. Marking each number would
make a stale one fail, which is better than nothing, and would then leave
whoever hit the failure to re-derive the lot by hand -- the same hand-typing
that put four wrong figures in this document on 2026-09-15. A generated block
has no hand step to get wrong: `--write` rewrites it, the diff is the change,
and the test compares the committed text to a fresh computation.

WHAT IS AND IS NOT IN THE BLOCK. The block holds the tables and the sentences
that carry a figure. The argument around it -- why maximal populations overlap,
what two thirds being fixtures means for the project -- stays hand-written
outside the markers, because that is the part a person is supposed to have
thought about. If an argument needs a number, the number comes into the block.

NO SEALED SET IS READ. Everything here comes from `readable_material.readers()`
walking committed text, the same walk the census uses.
"""
import collections
import difflib
import re
import pathlib
import posixpath
import sys
import textwrap

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import corpus_paths  # noqa: E402
import readable_material  # noqa: E402
from readable_material import GATING, ROOT, SPEECHLAB, shown  # noqa: E402

#: The document, and the two comments that bracket the generated region. They
#: are asymmetric on purpose: a single marker can be deleted and the region
#: then has no end, which reads as "there is nothing to check" -- the failure
#: mode every guard in this directory has been bitten by. Both must be present
#: or `marked_region` raises.
DOC = ROOT / "Docs" / "LANGUAGE_BASELINE.md"
BEGIN = "<!-- begin generated: population -->"
END = "<!-- end generated: population -->"

#: The three kinds the by-kind table splits the population into. Decided by
#: path, and stated here rather than inside a comprehension because it is the
#: judgement the whole table rests on: `SpeakItTests` is material written to
#: exercise the parser, the SpeechLab tree is generated from blueprints, and a
#: development set is material written to sound like somebody talking.
FIXTURES, GENERATED, SPOKEN = "fixtures", "generated", "spoken"

#: Where a development set lives. Named rather than left as the
#: else-branch of the other two, so that a source in neither tree is
#: unclassified and refused instead of quietly becoming spoken material.
DEVSETS = ROOT / "Tools" / "CorpusRunner" / "devsets"

#: The three trees, as directories a path is inside rather than as strings a
#: path contains. `in` was the first spelling, and it absorbs a sibling whose
#: name merely extends one of the three: `Tools/SpeechLab2` read as generated,
#: `SpeakItTestsExtra` as fixtures, and `CorpusRunner/devsets2` as **spoken** --
#: the same direction the removed catch-all fell, and the same figure this
#: document argues from. So the guard below did not refuse the unanticipated
#: source it exists for; it misfiled it.
#:
#: Latent rather than live: `readers()` yields only `corpus_paths.readable()`,
#: `ROOT/SpeakItTests` and the walk under `ROOT/Tools/SpeechLab`, so no such
#: path arrives today. It is still worth three lines, because a classifier that
#: mis-classifies is not the same thing as a guard that cannot fire -- refusing
#: what nobody anticipated is this function's whole job.
#:
#: It is also `corpus_paths`' bug from #80, in new code written after #80
#: landed. Fixing the instance is not checking the siblings.
TREES = ((ROOT / GATING, FIXTURES),
         (ROOT / SPEECHLAB, GENERATED),
         (DEVSETS, SPOKEN))

#: Small counts read as words in prose and as digits in a table, which is how
#: the hand-written section read before it was generated. Only the range the
#: section actually uses; anything larger stays a numeral rather than being
#: spelled by a rule nobody checked.
WORDS = ("no", "one", "two", "three", "four", "five", "six", "seven",
         "eight", "nine", "ten", "eleven", "twelve")


def word(count):
    """`4` as "four", and anything past the list as a numeral."""
    return WORDS[count] if count < len(WORDS) else f"{count:,}"


def kind_of(path):
    """Which of the three kinds a source belongs to, or None for neither.

    **No catch-all.** The first version ended `return SPOKEN`, so every source
    was classified by construction, the coverage check in `figures` could not
    fire, and a test asserting that every source is classified could not fail
    -- three things that look like a guard and are one unreachable branch.
    A mutation putting a fourth kind of source in the tree passed it.

    It matters which way the catch-all fell. A new corpus landing anywhere
    outside these three trees would have been counted as a development set,
    and the development-set total is the one figure in this document used as
    evidence about how much material sounds like somebody talking.

    **Containment, not substring.** The second version asked `GATING in
    str(path)`, which answers a question about spelling rather than about
    location: a sibling directory extending one of the three names was
    absorbed into it instead of refused, and `devsets2` landed on `spoken`
    -- the catch-all's direction again, by a different route. See `TREES`.
    """
    # `is_relative_to` is reflexive, which is what classifies the gating
    # source: `readers()` yields the `SpeakItTests` directory itself rather
    # than the files under it. An `or path == tree` beside this reads as the
    # case that handles it and is a branch nothing can reach.
    for tree, kind in TREES:
        if path.is_relative_to(tree):
            return kind
    return None


def label_for(paths):
    """How a population is named in the table, given the sources holding it.

    Several sources holding one body is the case worth naming: four SpeechLab
    files hold the same 818 utterances, and a table listing them separately
    would report four populations where there is one. So the label says how
    many files agree rather than picking one of them and hiding the rest.
    """
    names = sorted(str(shown(path)) for path in paths)
    if len(names) == 1:
        only = names[0]
        return f"the gating corpus in `{only}`" if only == GATING \
            else f"`{only}`"
    common = posixpath.commonpath(names)
    return f"`{common}`, in {word(len(names))} byte-identical files"


def figures(texts=None):
    """Every number the generated block states, from one read of the tree.

    One read, because two reads of a moving tree can disagree and the reader
    would have no way to tell -- the same reason `contained_sources` takes the
    population as an argument.
    """
    texts = readable_material.source_texts() if texts is None else texts
    if not texts:
        raise ValueError(
            "no sources were read at all, which would generate a block of "
            "zeroes that agrees with itself perfectly and describes nothing")
    bodies, maximal = readable_material.independent_bodies(texts=texts)
    union = frozenset().union(*texts.values())

    rows = sorted(((len(body), label_for(bodies[body])) for body in maximal),
                  key=lambda row: (-row[0], row[1]))
    #: A body several sources hold identically. Named in full below the
    #: table, because "in four byte-identical files" tells a reader that the
    #: reduction happened and not which four sources it collapsed -- and the
    #: point of the reduction is that a form appearing only there reads as
    #: four sources and is one.
    shared = sorted(((len(body), sorted(str(shown(path))
                                        for path in bodies[body]))
                     for body in maximal if len(bodies[body]) > 1),
                    key=lambda row: -row[0])

    by_kind = {}
    stray = []
    for path, utterances in texts.items():
        kind = kind_of(path)
        if kind is None:
            stray.append(str(shown(path)))
            continue
        by_kind.setdefault(kind, set()).update(utterances)
    if stray:
        raise ValueError(
            f"{len(stray)} source(s) are in none of the three trees this "
            f"document splits the population by, so the by-kind table would "
            f"leave them out while the total counts them: "
            + ", ".join(sorted(stray)))
    for name in (FIXTURES, GENERATED, SPOKEN):
        if not by_kind.get(name):
            raise ValueError(
                f"no source was classified as {name!r}, so the by-kind table "
                f"would report a kind of material as absent from a "
                f"repository that has a directory full of it")
    fixtures, generated, spoken = (by_kind[FIXTURES], by_kind[GENERATED],
                                   by_kind[SPOKEN])
    #: No "do the three kinds cover the union" check here, deliberately. With
    #: the stray refusal above, every source is in exactly one kind and the
    #: union is covered by construction -- so such a check could never fire,
    #: which is the unreachable branch `kind_of` was just cured of. The
    #: property worth checking is arithmetic rather than coverage, and
    #: `test_the_three_kinds_cover_the_population` checks it on the four
    #: figures the table prints.

    overlap = []
    for path, utterances in sorted(texts.items(), key=lambda kv: str(kv[0])):
        if kind_of(path) != SPOKEN:
            continue
        if not utterances:
            #: An empty development set would divide by zero in the sort
            #: below, and print a row of zeroes if it did not. `census()`
            #: refuses a source that yields nothing; this walk does not go
            #: through it, so it says the same thing itself.
            raise ValueError(
                f"{shown(path)} yielded no utterances, so its row in the "
                f"overlap table would read 0 of 0 — a reader that has "
                f"quietly stopped reading, reported as a set nobody shares")
        overlap.append((len(utterances & fixtures), len(utterances),
                        str(shown(path).name)))
    overlap.sort(key=lambda row: (-row[0] / row[1], row[2]))

    in_two_sets = _in_more_than_one(texts, SPOKEN)
    #: Which pairs of development sets hold the double-counted rows. The
    #: hand-written section named them and a generated one that only counts
    #: them would be a worse document than the one it replaced -- a reduction
    #: that says "seven" and not "which seven" is the shape of finding this
    #: file keeps producing about source counts.
    where = {}
    for path, utterances in texts.items():
        if kind_of(path) != SPOKEN:
            continue
        for utterance in utterances & fixtures:
            where.setdefault(utterance, []).append(shown(path).stem)
    pairs = collections.Counter(
        tuple(sorted(names)) for names in where.values() if len(names) > 1)
    return {
        "distinct": len(union),
        "sources": len(texts),
        "bodies": len(bodies),
        "maximal": len(maximal),
        "populations": rows,
        "shared": shared,
        "column_sum": sum(count for count, _ in rows),
        "fixtures": len(fixtures),
        "generated": len(generated),
        "spoken": len(spoken),
        "fixtures_only": len(fixtures - spoken - generated),
        "spoken_only": len(spoken - fixtures - generated),
        "both": len(spoken & fixtures),
        "not_spoken": len(fixtures | generated),
        "fixtures_and_generated": len(fixtures & generated),
        "generated_and_spoken": len(generated & spoken),
        "overlap": overlap,
        "overlap_sum": sum(count for count, _, _ in overlap),
        "overlap_in_two_sets": _in_more_than_one(texts, SPOKEN, fixtures),
        "overlap_pairs": sorted(pairs.items(), key=lambda kv: (-kv[1], kv[0])),
        "in_two_sets": in_two_sets,
    }


def _in_more_than_one(texts, kind, restrict=None):
    """Utterances appearing in more than one source of `kind`.

    The reason two columns in this document do not add up to their own
    headings, and a number worth computing rather than explaining away: the
    excess is exactly this, and when it stops being exactly this the
    explanation in the document has become wrong.
    """
    seen = {}
    for path, utterances in texts.items():
        if kind_of(path) != kind:
            continue
        for utterance in utterances:
            if restrict is None or utterance in restrict:
                seen[utterance] = seen.get(utterance, 0) + 1
    return sum(1 for count in seen.values() if count > 1)


#: The column the generated prose wraps to. The document is hand-wrapped at
#: this width and a block wrapping differently reads as pasted in, which is
#: how a generated section stops being read.
WIDTH = 78


def paragraph(text):
    """One paragraph, wrapped, with its runs of whitespace collapsed.

    Wrapped as a whole rather than emitted line by line. Emitting `**bold**`
    per line closes and reopens the emphasis on every line, which renders as
    several bold runs rather than one sentence -- the first version of this
    did exactly that, and the only symptom was that the rendered document
    looked slightly wrong to nobody in particular.
    """
    return textwrap.fill(" ".join(text.split()), width=WIDTH)


def block(figs=None):
    """The generated region, exactly as it appears between the markers."""
    f = figures() if figs is None else figs
    total = f["distinct"]
    out = [BEGIN, ""]

    out.append(paragraph(f"""
        Sources holding exactly the same utterances are one body, grouped
        first. Then a body wholly inside another is not a second population.
        {f['sources']} sources reduce to {f['bodies']} distinct bodies and
        **{f['maximal']} that sit inside no other**:"""))
    out.append("")
    out.append(f"| utterances | share of {total:,} | population |")
    out.append("|---:|---:|---|")
    for count, label in f["populations"]:
        out.append(f"| {count:,} | {100.0 * count / total:.1f}% | {label} |")
    for count, names in f["shared"]:
        common = posixpath.commonpath(names)
        out.append("")
        out.append(paragraph(
            f"The {word(len(names))} files under `{common}` are the same "
            f"{count:,} utterances {word(len(names))} times: "
            + ", ".join(f"`{name[len(common):].lstrip('/')}`"
                        for name in names)
            + ". A form appearing only there reads as "
              f"{word(len(names))} sources and is one."))
    out.append("")
    out.append(paragraph(f"""
        **That column sums to {f['column_sum']:,} and its shares to
        {100.0 * f['column_sum'] / total:.1f}%, because the
        {word(f['maximal'])} populations are maximal rather than disjoint.**
        A body inside no other body may still overlap one. The excess of
        {f['column_sum'] - total:,} counts an utterance once for every
        additional maximal population that contains it. Only the union,
        {total:,}, is a total."""))
    out.append("")
    out.append("### By kind, and the one place two kinds overlap")
    out.append("")
    #: Both halves of this sentence are conditional on their own figures. A
    #: sentence that says "share nothing" and then prints a number is the
    #: defect this whole file exists to stop, and generating it would be the
    #: same defect with a fresher number in it.
    disjoint = f["fixtures_and_generated"] == f["generated_and_spoken"] == 0
    pairs = ("Two of the three pairs share nothing: not one utterance is in "
             f"both `{GATING}` and the SpeechLab tree, and not one is in both "
             "the SpeechLab tree and a development set."
             if disjoint else
             f"{f['fixtures_and_generated']} utterances are in both "
             f"`{GATING}` and the SpeechLab tree, and "
             f"{f['generated_and_spoken']} are in both the SpeechLab tree and "
             f"a development set.")
    out.append(paragraph(f"""
        {pairs} The development sets and the fixtures overlap by {f['both']},
        so the three kinds are {f['fixtures']:,} + {f['generated']:,} +
        {f['spoken']:,} = {f['fixtures'] + f['generated'] + f['spoken']:,}
        against a union of {total:,} and do not add up. Written out so that
        they do:"""))
    out.append("")
    out.append(f"| kind | utterances | share of {total:,} |")
    out.append("|---|---:|---:|")
    for label, count in (
            ("test fixtures only", f["fixtures_only"]),
            ("generated renderings (the SpeechLab tree)", f["generated"]),
            ("development sets only", f["spoken_only"]),
            ("in both a development set and a fixture", f["both"])):
        out.append(f"| {label} | {count:,} | {100.0 * count / total:.1f}% |")
    out.append(f"| **total** | **{total:,}** | |")
    out.append("")
    out.append(paragraph(f"""
        **{100.0 * f['not_spoken'] / total:.1f}% of everything this project
        may read — {f['not_spoken']:,} of {total:,} — is either a fixture
        written to exercise the parser or a rendering generated from a
        blueprint.** The material written to look like somebody talking is
        {f['spoken']} utterances, of which {f['spoken_only']} exist nowhere
        else."""))
    out.append("")
    out.append(f"### The {f['both']} are not spread evenly, and where they "
               f"land is the interesting part")
    out.append("")
    out.append("| development set | also a fixture | of |")
    out.append("|---|---:|---:|")
    for count, size, name in f["overlap"]:
        share = "" if not count else f" ({100.0 * count / size:.1f}%)"
        out.append(f"| `{name}` | {count} | {size}{share} |")
    out.append("")
    #: Rendered from the tuple rather than by unpacking two names. Nothing
    #: stops an utterance sitting in three development sets, and the version
    #: that unpacked a pair would have raised on the day it happened rather
    #: than saying so.
    named_pairs = ", ".join(
        f"{word(count)} in " + " and ".join(f"`{name}`" for name in names)
        for names, count in f["overlap_pairs"])
    out.append(paragraph(
        f"""**That column sums to {f['overlap_sum']} against a heading of
        {f['both']}**, for the same reason one level down:
        {f['overlap_in_two_sets']} of the {f['both']} sit in two development
        sets each and are counted in both rows — {named_pairs}.
        {f['overlap_sum']} − {f['overlap_in_two_sets']} = {f['both']}."""
        if f["overlap_in_two_sets"] else
        f"""That column sums to {f['overlap_sum']}, which is the heading
        exactly: no development-set utterance that is also a fixture sits in
        a second development set."""))
    out.append("")
    out.append(END)
    return "\n".join(out)


#: A per-family row in a gap table names its family and, in brackets, how many
#: pairs that figure was measured over: `| restart (4) | 4/4 -> 4/4 | ...`.
#: The bracket is what makes the row checkable, and it is the half that goes
#: stale first -- a development set grows, the scores stay where they were, and
#: the table goes on asserting a number about a population that has moved.
#: `restart` was measured over four pairs and `rambling.tsv` now holds six.
FAMILY_ROW = re.compile(r"^\|\s*`?([a-z][a-z0-9-]*)`?\s*\((\d+)\)\s*\|")

#: The two halves of a twinned development set: the same content written
#: twice under one id stem, so a measurement is the gap between the twins.
#: Read off the family labels rather than the ids, because an id convention is
#: a spelling and the label is what the row claims to be.
#:
#: These two words are DECLARED, and deriving them instead does not work.
#: Pairing suffixes by shape reads `routed.tsv` as a family `reported` with
#: halves `cancellation` (4 rows) and `day` (13) -- a false twin, and one that
#: would then refuse the run for being unpaired. So the pair is written down,
#: and `twinned_families` refuses rather than returning nothing when the data
#: stops using these words.
TWIN_HALVES = ("clean", "rambling")


def twinned_families(paths=None):
    """`{path: {family: pairs}}` for every readable set written as twins.

    Recomputed from the development sets, never declared. Which sets are
    twinned, which families they carry and how many pairs each holds are all
    read off the `family` column, so the answer moves when the data does --
    which is the whole point, since the failure being caught is a document
    asserting a count the data no longer has.

    Refuses when a family's two halves disagree in size. An unpaired twin is
    not a stale figure, it is a set that has stopped being twinned, and a gap
    measured across it means nothing; reporting it as a count would hide that.

    Refuses again when NOTHING is twinned, because `TWIN_HALVES` is declared
    and a declared word is one somebody can rename. An empty result is not a
    clean bill of health -- `stale_family_rows` over an empty derivation
    reports no stale row and no missing family, the same answer it gives for a
    table that is genuinely current -- so it is not returned as one.

    The two refusals divide the ways that happens, which was measured rather
    than assumed: renaming ONE half (`-rambling` to `-spoken`) already fires
    the unpaired refusal above, because the other half is still counted and
    the family is then 8 against 0. What reaches this one is the set leaving
    the derivation whole -- both halves renamed at once, the `family` column
    renamed, the file gone -- where nothing is counted at all and there is no
    disagreement to notice.

    What neither can see is a SECOND twinned set arriving under different
    half-names: this one stays non-empty, no refusal fires, and the new set
    contributes nothing. Stated rather than guarded, because the guard would
    be the derivation the comment on `TWIN_HALVES` rules out.
    """
    paths = corpus_paths.readable() if paths is None else paths
    out = {}
    for path in sorted(paths):
        halves = collections.defaultdict(collections.Counter)
        for row in _family_column(path):
            family, _, half = row.rpartition("-")
            if family and half in TWIN_HALVES:
                halves[family][half] += 1
        families = {}
        for family, counts in halves.items():
            sizes = {counts[half] for half in TWIN_HALVES}
            if len(sizes) != 1:
                raise ValueError(
                    f"{shown(path)}: `{family}` has "
                    f"{counts[TWIN_HALVES[0]]} clean rows and "
                    f"{counts[TWIN_HALVES[1]]} spoken ones, so it is not a "
                    f"twinned family any more and a gap measured across it "
                    f"is not a gap between twins")
            families[family] = sizes.pop()
        if families:
            out[str(shown(path))] = families
    if not out:
        raise ValueError(
            f"no readable development set has a family label ending in "
            f"`-{TWIN_HALVES[0]}` and `-{TWIN_HALVES[1]}`, so either the twin "
            f"convention has been renamed or the twinned set is gone. Nothing "
            f"is being compared against the per-family gap tables, and a "
            f"check with nothing to compare reports no stale row -- which "
            f"reads as the tables being current. Update TWIN_HALVES to the "
            f"words the data uses now")
    return out


def _family_column(path):
    """The `family` cell of every data row, or nothing when there is no such
    column.

    Through `corpus_paths`, never by splitting the file here. The first
    version of this did split it here, and `test_score.py` refused it by name:
    this directory has produced six readers that each worked the
    tab-separated format out for themselves, and that guard exists so there is
    no seventh. It was right to. Reading a corpus a new way is how a scan
    picks up a header as data or drops the rows a comment convention hides,
    and the figure it then reports looks exactly like a correct one -- which
    is the defect this whole module was written against, arriving inside it.

    The column is found by name from the header rather than by position,
    because the corpora here do not agree on a layout.
    """
    lines = path.read_text(encoding="utf-8").splitlines()
    header = corpus_paths.header_row(lines)
    names = [name.lower() for name in header] if header else []
    if "family" not in names:
        return
    at = names.index("family")
    for _number, cells in corpus_paths.data_rows(path):
        if at < len(cells) and cells[at]:
            yield cells[at]


def stale_family_rows(text=None, twinned=None):
    """Per-family rows citing a population the development set no longer has.

    Returns `(mismatched, unrowed)`. `mismatched` is
    `[(family, cited, actual)]` for a row whose bracket disagrees with the
    set; `unrowed` is `[(family, pairs)]` for a twinned family with no row at
    all -- which matters because the table introduces itself as *the*
    per-family gaps, so a family missing from it is a claim of completeness
    that has quietly stopped being true.

    A row is recognised as a per-family row by its label being a twinned
    family name, so the table is matched to its development set by what the
    data holds rather than by a declared line range or file name. A set-level
    row such as `routed (116)` names a file and not a family, and is left to
    the population block, which already generates it.

    That means the whole document is scanned, and a line anywhere in its two
    and a half thousand that happens to read `| long (5) |` is reported even
    though it is nowhere near a gap table. That is the intended direction.
    Scoping the scan would mean naming the table by line range or by heading,
    and a line range goes stale exactly as the bracket does while a heading is
    a spelling; a false report names a line somebody can look at in a second,
    and a missed one is the failure the check was written for.

    **A count written in prose is out of reach and stays out of reach.** The
    same section says `coherent-long` is "7/7 on destination" and calls them
    "those seven rows", where the set now holds eleven, and no bracket check
    can see that. Matching counts in sentences would mean a regex over prose
    deciding which numbers are denominators, which is the kind of net this
    directory distrusts everywhere else. The general form is a per-section
    fingerprint -- a dated section records the set state it was measured over,
    older sections keep theirs because they are records, and the newest
    section's fingerprint must match the data -- and that is its own change.
    """
    text = DOC.read_text(encoding="utf-8") if text is None else text
    twinned = twinned_families() if twinned is None else twinned
    known = {family: pairs
             for families in twinned.values()
             for family, pairs in families.items()}
    mismatched, seen = [], set()
    for line in text.splitlines():
        found = FAMILY_ROW.match(line)
        if not found:
            continue
        family, cited = found.group(1), int(found.group(2))
        if family not in known:
            continue
        seen.add(family)
        if cited != known[family]:
            mismatched.append((family, cited, known[family]))
    unrowed = sorted((f, n) for f, n in known.items() if f not in seen)
    return sorted(mismatched), unrowed


#: A section records the shape the development set had when it was measured:
#:
#:     *Measured over `rambling.tsv` at 57 rows.*
#:
#: Visible prose rather than an HTML comment, because a marker only a script
#: can see is a marker nobody maintains -- and this one has to be written by
#: hand, once, by whoever reports a measurement.
MEASURED_OVER = re.compile(
    r"Measured over\s+`([a-z][a-z0-9_-]*\.tsv)`\s+at\s+(\d+)\s+rows")


def devset_rows(paths=None):
    """`{filename: data rows}` for every readable development set.

    The shape a fingerprint is compared against. Rows rather than families,
    deliberately: `stale_family_rows` already checks the per-family brackets,
    and what this adds is the half that check cannot reach -- a count written
    in prose. The same section that cites `restart (4)` also calls
    `coherent-long` "those seven rows" where the set now holds eleven, and no
    amount of parsing table brackets finds that sentence. A whole-set count
    does not find it either, but it fires on the same cause and says which
    set moved and by how much, which is what sends somebody back to read the
    section.
    """
    paths = corpus_paths.readable() if paths is None else paths
    return {path.name: sum(1 for _ in corpus_paths.data_rows(path))
            for path in sorted(paths)}


def fingerprints(text=None):
    """Every recorded measurement shape, in document order.

    Returns `[(filename, rows)]`. Order is the point: the last fingerprint
    for a set is the live one, the ones before it are records of runs that
    happened, and a record is not stale for describing the past correctly.
    """
    text = DOC.read_text(encoding="utf-8") if text is None else text
    return [(found.group(1), int(found.group(2)))
            for found in MEASURED_OVER.finditer(text)]


def stale_fingerprints(text=None, rows=None):
    """`[(filename, recorded, actual)]` where the live fingerprint has moved.

    **Only the last fingerprint for each set is checked.** An earlier one
    describes a set state that really was the state when that run happened,
    and failing it would be asking a dated record to change, which is the
    thing this file's own corrections argue against.

    This is deliberately not a check on which sections *ought* to carry a
    fingerprint. Deciding that mechanically means a heuristic for "does this
    section report a measurement", and the obvious ones misfire badly: a
    section merely naming `rambling.tsv` in a source table, with an unrelated
    rate somewhere in it, reads as a measurement of the rambling set. A
    heuristic standing in for that judgement is the defect this module keeps
    removing, so the judgement stays with whoever writes the section and what
    is mechanical is the consequence -- once a fingerprint is written, the
    day its set changes, the run fails.

    The failure therefore arrives on the next data change rather than at the
    moment somebody omits a fingerprint. That is weaker than it sounds: the
    omission costs nothing until the set moves, and when the set moves is
    exactly when the figures went wrong.
    """
    text = DOC.read_text(encoding="utf-8") if text is None else text
    rows = devset_rows() if rows is None else rows
    live = {}
    for name, recorded in fingerprints(text):
        live[name] = recorded
    out = []
    for name, recorded in sorted(live.items()):
        if name not in rows:
            out.append((name, recorded, None))
        elif rows[name] != recorded:
            out.append((name, recorded, rows[name]))
    return out


def marked_region(text):
    """`(start, end)` of the generated region, or a refusal saying which.

    Refuses on a missing marker rather than returning nothing to check, which
    is the shape of every guard in this directory that turned out not to run.
    """
    start, end = text.find(BEGIN), text.find(END)
    if start < 0 or end < 0:
        missing = [name for name, at in (("begin", start), ("end", end))
                   if at < 0]
        raise ValueError(
            f"{shown(DOC)} is missing its {' and '.join(missing)} marker, so "
            f"there is no generated region to check and every figure in that "
            f"section is unverified prose again")
    if end < start:
        raise ValueError(
            f"{shown(DOC)} has its end marker before its begin marker")
    return start, end + len(END)


def main(argv):
    text = DOC.read_text(encoding="utf-8")
    try:
        start, end = marked_region(text)
    except ValueError as why:
        print(f"baseline figures REFUSED: {why}")
        return 2
    fresh = block()
    if "--write" in argv:
        DOC.write_text(text[:start] + fresh + text[end:], encoding="utf-8")
        print(f"wrote {len(fresh.splitlines())} lines into {shown(DOC)}")
        return 0
    if text[start:end] == fresh:
        print(f"baseline figures OK — {shown(DOC)} matches a fresh walk")
        return 0
    print(f"baseline figures STALE — {shown(DOC)} disagrees with the corpus.")
    print("Run `python3 Tools/CorpusRunner/baseline_figures.py --write` and")
    print("read the diff; do not retype the numbers.\n")
    try:
        for line in difflib.unified_diff(
                text[start:end].splitlines(), fresh.splitlines(),
                fromfile="committed", tofile="measured", lineterm=""):
            print(line)
    except BrokenPipeError:
        #: The first thing anybody does with a long diff is pipe it to `head`,
        #: and a traceback there reads as the tool being broken rather than
        #: the document being stale, which is the opposite of the message.
        pass
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
