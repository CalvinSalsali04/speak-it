"""Regression coverage for the connective census.

The census produces one kind of claim -- "this form appears in no readable
row" -- and that claim is about to be used as a reason NOT to build something.
A reason not to act has to survive the same scrutiny as a reason to act, and it
fails in a way that is invisible from its output: every path that stops the
census reading produces zeros, and zeros are exactly what the interesting
answer looks like.

So most of what is here checks that the census cannot report absence for the
wrong reason.
"""
import contextlib
import importlib.util
import io
import json
import pathlib
import sys
import unittest

HERE = pathlib.Path(__file__).resolve().parent


def census_module():
    """A freshly executed census, and a freshly executed walk under it.

    The walk used to live in the census, so reloading one reloaded both and
    every test started from the real `ROOT`. Now it is an ordinary importable
    module, which means `sys.modules` caches it: a test that points `ROOT` at
    a temporary tree leaves it pointing there, and the next test reads an
    empty gating corpus and fails with the census's own "a reader that has
    quietly stopped reading" refusal -- the right error about the wrong
    thing. Dropping it from the cache restores the isolation the split took
    away rather than leaving each test to remember.
    """
    sys.modules.pop("readable_material", None)
    spec = importlib.util.spec_from_file_location(
        "connective_census", HERE / "connective-census.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class CensusCase(unittest.TestCase):
    def setUp(self):
        self.census = census_module()

    def run_main(self):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = self.census.main()
        return code, out.getvalue()


class TheRealRunIsSound(CensusCase):
    def test_it_reads_something(self):
        _, distinct, sources = self.census.census()
        self.assertGreater(distinct, 500)
        self.assertGreater(len(sources), 5)

    def test_no_source_is_a_sealed_set(self):
        """The one property that matters more than any count here."""
        import sys
        sys.path.insert(0, str(HERE))
        import corpus_paths
        sealed = {p.resolve() for p in corpus_paths.sealed()}
        _, _, sources = self.census.census()
        for path, _, _ in sources:
            self.assertNotIn((self.census.ROOT / path).resolve(), sealed, path)

    def test_a_form_the_project_does_use_is_found(self):
        """A census that found nothing at all would pass every absence test."""
        counts, _, _ = self.census.census()
        self.assertGreater(counts["and"], 50)

    def test_it_exits_zero_and_prints_a_row_count(self):
        code, text = self.run_main()
        self.assertEqual(code, 0)
        self.assertIn("rows", text)
        self.assertIn("no sealed set read", text)


class OverlappingSourcesAreCountedOnce(CensusCase):
    """The defect that made the first two runs of this census wrong.

    `Tools/SpeechLab/data/renderings.jsonl` is an exact subset of
    `audit/combined-renderings.jsonl`. Listing both read every one of those 324
    rows twice, inflating the denominator by about a quarter and deflating
    every percentage with it. Nothing warned: two real files, both readable,
    both read correctly.

    Once the tree is walked rather than listed, overlap turns out to be the
    normal shape -- SpeechLab keeps a dozen views of one population -- so the
    fix that holds is deduplication, and containment is reported rather than
    refused. These tests pin the denominator, not the absence of overlap.
    """

    def test_the_denominator_is_distinct_utterances(self):
        _, distinct, sources = self.census.census()
        read = sum(here for _, here, _ in sources)
        self.assertLess(distinct, read, "the sources are known to overlap")
        self.assertEqual(distinct, sum(fresh for _, _, fresh in sources))

    def test_reading_a_source_twice_does_not_change_any_count(self):
        """The original defect, reproduced against the current design."""
        before, distinct_before, _ = self.census.census()
        real = self.census.readers()
        self.census.readers = lambda: real + real
        after, distinct_after, _ = self.census.census()
        self.assertEqual(distinct_before, distinct_after)
        self.assertEqual(before, after)

    def test_the_overlap_is_reported_rather_than_hidden(self):
        _, text = self.run_main()
        self.assertIn("already seen", text)
        self.assertIn("not counted twice", text)
        self.assertIn("wholly contained", text)

    def test_the_report_says_the_source_count_is_not_a_population_count(self):
        """Nineteen sources over one population reads as nineteen corpora."""
        _, text = self.run_main()
        self.assertIn("not\n  a count of independent bodies of material",
                      text)

    def test_containment_is_found_where_it_is_known_to_exist(self):
        """A detector returning nothing would make the report silently clean."""
        pairs = self.census.contained_sources()
        self.assertTrue(pairs)
        names = {(a.name, b.name) for a, b in pairs}
        self.assertIn(("renderings.jsonl", "combined-renderings.jsonl"), names)


class AbsenceIsReportedAsAbsenceAndNotAsCoverage(CensusCase):
    def test_absent_forms_are_named_and_qualified(self):
        _, text = self.run_main()
        counts, _, _ = self.census.census()
        absent = [n for n, _ in self.census.CONNECTIVES if not counts[n]]
        if not absent:
            self.skipTest("every form is attested; nothing to qualify")
        for name in absent:
            self.assertIn(name, text)
        self.assertIn("NOT evidence that nobody says the form", text)

    def test_the_report_never_calls_a_count_a_measurement_of_the_parser(self):
        _, text = self.run_main()
        self.assertIn("nothing", text.lower())
        self.assertIn("whether the parser handles", text)


class ASilentReaderIsRefused(CensusCase):
    """Every way the census can stop reading looks like a discovery."""

    def test_a_source_that_yields_nothing_refuses_rather_than_scoring_zero(self):
        real = self.census.readers()
        self.census.readers = lambda: [(p, lambda _p: iter(()))
                                        for p, _ in real]
        with self.assertRaises(ValueError) as caught:
            self.census.census()
        self.assertIn("quietly stopped reading", str(caught.exception))

    def test_the_refusal_reaches_the_exit_code(self):
        real = self.census.readers()
        self.census.readers = lambda: [(p, lambda _p: iter(()))
                                        for p, _ in real]
        code, text = self.run_main()
        self.assertEqual(code, 2)
        self.assertIn("REFUSED", text)
        self.assertNotIn("0.0%", text)


class ARenamedFieldIsRefused(CensusCase):
    """The failure that a walked tree makes possible and a list hid.

    Reading a JSONL file for a field it does not have yields nothing and
    raises nothing. The file stays in the source list, contributes no
    utterance, and every form in it is reported absent -- which is exactly
    what the interesting answer looks like. This census read a `text` field
    from a file whose field is `utterance` and concluded, in a comment, that
    the file held no utterances at all.
    """

    def setUp(self):
        super().setUp()
        import tempfile
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.dir = pathlib.Path(self.tmp.name)

    def write(self, record):
        path = self.dir / "x.jsonl"
        path.write_text(json.dumps(record) + "\n")
        return path

    def test_a_known_field_is_found(self):
        for field in self.census.UTTERANCE_FIELDS:
            path = self.write({field: "call the dentist"})
            self.assertEqual(self.census.utterance_field(path), field)

    def test_an_unknown_speech_shaped_field_refuses(self):
        path = self.write({"spoken_phrase": "call the dentist"})
        with self.assertRaises(ValueError) as caught:
            self.census.utterance_field(path)
        self.assertIn("silently stopped counting", str(caught.exception))

    def test_a_manifest_with_no_speech_shaped_field_is_simply_skipped(self):
        path = self.write({"archive_sha256": "abc", "license": "CC-BY"})
        self.assertIsNone(self.census.utterance_field(path))

    def test_a_named_exception_does_not_refuse(self):
        path = self.write({"text_hash": "abc"})
        self.assertIsNone(self.census.utterance_field(path))

    def test_every_speechlab_file_is_classified_without_raising(self):
        """The real tree passes, or the three tests above prove nothing."""
        for path in self.census.speechlab_files():
            self.census.utterance_field(path)


class SealedPathsAreRefusedByName(CensusCase):
    def test_a_file_sealed_by_speechlab_convention_is_refused(self):
        import tempfile, os
        with tempfile.TemporaryDirectory() as root:
            tree = pathlib.Path(root) / "Tools" / "SpeechLab" / "data"
            tree.mkdir(parents=True)
            (tree / "sealed-renderings.jsonl").write_text("{}\n")
            # The walk reads its own module's ROOT, which is where it now
            # lives; patching the census's copy would leave the real tree
            # walked and the test passing for the wrong reason.
            self.census.readable_material.ROOT = pathlib.Path(root)
            with self.assertRaises(ValueError) as caught:
                self.census.speechlab_files()
            self.assertIn("sealed", str(caught.exception))

    def test_the_real_tree_holds_no_sealed_file_and_is_not_empty(self):
        """Both halves matter: an empty walk refuses nothing, forever."""
        files = self.census.speechlab_files()
        self.assertGreater(len(files), 5)
        for path in files:
            self.assertNotIn("sealed", str(path).lower())

    def test_the_gating_reader_needs_no_refusal_because_it_cannot_reach_one(self):
        """`swift_utterances` deliberately has no sealed check, and these are
        the two facts that make it unnecessary rather than missing.

        One was written. Mutating it away changed no verdict, because every
        path `sealed()` can name is a `.tsv` and that reader opens only
        `.swift`. A branch that cannot fire reads as protection and is not, so
        the guard came out and the reasoning came here. If either half stops
        holding -- a sealed set gains a Swift file, or one moves under the
        gating tree -- this fails and the guard goes back in.
        """
        gating = (self.census.ROOT / self.census.GATING).resolve()
        for path in self.census.corpus_paths.sealed():
            self.assertEqual(path.suffix, ".tsv", f"{path.name} is not a TSV")
            self.assertNotIn(gating, path.resolve().parents,
                             f"{path.name} is inside the gating corpus")


class TheMarkedListInTheBaselineIsRecomputed(CensusCase):
    """The document names which forms are absent; the census decides.

    `LANGUAGE_BASELINE.md` states that four connectives appear in no readable
    utterance, and that sentence is the reason a target is not being built.
    A claim doing that much work cannot be a sentence somebody typed once.

    It is a list rather than a number on purpose. A count drifts by one every
    time anybody adds a devset row and says nothing when it does; the set of
    forms with no attestation at all changes only when the answer changes,
    and when it changes the conclusion changes with it.

    The limit is the same one every marked figure here has: **this catches a
    marked claim that drifts and cannot catch a claim nobody marked.**
    """

    DOC = HERE.parents[1] / "Docs" / "LANGUAGE_BASELINE.md"
    MARKER = r"<!--\s*recomputed:\s*absent-connectives\s+([^>]*?)\s*-->"

    def claimed(self):
        import re
        found = re.findall(self.MARKER, self.DOC.read_text(encoding="utf-8"))
        return [[part.strip() for part in raw.split(",")] for raw in found]

    def measured(self):
        counts, _, _ = self.census.census()
        return [name for name, _ in self.census.CONNECTIVES if not counts[name]]

    def test_the_document_still_carries_the_marker(self):
        """No marker means the test below checks nothing, silently."""
        self.assertEqual(len(self.claimed()), 1)

    def test_the_marked_list_matches_what_the_census_finds(self):
        self.assertEqual(self.claimed()[0], self.measured())

    def test_the_claim_is_about_something(self):
        """An empty absent-list agrees with an empty census perfectly, and
        the sentence in the document would then be true of nothing."""
        self.assertTrue(self.measured())

    def test_the_document_does_not_restate_the_counts(self):
        """The forms are named; the figures stay where something prints them.

        `choice-balance.py` printed a count two generations out of date for as
        long as that block existed, because the document's copy was corrected
        and the script's was not. The rule that came out of it was one copy,
        and this is the section most tempted to make a second.
        """
        import re
        start = self.DOC.read_text(encoding="utf-8").index(
            "## 2026-09-14 — the next target")
        text = self.DOC.read_text(encoding="utf-8")[start:]
        text = text[:text.index("\n## ", 10)]
        for name, _ in self.census.CONNECTIVES:
            # Any digit within a few words of the form, in either order. The
            # first version of this looked for a digit immediately after the
            # backticks, and the sentence that slipped past it -- mine, in the
            # commit that added this test -- read "`also` in 153 utterances".
            near = rf"(?:`{re.escape(name)}`(?:\W+\w+){{0,3}}\W+\d" \
                   rf"|\d(?:\W+\w+){{0,3}}\W+`{re.escape(name)}`)"
            hits = re.findall(near, text)
            self.assertEqual(hits, [], f"the section quotes a count for {name}")


class TheMatcherWorksInBothDirections(CensusCase):
    """A pattern matching nothing reports every form absent; one matching
    everything reports every form attested. Both read as a clean run."""

    def counts_for(self, utterance):
        import re
        found = set()
        for name, pattern in self.census.CONNECTIVES:
            if re.search(pattern, utterance, re.IGNORECASE):
                found.add(name)
        return found

    def test_word_boundaries_are_respected(self):
        self.assertEqual(self.counts_for("android sales"), set())
        self.assertEqual(self.counts_for("sober by tuesday"), set())
        self.assertIn("and", self.counts_for("milk and eggs"))
        self.assertIn("so", self.counts_for("so I need to call"))

    def test_multi_word_forms_match_as_phrases(self):
        self.assertIn("which means", self.counts_for("which means I must go"))
        self.assertEqual(self.counts_for("which meant I must go") - {"then"},
                         set())

    def test_case_is_ignored(self):
        self.assertIn("therefore", self.counts_for("Therefore I will"))


class TheReadersReadWhatTheyClaim(CensusCase):
    def setUp(self):
        super().setUp()
        import tempfile
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.dir = pathlib.Path(self.tmp.name)

    def test_the_tsv_reader_skips_comments_and_the_header(self):
        path = self.dir / "x.tsv"
        path.write_text("# a note\nid\tutterance\tfamily\n"
                        "A1\tbuy milk and eggs\tfam\n\n")
        self.assertEqual(list(self.census.tsv_utterances(path)),
                         ["buy milk and eggs"])

    def test_the_tsv_reader_handles_an_uncommented_header(self):
        """`everyday.tsv` writes its header as an ordinary first line, and the
        devsets comment theirs. A reader that knows only one counts a header
        as a capture, which is a real bug this repository has had."""
        path = self.dir / "x.tsv"
        path.write_text("id\tutterance\nA1\tcall the dentist\n")
        self.assertEqual(list(self.census.tsv_utterances(path)),
                         ["call the dentist"])

    def test_the_jsonl_reader_takes_text_and_ignores_records_without_it(self):
        path = self.dir / "x.jsonl"
        path.write_text(json.dumps({"text": "call mom"}) + "\n"
                        + json.dumps({"archive_sha256": "abc"}) + "\n\n")
        self.assertEqual(list(self.census.jsonl_utterances(path)),
                         ["call mom"])

    def test_the_swift_reader_takes_sentences_and_leaves_identifiers(self):
        (self.dir / "T.swift").write_text(
            'let a = "pick up milk and eggs"\n'
            'let b = "identifier"\n'
            'let c = "todayTabAccessibilityLabel"\n')
        self.assertEqual(list(self.census.swift_utterances(self.dir)),
                         ["pick up milk and eggs"])

    def test_the_swift_reader_descends_and_ignores_other_languages(self):
        nested = self.dir / "Deep" / "Deeper"
        nested.mkdir(parents=True)
        (nested / "T.swift").write_text('let a = "call the dentist tomorrow"')
        (self.dir / "T.py").write_text('a = "call the plumber tomorrow"')
        self.assertEqual(list(self.census.swift_utterances(self.dir)),
                         ["call the dentist tomorrow"])

    def test_the_swift_reader_uses_the_one_harvester(self):
        """Not a second implementation. One module owns what a literal is in
        this codebase, including the twelve-character floor, and two readers
        of one rule is the defect that produced this whole family.

        The owner moved from `leak-check.py` to `readable_material.py` when
        the third consumer arrived: a hyphenated filename cannot be imported
        by statement, so every consumer reached it by path, and the comment
        warning against a third path-importer had already been overtaken by
        one. Moving it is what makes the rule importable rather than copied.

        Pinned by behaviour rather than by identity: a short literal is
        dropped because that harvester drops it, so a private copy that
        forgot the floor fails here.
        """
        self.assertEqual(
            pathlib.Path(self.census.readable_material.__file__).name,
            "readable_material.py",
            "the harvester no longer comes from the module that owns it")
        self.assertIs(self.census.swift_literals,
                      self.census.readable_material.swift_literals)
        (self.dir / "T.swift").write_text(
            'let a = "buy eggs"\n'                 # 9 chars, under the floor
            'let b = "buy eggs and whole milk"\n')
        self.assertEqual(list(self.census.swift_utterances(self.dir)),
                         ["buy eggs and whole milk"])

    def test_the_gating_corpus_is_actually_among_the_sources(self):
        """The omission this reader was added for.

        The first version of this census counted 1908 utterances and called
        that readable material, while `SpeakItTests` -- roughly twice as much
        distinct text, and the material this project reads most -- was not
        read at all. A coverage claim cannot be asserted, which is the lesson
        the census itself is built on, so it is checked here.
        """
        sources = [p for p, _ in self.census.readers()]
        self.assertIn(self.census.ROOT / self.census.GATING, sources)

    def test_the_gating_corpus_is_one_source_and_not_two_hundred(self):
        """A source count is not a population count, and this file says so in
        its own report. Listing every test file separately would make the
        largest single authored population look like the most diverse one."""
        sources = [p for p, _ in self.census.readers()]
        under = [p for p in sources
                 if self.census.GATING in str(p)]
        self.assertEqual(len(under), 1, f"{len(under)} gating sources")


if __name__ == "__main__":
    unittest.main(verbosity=1)
