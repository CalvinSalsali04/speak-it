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
import inspect
import io
import json
import pathlib
import sys
import unittest

HERE = pathlib.Path(__file__).resolve().parent


def corpus_paths_module():
    """The path declaration, imported the way the scans import it."""
    sys.path.insert(0, str(HERE))
    try:
        import corpus_paths
    finally:
        sys.path.pop(0)
    return corpus_paths


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

    def test_the_report_gives_the_number_it_says_the_count_is_not(self):
        """Saying a figure is not a population count leaves the reader with no
        population count, and twenty-eight pairs cannot be reduced by eye."""
        _, text = self.run_main()
        _bodies, maximal = self.census.independent_bodies()
        _, _, sources = self.census.census()
        self.assertIn(f"read {len(sources)} sources as {len(maximal)} "
                      f"populations", text)
        self.assertLess(len(maximal), len(sources),
                        "the sources are known to overlap")

    def test_containment_is_found_where_it_is_known_to_exist(self):
        """A detector returning nothing would make the report silently clean."""
        pairs = self.census.contained_sources()
        self.assertTrue(pairs)
        names = {(a.name, b.name) for a, b in pairs}
        self.assertIn(("renderings.jsonl", "combined-renderings.jsonl"), names)


class TheReductionToPopulationsSurvivesIdenticalSources(CensusCase):
    """A set of equal sources eliminates itself, and the totals look fine.

    Four SpeechLab files hold the same 818 utterances. Asking each source "is
    it wholly inside another" is true for every one of the four, so a
    reduction comparing before grouping drops all four and reports nine
    populations rather than ten. Nothing in the output looks wrong: the number
    is plausible, it moves the direction a reader expects, and no source is
    named. The only symptom is that the survivors stop covering the material
    -- 4683 of 5501 -- which is why that is asserted rather than assumed, and
    why these fixtures are the shape that broke it.
    """

    def reduce(self, groups):
        """Run the reduction over planted sources: a list of lists of texts.

        Patches the walk's own `readers`, because the caller here is
        `source_texts`, which is in that module and calls the name beside it.
        Patching the census's re-export would leave the real tree read and
        this passing for the wrong reason.

        **The rule is the caller, not the module.** This docstring used to say
        "patch `readable_material`, not the census's re-export", stated as
        general -- and it is the special case that happens to be right for
        this fixture. `connective-census.py` does `from readable_material
        import source_texts`, so `main()` holds a binding of its own that
        rebinding the walk's name never reaches. Following the general-sounding
        version, `TheTwoGuardsReadOnePopulation` below counted zero reads of a
        tree the run had just read 170 times. So: find the caller and patch the
        binding it holds, or patch every binding that can reach the function --
        `patch()` below does the latter, which is why it sets both.

        Same family as the `words=STEM_WORDS` default #70 fixed one module
        over: an alias is a second copy of a name meant to have one, and
        rebinding the copy changes the name and not the behaviour. All of them
        fail by passing while measuring nothing, which is the answer that
        raises no alarm.
        """
        planted = []
        for number, texts in enumerate(groups):
            path = self.census.ROOT / f"planted-{number}.tsv"
            planted.append((path, lambda _p, t=tuple(texts): iter(t)))
        self.census.readable_material.readers = lambda: planted
        return self.census.readable_material.independent_bodies()

    def test_sources_holding_the_same_utterances_are_one_body(self):
        same = ["the lease is up in March", "call the dentist tomorrow"]
        bodies, maximal = self.reduce([same, same, same, same])
        self.assertEqual(len(bodies), 1)
        self.assertEqual(len(maximal), 1, "four equal sources are one body")

    def test_equal_sources_do_not_eliminate_each_other(self):
        """The failing shape, stated as the thing that must not happen."""
        same = ["the lease is up in March", "call the dentist tomorrow"]
        _bodies, maximal = self.reduce([same, same, ["a separate thought"]])
        self.assertEqual(len(maximal), 2)
        self.assertEqual(len(frozenset().union(*maximal)), 3,
                         "every planted utterance survives")

    def test_a_source_inside_another_is_not_a_second_population(self):
        whole = ["one thought", "two thought", "three thought"]
        bodies, maximal = self.reduce([whole, whole[:2]])
        self.assertEqual(len(bodies), 2, "the two are not equal")
        self.assertEqual(len(maximal), 1, "the subset is not its own body")

    def test_disjoint_sources_stay_separate(self):
        """A reduction collapsing everything would pass the tests above."""
        _bodies, maximal = self.reduce([["one thought"], ["another thought"]])
        self.assertEqual(len(maximal), 2)

    def test_the_maximal_bodies_cover_the_real_population(self):
        """The control that caught the grouping bug, on the real sources."""
        _bodies, maximal = self.census.independent_bodies()
        _counts, distinct, _sources = self.census.census()
        self.assertEqual(len(frozenset().union(*maximal)), distinct)

    def test_the_coverage_guard_can_actually_fire(self):
        """A refusal nothing reaches is worth nothing -- so reach it.

        The shipped guard is handed the reduction it replaced: one entry per
        source with the equal ones kept apart, so each of a pair is inside the
        other and neither survives. That is the version that reported nine
        bodies and covered 4683 of 5501.

        The precondition is asserted first because this test borrows a
        property of the corpus rather than planting one, and the borrowed
        property can go away: de-duplicate the four equal SpeechLab files and
        the replaced reduction drops nothing, the guard does not fire, and
        this fails with a bare "AssertionError not raised" naming nothing.
        That reads as the guard breaking when it means the fixture stopped
        reproducing the bug, and the two want different responses.
        """
        texts = self.census.source_texts()
        self.assertLess(
            len(set(texts.values())), len(texts),
            "no two sources hold the same utterances any more, so there is "
            "nothing here for a reduction comparing before grouping to "
            "eliminate; if that de-duplication is deliberate, this test "
            "should go too")

        def compared_before_grouping(texts):
            each = list(texts.values())
            maximal = [body for number, body in enumerate(each)
                       if not any(body <= other
                                  for count, other in enumerate(each)
                                  if count != number)]
            return {body: [] for body in each}, maximal

        with self.assertRaises(AssertionError) as raised:
            self.census.independent_bodies(compared_before_grouping)
        self.assertIn("the reduction dropped one", str(raised.exception))

    def test_the_guard_passes_the_reduction_that_is_shipped(self):
        """Otherwise the test above would pass against a guard that always
        raises, which is the same defect one layer up."""
        bodies, maximal = self.census.independent_bodies(
            self.census.reduce_to_bodies)
        self.assertTrue(maximal)
        self.assertLessEqual(len(maximal), len(bodies))

    def test_sources_are_keyed_by_path_and_never_by_name(self):
        """`renderings.jsonl` exists twice under Tools/SpeechLab.

        Keyed on the basename the two merge, which undercounts sources and so
        undercounts the arm deciding whether evidence is concentrated.
        """
        texts = self.census.source_texts()
        names = [path.name for path in texts]
        self.assertGreater(len(names), len(set(names)),
                           "the collision this guards against is gone; if "
                           "that is deliberate, this test should go too")
        self.assertEqual(len(texts), len(self.census.readers()))


class EveryDeclaredSourceReachesTheWalk(CensusCase):
    """A source can be declared and still not be read.

    `corpus_paths` guards the declaration: `unclassified()` fails on a corpus
    nobody classified, `missing()` on a declared file that is gone. Neither
    watches the step after, where `readers()` turns the declaration into the
    list the walk actually reads. Dropping one development set there -- one
    line, `[1:]` on the comprehension -- passed the census suite, the
    observation suite and the scorer suite together.

    It is quiet because the sets are small. The seven development sets are 618
    of 5,501 utterances, so losing one moves the total by a fraction of a
    percent, every count derives from the same shortened list and moves with
    it, and the report prints one fewer source without claiming how many there
    should be. The population this project may read is the denominator under
    every figure it publishes, and it was the one number nothing recomputed.
    """

    def test_every_readable_set_is_one_of_the_readers(self):
        declared = corpus_paths_module().readable()
        self.assertTrue(declared, "no development sets declared at all")
        reading = {path for path, _ in self.census.readers()}
        for path in declared:
            self.assertIn(path, reading,
                          f"{path.name} is declared readable and no reader "
                          f"picks it up, so every figure over readable "
                          f"material silently excludes it")

    def test_the_walk_reads_the_gating_corpus_and_the_speechlab_tree(self):
        """The other two categories, named rather than assumed.

        Dropping either is caught loudly today by tests that compare counts,
        because between them they are 4,992 of the 5,501. That is a property
        of their size, not of a check, and it would stop holding the moment
        someone adds a large development set.
        """
        reading = {path for path, _ in self.census.readers()}
        self.assertIn(self.census.ROOT / self.census.GATING, reading)
        self.assertTrue(
            [path for path in reading
             if path.is_relative_to(self.census.ROOT / self.census.SPEECHLAB)],
            "no SpeechLab file reaches the walk")

    def test_the_walk_reads_nothing_that_is_not_declared(self):
        """The other direction: a reader nobody declared is material from
        nowhere, and a sealed one would be worse than that.

        **The SpeechLab tree gets an answer to "declared" rather than an
        exemption.** The first version of this test skipped every path under
        it with a `continue`, so its name was broader than its check by
        fifteen of the twenty sources. Planting a reader for
        `Tools/SpeechLab2/planted.jsonl` passed it: the skip was written as
        `str(path).startswith(str(ROOT / SPEECHLAB))`, and a sibling whose
        name extends the directory's satisfies that. Both halves of that line
        were wrong and they hid each other.

        A SpeechLab path is declared by being inside the declared tree, so
        that is what it is held to. Deliberately not `speechlab_files()`:
        `readers()` builds those entries out of that function, so asserting
        the result is a subset of it could not fail.

        **What the sealed assertion here is worth, stated rather than
        implied.** It now runs over every reader instead of the non-SpeechLab
        ones, but for a SpeechLab path it cannot fire today: every path
        `corpus_paths.sealed()` can name is a `.tsv` under `Tools/CorpusRunner`
        (4 files, one suffix, none inside the tree), and `speechlab_files()`
        raises on a sealed path before `readers()` sees it. So it is a second
        line on an arrangement `SealedPathsAreRefusedByName` already pins, not
        a live catch, and it is kept only because it costs one line over the
        paths where it can fire. The `continue` is the defect this fixes; the
        sealed widening is tidying.
        """
        paths_module = corpus_paths_module()
        allowed = set(paths_module.readable())
        allowed.add(self.census.ROOT / self.census.GATING)
        speechlab = self.census.ROOT / self.census.SPEECHLAB
        sealed = {path.resolve() for path in paths_module.sealed()}
        read = [path for path, _ in self.census.readers()]
        self.assertTrue(read, "the walk reads nothing at all")
        for path in read:
            self.assertTrue(
                path in allowed or path.is_relative_to(speechlab),
                f"{path} is read and is neither a declared development set, "
                f"the gating corpus, nor inside {self.census.SPEECHLAB}")
            self.assertNotIn(path.resolve(), sealed, f"{path} is sealed")


class TheTwoGuardsReadOnePopulation(CensusCase):
    """The report walks the tree twice, not three times, and says which two.

    One walk is counted and printed. The second is the guards', deliberately
    independent of it, because a guard reading the counted walk's own state
    fails whenever that walk does. The third was an accident of writing the
    two guards separately: each called `source_texts()` for itself, so the
    tree was read three times and the two guards reduced two different reads.

    `contained_sources` said otherwise -- "two guards reading one independent
    copy" -- and had said it since the walk was split out. Nothing related the
    sentence to the calls, so it was true about the design and false about the
    code, and the fix is the code, because one population reduced twice is
    what the sentence describes and the better arrangement.
    """

    def patch(self, name, wrap):
        """Replace `name` under BOTH the walk and the census, with `wrap`.

        Which name has to be patched depends on who calls, and here both do.
        The guards call the module-global inside `readable_material`; the
        report calls the census's own binding, made by `from readable_material
        import ...`, which a later rebinding of the walk's name does not
        reach. Patching one caught the guards and missed the report, and the
        first run of the test below counted zero reads of a tree it had just
        read -- an alias is a second copy of a name meant to have one, and
        this is the third shape of that in three days.
        """
        walk = self.census.readable_material
        real = getattr(walk, name)
        replacement = wrap(real)
        setattr(walk, name, replacement)
        setattr(self.census, name, replacement)
        return real

    def counted_source_texts(self):
        """Count every read of the tree, by whichever name reaches it."""
        calls = []

        def wrap(real):
            def counting():
                calls.append(None)
                return real()
            return counting

        self.patch("source_texts", wrap)
        return calls

    def test_the_report_reads_the_population_once_for_both_guards(self):
        calls = self.counted_source_texts()
        code, _ = self.run_main()
        self.assertEqual(code, 0)
        self.assertEqual(len(calls), 1,
                         "the report should walk the tree once for the "
                         "guards and hand that one population to both")

    def test_both_guards_are_handed_the_same_population(self):
        """One call proves one read; this proves both guards got that read.

        A version calling `source_texts()` once and passing it to only one
        guard, the other reducing a population built some other way, counts
        one call and is the defect this exists to catch.
        """
        seen = []

        def wrap(real):
            def recording(*args, **kwargs):
                bound = inspect.signature(real).bind(*args, **kwargs)
                seen.append((real.__name__, bound.arguments.get("texts")))
                return real(*args, **kwargs)
            return recording

        for name in ("contained_sources", "independent_bodies"):
            self.patch(name, wrap)
        self.run_main()
        self.assertEqual([name for name, _ in seen],
                         ["contained_sources", "independent_bodies"])
        first, second = (population for _, population in seen)
        self.assertIsNotNone(first, "the population was not passed at all")
        self.assertIs(first, second,
                      "the two guards reduced two different reads")

    def test_a_population_handed_in_is_the_one_reduced(self):
        """Otherwise both tests above pass against guards ignoring the
        argument -- they would read three times and count three, but a guard
        that takes the argument and drops it is a real way to write this."""
        walk = self.census.readable_material
        planted = {pathlib.Path("planted-whole.tsv"): frozenset(
                       ["one thought", "two thought", "three thought"]),
                   pathlib.Path("planted-part.tsv"): frozenset(
                       ["one thought", "two thought"])}
        self.assertEqual(
            [(a.name, b.name) for a, b in walk.contained_sources(planted)],
            [("planted-part.tsv", "planted-whole.tsv")])
        bodies, maximal = walk.independent_bodies(texts=planted)
        self.assertEqual(len(bodies), 2)
        self.assertEqual(len(maximal), 1)

    def test_the_shared_population_is_the_whole_one(self):
        """Reading once is only an improvement if the once reads everything.

        Byte-identical output is the obvious control for a refactor and it is
        necessary rather than sufficient: a walk that quietly stopped visiting
        a source would print identically wherever the report does not name
        what it dropped. So this pins the population itself against the
        separate counted walk in `census()`, which is the one number the
        report does print.
        """
        seen = []

        def wrap(real):
            def recording(*args, **kwargs):
                bound = inspect.signature(real).bind(*args, **kwargs)
                seen.append(bound.arguments.get("texts"))
                return real(*args, **kwargs)
            return recording

        self.patch("contained_sources", wrap)
        self.run_main()
        population, = seen
        self.assertIsNotNone(
            population,
            "the report called the guard without a population, so there is "
            "no shared read to check the completeness of")
        self.assertEqual(len(population), len(self.census.readers()),
                         "every declared source is in the shared population")
        _counts, distinct, _sources = self.census.census()
        self.assertEqual(
            len(frozenset().union(*population.values())), distinct,
            "the population the guards reduce holds exactly the utterances "
            "the counted walk counts; if these drift, one of the two walks "
            "has stopped reading something and the report cannot show it")

    def test_each_guard_still_reads_for_itself_when_called_alone(self):
        """Every other test in this file calls them with no population, and
        the census is not the only caller that may exist."""
        calls = self.counted_source_texts()
        self.assertTrue(self.census.contained_sources())
        _bodies, maximal = self.census.independent_bodies()
        self.assertTrue(maximal)
        self.assertEqual(len(calls), 2, "one fresh read each")


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
    """Both readers' sealed-path arguments, kept in one place.

    `speechlab_files` refuses by name and the refusal is exercised.
    `swift_utterances` has no refusal at all, and this class holds the whole
    argument for why it needs none -- both legs of it, because half a pin on
    a removed refusal is what the removal has to be judged on.
    """

    def setUp(self):
        super().setUp()
        import tempfile
        room = tempfile.TemporaryDirectory()
        self.addCleanup(room.cleanup)
        self.dir = pathlib.Path(room.name)

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

    def test_the_gating_reader_never_opens_a_corpus_file(self):
        """The second half of the pin, and it was missing.

        `swift_utterances` has no sealed-path refusal because it cannot reach
        one, and that argument has two legs: everything `sealed()` names is a
        `.tsv`, and this reader opens only `.swift`. The first was pinned. The
        second was not -- the nearest test plants a `.py` file, which shows
        the reader ignores *some* other extension and says nothing about the
        one that matters. Widening the filter to `(".swift", ".tsv")` passed
        the whole suite.

        A dead fallback and a dead refusal are not the same risk. A fallback
        that never fires does nothing; a refusal that never fires reads a
        sealed path. So removing one is only as good as the pin being total,
        and mine was half.
        """
        (self.dir / "T.swift").write_text('let a = "call the dentist tomorrow"')
        #: The planted row is QUOTED on purpose. A bare TSV holds no Swift
        #: string literal, so `swift_literals` returns nothing from it whether
        #: the reader opened it or not, and a fixture that cannot tell those
        #: apart is the defect this test was written against, one layer down.
        #: The first version of this test used an unquoted row and passed on
        #: a reader widened to `(".swift", ".tsv")`.
        (self.dir / "set.tsv").write_text(
            'id\tutterance\nX01\t"the lease ends in March"\n')
        self.assertEqual(list(self.census.swift_utterances(self.dir)),
                         ["call the dentist tomorrow"])

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
