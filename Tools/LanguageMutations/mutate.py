"""Meaning-preserving mutations of captured speech.

The point of this tool is not to produce a large number. It is to produce
*disagreements*, which need no ground truth to be interesting.

A mutation here is a rewrite that a careful human reader would say does not
change what the speaker wants. If Speak It answers the base utterance one way
and its mutation another, exactly one of those answers is wrong, and we learn
that without anyone having written down which. That is what makes volume useful
here where a pass count would not be: two million variations that all pass say
only that the engine is *consistent*, and consistency is not correctness. A
capture the engine gets wrong identically under every mutation scores clean.
Nothing this tool reports may be quoted as accuracy.

Invariants come in two strengths, because not every family promises the same
thing:

  strict     the structured result must be identical — same destination, same
             rows, same titles, same dates
  structure  the destination and the row count must be identical; the titles
             may differ because the mutation deliberately changed a word

Families are listed in FAMILIES with the strength they claim.
"""

from __future__ import annotations

import argparse
import random
import re
import sys
from dataclasses import dataclass
from pathlib import Path

# Held-out language is sealed. Mutating it would put near-duplicates of
# held-out sentences into a development-visible file, which destroys the set
# as a measure of generalisation just as surely as reading its failures does.
SEALED = ("heldout",)


@dataclass(frozen=True)
class Mutation:
    base: str
    mutated: str
    family: str
    strength: str


FILLERS = ["um", "uh", "like", "you know", "I mean", "er"]
PREAMBLES = [
    "okay so", "alright so", "right", "okay", "so basically", "let me think",
]
SIGN_OFFS = ["bye", "thanks", "that's it", "okay bye", "anyway", "cheers"]
# Unknown-to-the-vocabulary names: the point is words no lexicon holds, which
# is where the proper-noun family actually fails.
STORE_NAMES = [
    "Lucky Star", "Brandy Melville", "Mooji", "Long Fong Mall", "Zehrs",
    "Kinokuniya", "Uniqlo", "Daiso", "Nordstrom Rack", "Provigo",
]
PERSON_NAMES = [
    "Dave", "Priya", "Tomasz", "Ngozi", "Sunil", "Marguerite", "Bao", "Ines",
]
CONJUNCTIONS = ["and then", "then", "after that", "and after that", "and"]


def _insert_filler(text: str, rng: random.Random) -> str:
    """Filler lands between words, which is where people put it."""
    words = text.split()
    if len(words) < 3:
        return text
    at = rng.randrange(1, len(words))
    words.insert(at, rng.choice(FILLERS))
    return " ".join(words)


def _repeat_word(text: str, rng: random.Random) -> str:
    """A stutter or a restarted phrase: "I need to I need to call the vet"."""
    words = text.split()
    if len(words) < 4:
        return text
    at = rng.randrange(0, len(words) - 2)
    span = words[at:at + rng.randint(1, 3)]
    return " ".join(words[:at] + span + words[at:])


def _drop_punctuation(text: str, _rng: random.Random) -> str:
    """Recognisers punctuate inconsistently; the meaning does not move."""
    return re.sub(r"[,;:]", "", text)


def _lowercase(text: str, _rng: random.Random) -> str:
    return text.lower()


def _add_preamble(text: str, rng: random.Random) -> str:
    return f"{rng.choice(PREAMBLES)} {text}"


def _add_sign_off(text: str, rng: random.Random) -> str:
    return f"{text.rstrip('.')} {rng.choice(SIGN_OFFS)}"


def _contract(text: str, _rng: random.Random) -> str:
    """Casual spoken forms of the same obligation."""
    pairs = [
        (r"\bwant to\b", "wanna"),
        (r"\bgoing to\b", "gonna"),
        (r"\bgot to\b", "gotta"),
        (r"\bhave to\b", "hafta"),
        (r"\bneed to\b", "needa"),
        (r"\bkind of\b", "kinda"),
    ]
    for pattern, replacement in pairs:
        if re.search(pattern, text, flags=re.I):
            return re.sub(pattern, replacement, text, count=1, flags=re.I)
    return text


def _swap_conjunction(text: str, rng: random.Random) -> str:
    for pattern in (r"\band then\b", r"\bafter that\b", r"\bthen\b"):
        if re.search(pattern, text, flags=re.I):
            return re.sub(pattern, rng.choice(CONJUNCTIONS), text, count=1, flags=re.I)
    return text


def _restart(text: str, rng: random.Random) -> str:
    """An abandoned opening followed by the real one.

    Modelled on Disfl-QA's human-written restarts ("Norse found no wait
    Normandy"): the speaker begins, breaks off before naming anything, and
    starts again. The second half is the original sentence untouched, so the
    meaning is exactly the original's.
    """
    words = text.split()
    if len(words) < 4:
        return text
    prefix = " ".join(words[: rng.randint(2, 3)])
    marker = rng.choice(["or actually", "no wait", "sorry", "I mean", "actually"])
    return f"{prefix} {marker} {text}"


def _swap_proper_noun(text: str, rng: random.Random) -> str:
    """Replace a name with another unknown name **of the same kind**.

    Structure-preserving rather than strict: the title should change, the
    destination and the number of rows should not.

    Staying inside one pool is what makes that promise true. Swapping a shop
    for a person changes what the sentence is about — "buy socks at Mooji"
    and "buy socks at Bao" are not the same errand — so a disagreement would
    say nothing about proper-noun handling. Shop for shop and person for
    person keeps the only difference the one being tested: whether the
    vocabulary happens to know this particular word.
    """
    for pool in (STORE_NAMES, PERSON_NAMES):
        for name in pool:
            if name in text:
                alternatives = [n for n in pool if n != name]
                return text.replace(name, rng.choice(alternatives), 1)
    return text


FAMILIES = {
    "filler": (_insert_filler, "strict"),
    "repetition": (_repeat_word, "strict"),
    "unpunctuated": (_drop_punctuation, "strict"),
    "lowercased": (_lowercase, "strict"),
    "preamble": (_add_preamble, "strict"),
    "sign-off": (_add_sign_off, "strict"),
    "contraction": (_contract, "strict"),
    "conjunction": (_swap_conjunction, "strict"),
    "restart": (_restart, "strict"),
    "proper-noun": (_swap_proper_noun, "structure"),
}


def mutations_for(text: str, rng: random.Random, families=None) -> list[Mutation]:
    """Every mutation of one utterance that actually changed it.

    A family that cannot apply — no conjunction to swap, no name to replace —
    returns the input unchanged, and an unchanged mutation is dropped rather
    than reported as a trivially passing case.
    """
    chosen = families or list(FAMILIES)
    out = []
    for family in chosen:
        mutate, strength = FAMILIES[family]
        mutated = mutate(text, rng)
        if mutated.strip() and mutated.strip() != text.strip():
            out.append(Mutation(text, mutated, family, strength))
    return out


def read_utterances(path: Path) -> list[str]:
    """Bare lines, or column two of a TSV, skipping comments and headers."""
    if any(part in SEALED for part in path.parts):
        raise SystemExit(
            f"refusing to read {path}: held-out language is sealed.\n"
            "Mutating it would put near-duplicates of held-out sentences into a\n"
            "development-visible file. Mutate development or public-derived sets."
        )
    lines = []
    for raw in path.read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if "\t" in line:
            parts = line.split("\t")
            if parts[0] == "id":
                continue
            line = parts[1] if len(parts) > 1 else parts[0]
        lines.append(line)
    return lines


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path, help="utterances, one per line or TSV column two")
    parser.add_argument("--seed", type=int, default=20260911,
                        help="fixed so a run is reproducible and a finding can be re-shown")
    parser.add_argument("--families", help="comma-separated subset of the families")
    parser.add_argument("--per-utterance", type=int, default=0,
                        help="cap mutations per utterance (0 = every family that applies)")
    args = parser.parse_args()

    families = args.families.split(",") if args.families else None
    if families:
        unknown = [f for f in families if f not in FAMILIES]
        if unknown:
            parser.error(f"unknown families: {', '.join(unknown)}")

    rng = random.Random(args.seed)
    print("base\tmutated\tfamily\tstrength")
    for utterance in read_utterances(args.input):
        produced = mutations_for(utterance, rng, families)
        if args.per_utterance:
            produced = produced[: args.per_utterance]
        for m in produced:
            print(f"{m.base}\t{m.mutated}\t{m.family}\t{m.strength}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
