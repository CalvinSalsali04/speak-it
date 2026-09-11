"""Tests for the mutation generator.

These check the properties the instrument depends on, not the wording of any
one mutation. If a mutation is not meaning-preserving, every disagreement it
reports downstream is noise, so that is what is tested here.
"""

import random
import unittest
from pathlib import Path

import mutate


class MeaningPreservation(unittest.TestCase):
    """Every strict family must leave the words that carry the meaning intact."""

    SENTENCE = "Today I need to go to Lucky Star, and then buy socks at Mooji at 4pm"

    def content_words(self, text):
        skip = set(mutate.FILLERS) | set(w for p in mutate.PREAMBLES for w in p.split())
        skip |= set(w for s in mutate.SIGN_OFFS for w in s.split())
        skip |= {"or", "actually", "no", "wait", "sorry", "i", "mean"}
        # Conjunctions are function words: swapping "then" for "after that"
        # preserves the sequence, which is the meaning that has to survive.
        skip |= set(w for c in mutate.CONJUNCTIONS for w in c.split())
        words = [w.strip(".,;:").lower() for w in text.split()]
        return [w for w in words if w and w not in skip]

    def test_strict_families_keep_every_content_word(self):
        rng = random.Random(1)
        for family, (_, strength) in mutate.FAMILIES.items():
            if strength != "strict":
                continue
            for seed in range(25):
                produced = mutate.mutations_for(
                    self.SENTENCE, random.Random(seed), [family]
                )
                for m in produced:
                    original = self.content_words(m.base)
                    after = self.content_words(m.mutated)
                    # Contraction rewrites "want to" as "wanna" by design, so
                    # it is checked by its own test rather than by word survival.
                    if family == "contraction":
                        continue
                    missing = [w for w in original if w not in after]
                    self.assertEqual(
                        [], missing,
                        f"{family} lost {missing} from {m.mutated!r}",
                    )
        del rng

    def test_contraction_only_rewrites_the_obligation(self):
        m = mutate.mutations_for("I want to call Dave", random.Random(0), ["contraction"])
        self.assertEqual(1, len(m))
        self.assertEqual("I wanna call Dave", m[0].mutated)

    def test_restart_keeps_the_original_sentence_whole(self):
        for seed in range(20):
            produced = mutate.mutations_for(self.SENTENCE, random.Random(seed), ["restart"])
            for m in produced:
                self.assertTrue(
                    m.mutated.endswith(m.base),
                    f"restart did not leave the original intact: {m.mutated!r}",
                )

    def test_proper_noun_swap_stays_inside_one_kind(self):
        """A shop must not become a person: that changes what is being asked."""
        for seed in range(30):
            shop = mutate.mutations_for(
                "Buy socks at Mooji", random.Random(seed), ["proper-noun"]
            )
            for m in shop:
                replacement = m.mutated.replace("Buy socks at ", "")
                self.assertIn(replacement, mutate.STORE_NAMES)
            person = mutate.mutations_for(
                "Call Dave tomorrow", random.Random(seed), ["proper-noun"]
            )
            for m in person:
                replacement = m.mutated.replace("Call ", "").replace(" tomorrow", "")
                self.assertIn(replacement, mutate.PERSON_NAMES)

    def test_proper_noun_swap_is_structure_not_strict(self):
        produced = mutate.mutations_for(
            "Buy socks at Mooji", random.Random(0), ["proper-noun"]
        )
        self.assertEqual(1, len(produced))
        self.assertEqual("structure", produced[0].strength)
        self.assertNotIn("Mooji", produced[0].mutated)


class NoTrivialCases(unittest.TestCase):
    def test_inapplicable_families_produce_nothing(self):
        # No conjunction, no name, no obligation to contract, no punctuation.
        produced = mutate.mutations_for(
            "call mom", random.Random(0),
            ["conjunction", "proper-noun", "contraction", "unpunctuated", "lowercased"],
        )
        self.assertEqual([], produced, f"expected no mutations, got {produced}")

    def test_a_mutation_never_equals_its_base(self):
        rng = random.Random(7)
        for utterance in ["Buy milk", "Remind me to call Dave tomorrow at 4"]:
            for m in mutate.mutations_for(utterance, rng):
                self.assertNotEqual(m.base.strip(), m.mutated.strip())


class Reproducibility(unittest.TestCase):
    def test_same_seed_gives_the_same_mutations(self):
        a = mutate.mutations_for("Today buy socks at Mooji then call Dave", random.Random(3))
        b = mutate.mutations_for("Today buy socks at Mooji then call Dave", random.Random(3))
        self.assertEqual(a, b)


class SealedSets(unittest.TestCase):
    def test_reading_the_heldout_set_is_refused(self):
        sealed = Path("Tools/CorpusRunner/heldout/heldout.tsv")
        with self.assertRaises(SystemExit) as raised:
            mutate.read_utterances(sealed)
        self.assertIn("sealed", str(raised.exception))


class Parsing(unittest.TestCase):
    def test_tsv_takes_column_two_and_skips_the_header(self):
        import tempfile
        with tempfile.NamedTemporaryFile("w", suffix=".tsv", delete=False) as fh:
            fh.write("# a comment\nid\tutterance\tfamily\nC001\tbuy milk\tshopping\n")
            path = Path(fh.name)
        self.assertEqual(["buy milk"], mutate.read_utterances(path))


if __name__ == "__main__":
    unittest.main(verbosity=2)
