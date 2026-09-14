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

# Text is a NEAR duplicate of tuned material — Jaccard at or above 0.70 over
# content words — without being identical. Weaker than an exact match and still
# not "unseen": a gating-corpus sentence that shares seven content words in ten
# with a held-out capture was fitted against essentially this capture.
#
# It is the weakest category here and the threshold is a choice somebody made,
# not a fact. `leak-check.py` pins a four-token floor with a test for the
# reason that matters: Jaccard over content words clears 0.70 easily on a very
# short sentence, so without the floor this category would fill up with pairs
# that merely share a verb and a noun.
NEAR_TUNED_MATERIAL = {
    "C005": "near the gating corpus",
    "C236": "near SwiftDataThoughtRepositoryTests",
    "C243": "near the gating corpus and routed.tsv",
    "C331": "near the gating corpus and DurabilityTests",
    "C353": "near the gating corpus",
    "C355": "near the gating corpus",
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
    ("near tuned material (Jaccard >= 0.70)", NEAR_TUNED_MATERIAL),
    ("exposed without inspection", EXPOSED_WITHOUT_INSPECTION),
)

# Calvin's "five compromised captures": the union of the two categories that
# describe the state of the repository. Kept as its own name because it is the
# number quoted in the baseline and in his instruction, and a reader has to be
# able to get from that five to the exclusion set used here.
COMPROMISED = set(IN_TUNED_MATERIAL) | set(VERBATIM_IN_DOCUMENT)

# What the clean sealed score excludes: every capture documented as not unseen,
# by any route. Wider than COMPROMISED, and deliberately so — the property the
# clean number claims is **unseen**, and each category below defeats it.
#
# The five in COMPROMISED are the ones whose text is demonstrably present in
# tuned material or in a document. The near-duplicates and the exposure are
# weaker cases and are still excluded, because the conservative denominator is
# the honest one for a generalisation claim: if the exclusion is wrong, the
# clean score is computed over slightly fewer captures than it could have been,
# which costs precision. If it is too narrow, the number overstates what the
# parser has shown, which is the failure this whole apparatus exists to stop.
#
# Anyone wanting a less conservative figure has the categories: the scorer
# prints each one's count on every run, so the arithmetic is available without
# a second metric being published.
EXCLUDED = (COMPROMISED
            | set(NEAR_TUNED_MATERIAL)
            | set(EXPOSED_WITHOUT_INSPECTION))


def why(cid):
    """Every category a capture falls into, as (category, provenance) pairs.

    A capture can be compromised two ways at once — C342 is — which is exactly
    the shape that made the original count wrong: the two limbs were reported
    as a column rather than a union, and the capture in both made the total
    look consistent.
    """
    return [(name, table[cid]) for name, table in CATEGORIES if cid in table]
