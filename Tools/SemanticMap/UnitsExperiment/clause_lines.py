#!/usr/bin/env python3
"""Candidate 2's input: deterministic clause lines over the atoms.

FROZEN BEFORE THE GOLD WAS WRITTEN. Its sha256 is recorded in the experiment
manifest; changing a rule after seeing the gold or any model output would be
tuning the representation to the answer, so any change restarts the
experiment from scratch.

A clause line is a low-level structural piece, NOT a thought and NOT a rules
row. It deliberately over-segments: the model can only join lines
(`continues`), never cut inside one, so a missing boundary is a hard ceiling
and a surplus boundary costs nothing but one more label. No rules-parser output
is used here, so the parser's current thought-boundary decisions cannot leak in.

A new line starts BEFORE atom i (i > 0) when any of:
  1. atom i-1 ends in sentence or clause punctuation  . , ; : ! ? or a dash
  2. atom i is a coordinator, subordinator or discourse marker (MARKERS)
  3. atom i is a subject pronoun (SUBJECTS) and atom i-1 is not a word that
     takes it as an object or complement opener (NO_SUBJECT_CUT_AFTER)
  4. atom i starts an action verb from production's ActionabilityReader list
     (copied verbatim, first word of each alternative) and atom i-1 is not a
     word that makes it a complement or infinitive (NO_VERB_CUT_AFTER)
Atoms are whitespace runs of the original transcript, numbered from 0.
"""
import re

MARKERS = {
    "and", "but", "or", "so", "then", "because", "cause", "cos", "while", "although",
    "though", "if", "unless", "until", "when", "whenever", "before", "after", "since",
    "whereas", "plus", "also", "actually", "anyway", "anyways", "oh", "okay", "ok",
    "right", "um", "uh", "yeah", "well", "no", "which", "otherwise", "instead",
}
SUBJECTS = {"i", "i'm", "i'll", "i've", "i'd", "we", "we're", "we'll", "he", "she", "they",
            "it's", "there's", "that's", "you"}
NO_SUBJECT_CUT_AFTER = {
    "to", "for", "with", "at", "of", "from", "about", "on", "in", "by", "than", "like",
    "let", "help", "make", "give", "tell", "ask", "remind", "text", "call", "email", "send",
}
# ActionabilityReader.actionVerb (SpeakIt/Repositories/Actionability.swift), first word of each alternative.
ACTION_VERBS = {
    "buy", "get", "grab", "pick", "drop", "finish", "complete", "submit", "hand", "send", "call",
    "phone", "text", "email", "message", "book", "schedule", "reserve", "renew", "do", "return",
    "pay", "order", "take", "bring", "pack", "check", "make", "add", "water", "wash", "clean",
    "visit", "meet", "ask", "tell", "wish", "say", "print", "fix", "lock", "follow", "reply",
    "respond", "confirm", "cancel", "sign", "file", "mail", "deliver", "charge", "refill", "top",
}
NO_VERB_CUT_AFTER = {
    "to", "i", "we", "you", "he", "she", "they", "i'll", "we'll", "will", "would", "should",
    "could", "can", "can't", "must", "might", "may", "need", "needs", "want", "wants", "gotta",
    "please", "don't", "didn't", "not", "never", "just", "also", "let's", "the", "a", "an",
    "and", "or", "but", "so", "then", "could", "might", "and", "go", "to", "me", "you'll",
    "i'd", "we'd", "i've", "gonna", "wanna", "have", "has", "had", "did", "does", "do",
}
PUNCT_END = re.compile(r"[.,;:!?—–-]$")


def norm(atom):
    return re.sub(r"^[^\w']+|[^\w']+$", "", atom.lower()).replace("’", "'")


def boundaries(atoms):
    """Atom indexes i (> 0) before which a new line starts, sorted."""
    cuts = []
    for i in range(1, len(atoms)):
        prev, word = norm(atoms[i - 1]), norm(atoms[i])
        if (PUNCT_END.search(atoms[i - 1])
                or word in MARKERS
                or (word in SUBJECTS and prev not in NO_SUBJECT_CUT_AFTER)
                or (word in ACTION_VERBS and prev not in NO_VERB_CUT_AFTER)):
            cuts.append(i)
    return cuts


def lines(atoms):
    """Contiguous inclusive [first, last] atom ranges covering every atom once."""
    starts = [0] + boundaries(atoms)
    return [[s, (starts[k + 1] - 1) if k + 1 < len(starts) else len(atoms) - 1]
            for k, s in enumerate(starts)] if atoms else []


if __name__ == "__main__":
    import sys
    for text in sys.stdin:
        atoms = text.split()
        print(" | ".join(" ".join(atoms[a:b + 1]) for a, b in lines(atoms)))
