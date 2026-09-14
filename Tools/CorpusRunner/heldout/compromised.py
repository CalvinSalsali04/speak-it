"""Held-out captures that are known not to be unseen, and why each one is not.

WHY THIS FILE EXISTS

`heldout.tsv` is scored separately from the corpus the rules are tuned against
so that its rate can be read as generalisation. That reading is only as good as
the claim that the parser has not met these captures before, and on 2026-09-11
that claim turned out to be false for several of them. The response is not to
delete the rows — deleting a sentence does not un-see it, and it would break
comparability with every figure already published — but to name them, keep
scoring them, and publish two numbers:

  legacy       every labelled capture, the historical metric, unchanged
  clean sealed the same measures over the captures still plausibly unseen

Neither replaces the other. The legacy number is what older sections of
`Docs/LANGUAGE_BASELINE.md` mean; the clean number is what a claim about
generalisation to unseen speech is entitled to use.

IDS ONLY

Nothing here reads, stores or prints capture text. An id is enough to exclude a
row, to subtract it from a denominator, and to recognise the same row twice.

An id is safe to store and **unsafe to grep**: `heldout.tsv` is the one place an
id sits beside its text, so a plain recursive search from the repository root
turns this registry into a lookup key. That is not hypothetical — it is how
C283 came to be exposed a second time, while its first exposure was being
written up. Check an id against this module, never with `grep -r`.
"""

# Text appears verbatim in material the rules are tuned against: the gating
# corpus fixtures and the development sets. This is the strongest form of
# compromise, because the rules were fitted while the capture was visible, so
# the row measures memorisation rather than generalisation.
IN_TUNED_MATERIAL = {
    "C049": "SemanticCorpusDataQ.swift; devsets/routed.tsv RC02; devsets/coordination.tsv RS04",
    "C100": "four SemanticCorpusData*.swift files and six hand-written test files",
    "C342": "SpeakItTests/LocationReminderTests.swift",
}

# Text appears verbatim in tracked repository prose. Weaker than the above —
# nothing was fitted to it — but every rule in this repository is written by
# someone who reads these documents, so the capture is not unseen either.
VERBATIM_IN_DOCUMENT = {
    "C342": "five App Store and hand-QA documents",
    "C236": "Docs/PipelineSweep/routing.md",
    "C358": "Docs/AMBIGUITY_TAXONOMY.md",
}

# Text was printed into a working session's context. Never in tuning material,
# never compared against, pass/fail never looked up. This category is an
# *event* rather than a state of the repository, which is why it cannot be
# rediscovered by scanning and has to be recorded when it happens.
#
# C283: exposed twice on 2026-09-11 — once by a corpus-wide `*.tsv` scan, once
# by a `grep` for its own id while the first exposure was being documented.
# Distinct captures exposed is one; exposure events are two.
EXPOSED_WITHOUT_INSPECTION = {
    "C283": "printed into a session context twice on 2026-09-11; never inspected",
}

CATEGORIES = (
    ("in tuned material", IN_TUNED_MATERIAL),
    ("verbatim in a tracked document", VERBATIM_IN_DOCUMENT),
    ("exposed without inspection", EXPOSED_WITHOUT_INSPECTION),
)

# Calvin's "five compromised captures": the union of the two categories that
# describe the state of the repository. Kept as its own name because it is the
# number quoted in the baseline and in his instruction, and a reader has to be
# able to get from that five to the exclusion set used here.
COMPROMISED = set(IN_TUNED_MATERIAL) | set(VERBATIM_IN_DOCUMENT)

# What the clean sealed score excludes. Wider than COMPROMISED by one, and the
# judgement is deliberate: the property the clean number claims is "unseen",
# and a capture that a parser-writing session has read is not unseen whatever
# route it took. Excluding it costs one row and protects the claim.
EXCLUDED = COMPROMISED | set(EXPOSED_WITHOUT_INSPECTION)


def why(cid):
    """Every category a capture falls into, as (category, provenance) pairs.

    A capture can be compromised two ways at once — C342 is — which is exactly
    the shape that made the original count wrong: the two limbs were reported
    as a column rather than a union, and the capture in both made the total
    look consistent.
    """
    return [(name, table[cid]) for name, table in CATEGORIES if cid in table]
