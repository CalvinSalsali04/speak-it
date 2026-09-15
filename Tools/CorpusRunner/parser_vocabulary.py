"""The obligation vocabularies the parser holds, read out of the source.

Five lists in four files say "this is an obligation", and each gates a
different thing: whether the sentence is cut here, whether it goes to Today or
to Memory, what the row title reads, whether a severed piece is glued back on,
and whether the obligation is somebody else's. They are five lists because they
were written at five times, and `Docs/KNOWN_ISSUES.md` records that they still
disagree.

This module does not unify them -- three of the five gate `count` or `route`,
and converging them changes behaviour that has to be measured on captures
authored for it. What it does is make the disagreement *readable*, so a check
can be written against it. See `test_parser_vocabulary.py` for what is checked.

**Every reader here refuses rather than returns empty.** A source file that has
been reformatted, or a constant that has been renamed, is indistinguishable
from a vocabulary that has become empty -- and an empty vocabulary passes every
subset check ever written. `Refused` is raised instead.
"""
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parents[2]
REPOS = ROOT / "SpeakIt" / "Repositories"


class Refused(Exception):
    """A list could not be read. Never confused with a list that is empty."""


def _source(name):
    path = REPOS / name
    if not path.is_file():
        raise Refused(f"{path} is not on disk; the parser layout has moved")
    return path.read_text(encoding="utf-8")


def _one(pattern, text, what, flags=re.S):
    found = re.findall(pattern, text, flags)
    if len(found) != 1:
        raise Refused(
            f"{what}: expected exactly one match, found {len(found)}. "
            "The constant has been renamed, reformatted or duplicated; fix the "
            "reader rather than letting it report an empty vocabulary."
        )
    return found[0]


def _normalise(form):
    """One spelling per form, so `need\\s+to` and `need to` are one thing."""
    form = form.replace(r"\s+", " ").replace("\\", "")
    form = form.replace("['’]", "'").replace("(?:i|we)", "i/we")
    return form.strip()


def _alternatives(blob):
    """Split a regex alternation at its top level."""
    out, depth, cur = [], 0, ""
    for ch in blob:
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
        if ch == "|" and depth == 0:
            out.append(cur)
            cur = ""
        else:
            cur += ch
    out.append(cur)
    forms = [_normalise(o) for o in out]
    return {f for f in forms if f}


def clause_internal_lead():
    """`SpeechRepair.ClauseJuxtaposition` -- words that cannot end a clause.

    Far wider than obligation: conjunctions, copulas, pronouns and motion verbs
    are here too. It matters to obligation because a single-token obligation
    form missing from it gets cut off from what it governs, which is the defect
    that produced a Memory row titled "I hafta".
    """
    body = _one(
        r"private static let clauseInternalLead: Set<String> = \[(.*?)\n    \]",
        _source("SpeechRepair.swift"),
        "clauseInternalLead",
    )
    return {s for s in re.findall(r'"((?:[^"\\]|\\.)*)"', re.sub(r"//[^\n]*", "", body))}


def obligation_lead():
    """`ActionabilityReader.obligationLead` -- Today versus Memory.

    Read unanchored, which is why bare `better` is not in it: "the weather is
    better tomorrow" would become an errand.
    """
    blob = _one(
        r'static let obligationLead = #"(.*?)"#',
        _source("Actionability.swift"),
        "obligationLead",
    )
    for prefix in (r"^\(\?:i\\s\+\)\?", r"^\(\?:really\\s\+\)\?"):
        blob = re.sub(prefix, "", blob)
    if not (blob.startswith("(?:") and blob.endswith(")")):
        raise Refused(f"obligationLead is no longer one alternation: {blob[:60]}")
    return _alternatives(blob[3:-1])


def third_person_obligation():
    """`ActionabilityReader.thirdPersonObligation` -- whose obligation it is.

    A closed class, and deliberately smaller than `obligationLead`: only the
    forms English can predicate of somebody who is not the speaker.
    """
    blob = _one(
        r"private static let thirdPersonObligation =\n(.*?)\n\n",
        _source("Actionability.swift"),
        "thirdPersonObligation",
    )
    pieces = re.findall(r'#"([^"]*)"#', blob)
    joined = "|".join(p.strip("|") for p in pieces)
    if not joined.startswith("(?:") or not joined.endswith(")"):
        raise Refused(f"thirdPersonObligation is no longer one alternation: {joined[:60]}")
    return _alternatives(joined[3:-1])


def obligation_frame_link():
    """`ThoughtOrganizer.ObligationFrame.link` -- what the row title reads.

    The smallest of the five on purpose. Its docstring calls it safety by
    omission: a form absent here can never sit inside the span the type
    deletes, so "I had to cancel the appointment" keeps its words.
    """
    blob = _one(
        r'private static let link = #"\(\?:"#\n(.*?)\+ #"\)"#',
        _source("ThoughtOrganizer.swift"),
        "ObligationFrame.link",
    )
    pieces = re.findall(r'#"([^"]*)"#', blob)
    return _alternatives("|".join(p.strip("|") for p in pieces))


def dangling_auxiliary():
    """`ThoughtExtractor.isFragment` -- whether a severed piece is glued back.

    Holds `will` and `can`, which no other list calls obligations, because this
    one is about a sentence that stopped rather than about what it was going to
    say.
    """
    blob = _one(
        r'of: #"\^\(\?:i\\s\+\)\?\(\?:(.*?)\)\$"#',
        _source("ThoughtExtractor.swift"),
        "isFragment's dangling auxiliary",
    )
    return _alternatives(blob)


#: Every list, by the thing it gates. The key is what a reader has to know.
LISTS = {
    "split": clause_internal_lead,
    "route": obligation_lead,
    "whose": third_person_obligation,
    "title": obligation_frame_link,
    "glue": dangling_auxiliary,
}

#: The four that state an obligation. `split` is excluded: it is a "cannot end
#: a clause" set that happens to contain obligation forms, so counting it as a
#: claimant would make every conjunction an obligation.
CLAIMANTS = ("route", "whose", "title", "glue")


def read_all():
    """Every list, or a refusal naming the one that could not be read."""
    return {name: reader() for name, reader in LISTS.items()}


def union(lists=None):
    """Every form any claimant calls an obligation."""
    lists = lists or read_all()
    out = set()
    for name in CLAIMANTS:
        out |= lists[name]
    return out


def single_token(forms):
    """Forms of one word, which are the ones clause splitting can sever.

    A multi-word frame ends in `to`, and `to` has been the first entry of
    `clauseInternalLead` since it was written, so those are protected without
    anyone deciding to protect them.
    """
    return {f for f in forms if " " not in f and "/" not in f}
