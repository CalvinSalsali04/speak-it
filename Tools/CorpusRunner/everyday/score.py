"""Scores the everyday-speech held-out set, per domain and per family.

Six measures. They are deliberately not averaged into one number, because a
single figure hides exactly the failures that matter most: a set can route 95%
of captures correctly and still invert every negation it sees.

  routing     did the capture land on Today or in Memory as a careful reader
              said it should
  count       did it produce the right number of user-visible rows
  split       it produced MORE rows than the speaker meant   (over-segmentation)
  merge       it produced FEWER rows than the speaker meant  (under-segmentation)
  loss        something the speaker said is gone from everything they can see
  invention   the structured reading shows a value the speaker did not mean —
              an unresolved correction, an inverted negation, a wrong date

and one harm measure, which is reported apart from the rest:

  unsafe      the capture's meaning could not be pinned down by a careful human
              reader, and the app scheduled, dated or modified something anyway

`loss` and `invention` are checked against different surfaces on purpose.
Loss looks at everything the user can see, the verbatim quote included: if the
words survive anywhere, nothing was lost. Invention looks only at the
*interpretation* — titles, dates, reminders, recurrence, person, list — because
the quote is supposed to hold the speaker's own words, superseded ones and all.
Rejecting a word for appearing in the quote would punish the pipeline for
keeping its promise.

Expected item types are reported but never gated. Today-versus-Memory is the
product contract's hard line; whether a note is an `idea` or a `note` is a
judgement call the label cannot settle.
"""
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path


def norm(text):
    """Fold to comparable text: lowercase, punctuation to single spaces."""
    return re.sub(r"[^a-z0-9]+", " ", text.lower()).strip()


def carries(span, surface):
    """Does `surface` contain `span`, starting at a token boundary?

    A plain substring test folds `6:40` to `6 40`, which sits inside `16 40` —
    so a pipeline that read the time correctly gets reported for inventing the
    one it discarded. Anchoring the left edge removes that whole class. The
    right edge is deliberately left open, because a label says `500 gram` and a
    rendering may say `500 grams`; a suffix match is the tolerance the labels
    were written with and it cannot manufacture a failure.
    """
    return re.search(r"(?<![a-z0-9])" + re.escape(norm(span)), surface) is not None


def parse_labels(path):
    rows = []
    for line in open(path):
        if line.startswith("#") or not line.strip():
            continue
        parts = line.rstrip("\n").split("\t")
        if len(parts) < 8 or parts[0] == "id":
            continue
        cid, domain, utterance, expect, keep, reject, families, note = parts[:8]
        rows.append({
            "id": cid,
            "domain": domain,
            "utterance": utterance,
            "expect": [e for e in expect.split("|") if e],
            "keep": [k for k in keep.split("|") if k and k != "-"],
            "reject": [r for r in reject.split("|") if r and r != "-"],
            "families": [f for f in families.split("|") if f],
            "note": note,
        })
    return rows


def parse_probe(path):
    r"""Reads `probe` output into one record per utterance.

    Field patterns use `[ \t]` rather than `\s` on purpose: `\s` matches a
    newline, so a field printed with an empty value let the capture run on into
    the following line and read the next field's text as this one's value.
    """
    blocks = re.split(r'\n(?=── ")', Path(path).read_text())
    seen = {}
    for block in blocks:
        header = re.match(r'── "(.*?)"', block)
        if not header:
            continue
        rows = []
        for chunk in re.split(r"\n(?=     row title:)", block)[1:]:
            rows.append({
                "title": (re.search(r"row title:[ \t]*(.*)", chunk) or [None, ""])[1]
                if re.search(r"row title:[ \t]*(.*)", chunk) else "",
                "route": (re.search(r"route:[ \t]*(\S+)", chunk).group(1)
                          if re.search(r"route:[ \t]*(\S+)", chunk) else ""),
                "type": (re.search(r"type:[ \t]*(\S+)", chunk).group(1)
                         if re.search(r"type:[ \t]*(\S+)", chunk) else ""),
                "due": (re.search(r"due:[ \t]*(.*)", chunk).group(1).strip()
                        if re.search(r"due:[ \t]*(.*)", chunk) else "nil"),
                "remind": (re.search(r"remind:[ \t]*(.*?)[ \t]{2,}delivery:", chunk).group(1).strip()
                           if re.search(r"remind:[ \t]*(.*?)[ \t]{2,}delivery:", chunk) else "nil"),
                "person": (re.search(r"person:[ \t]*(.*)", chunk).group(1).strip()
                           if re.search(r"person:[ \t]*(.*)", chunk) else ""),
                "recurs": (re.search(r"recurs:[ \t]*(.*)", chunk).group(1).strip()
                           if re.search(r"recurs:[ \t]*(.*)", chunk) else ""),
                "location": (re.search(r"location:[ \t]*(.*)", chunk).group(1).strip()
                             if re.search(r"location:[ \t]*(.*)", chunk) else ""),
                "list": (re.search(r"list:[ \t]*(.*)", chunk).group(1).strip()
                         if re.search(r"list:[ \t]*(.*)", chunk) else ""),
                "quote": (re.search(r"quote:[ \t]*(.*)", chunk).group(1).strip()
                          if re.search(r"quote:[ \t]*(.*)", chunk) else ""),
            })
        for row in rows:
            # The row title doubles as the quote when the probe suppresses the
            # duplicate `quote:` line, so a missing quote is the title.
            if not row["quote"]:
                row["quote"] = row["title"]
        seen[header.group(1)] = {
            "rows": rows,
            "operations": re.findall(r"operation:[ \t]*(\S+)", block),
            # The target is the part of an operation a person can see: a
            # withdrawal that named the wrong thought, or none at all, is a
            # real defect, and a cancellation whose target survived is not
            # content loss. Scoring the verb alone missed both.
            "targets": [t.strip() for t in re.findall(r"operation:.*?target=(\S+)", block)],
            "block": block.strip(),
        }
    return seen


# The surface the user reads. `interpretation` is what the pipeline decided;
# `visible` adds the verbatim quote, which is what the speaker actually said.
def interpretation(got):
    parts = [t for t in got["targets"] if t != "nil"]
    for row in got["rows"]:
        parts += [row["title"], row["person"], row["recurs"], row["list"],
                  row["location"]]
        parts += [row["due"] if row["due"] != "nil" else "",
                  row["remind"] if row["remind"] != "nil" else ""]
    return norm(" ".join(p for p in parts if p))


def visible(got):
    return norm(interpretation(got) + " " + " ".join(r["quote"] for r in got["rows"]))


# --- title hygiene -------------------------------------------------------
#
# This does NOT score whether a title reads well. That is a judgement no label
# can settle, and pretending to measure it would produce a number nobody should
# trust. What it scores is narrower and checkable: whether the title still
# carries something the pipeline is supposed to have removed.
#
# Every rule below fires only on material that is never content in title
# position. Ambiguous fillers — "like", "basically", "honestly" — are
# deliberately absent, because they are ordinary words often enough that
# flagging them would manufacture failures. The result is a LOWER BOUND on
# title defects: everything it reports is real, and it will miss some.

HESITATION = {"um", "uh", "erm", "er", "uhh", "umm"}
FAREWELL = {"bye", "goodbye", "byebye"}
# A title may not open on a word that only ever joins one clause to another.
DANGLING_OPENER = {"and", "then", "but", "also", "or", "because", "which",
                   "that", "so"}
PREAMBLE = ("the thing is", "what happened was", "number one", "number two",
            "number three", "basically what", "so basically")


def title_defects(title, utterance):
    """Names every removable thing the title still carries."""
    words = norm(title).split()
    if not words:
        return ["empty title"]

    found = []
    if set(words) & HESITATION:
        found.append("hesitation kept")
    if words[-1] in FAREWELL:
        found.append("farewell kept")
    if words[0] in DANGLING_OPENER:
        found.append(f"opens on '{words[0]}'")
    reading = norm(title)
    for phrase in PREAMBLE:
        if reading.startswith(phrase) or f" {phrase}" in reading:
            found.append(f"preamble '{phrase}' kept")
            break
    # A doubled phrase is a stutter the repair chain should have rejoined.
    for size in (4, 3, 2):
        for i in range(len(words) - 2 * size + 1):
            if words[i:i + size] == words[i + size:i + 2 * size]:
                found.append("stutter kept: " + " ".join(words[i:i + size]))
                break
        else:
            continue
        break
    # A long capture whose title is the whole utterance was never summarised.
    spoken = norm(utterance)
    if len(spoken.split()) > 12 and reading == spoken:
        found.append("title is the whole capture")
    return found


def main():
    labels_path, probe_path = sys.argv[1], sys.argv[2]
    show_failures = "--failures" in sys.argv or "--verbose" in sys.argv

    rows = parse_labels(labels_path)
    seen = parse_probe(probe_path)

    # tallies[scope][measure] where scope is "ALL", a domain, or a family.
    tallies = defaultdict(Counter)
    failures = []
    type_agreement = Counter()

    for case in rows:
        got = seen.get(case["utterance"])
        scopes = ["ALL", case["domain"]] + ["fam:" + f for f in case["families"]]

        if got is None:
            for scope in scopes:
                tallies[scope]["unseen"] += 1
            continue

        ambiguous = case["expect"] == ["Ambiguous"]
        wants_op = any(e.startswith("Op:") for e in case["expect"])
        expected_rows = 0 if (ambiguous or wants_op) else len(case["expect"])
        produced = len(got["rows"])
        had_op = bool(got["operations"])

        def hit(measure, ok, detail=""):
            for scope in scopes:
                tallies[scope][measure + ("_ok" if ok else "_miss")] += 1
            if not ok:
                failures.append((measure, case, got, detail))

        for scope in scopes:
            tallies[scope]["scored"] += 1

        # Preservation is scored on every capture, ambiguous ones included: a
        # capture that silently produced nothing is the purest form of loss.
        if produced == 0 and not had_op:
            hit("empty", False, "no rows and no operation")
        else:
            hit("empty", True)

        if ambiguous:
            for scope in scopes:
                tallies[scope]["ambiguous"] += 1
            acted = had_op or any(r["due"] != "nil" or r["remind"] != "nil"
                                  for r in got["rows"])
            if acted:
                for scope in scopes:
                    tallies[scope]["unsafe"] += 1
                dues = [r["due"] for r in got["rows"] if r["due"] != "nil"]
                reminds = [r["remind"] for r in got["rows"] if r["remind"] != "nil"]
                failures.append(("unsafe", case, got,
                                 f"op={got['operations']} due={dues} remind={reminds}"))
        elif wants_op:
            hit("routing", had_op, f"operations={got['operations'] or 'none'}")
        else:
            want = Counter(e.split(":")[0] for e in case["expect"])
            have = Counter(r["route"] for r in got["rows"])
            hit("routing", want == have,
                f"want {dict(want)} · got {dict(have) or 'nothing'}")

            hit("count", produced == expected_rows,
                f"want {expected_rows} rows · got {produced}")
            if produced > expected_rows:
                for scope in scopes:
                    tallies[scope]["split"] += 1
            elif produced < expected_rows:
                for scope in scopes:
                    tallies[scope]["merge"] += 1

            # Reported two ways on purpose. A capture the pipeline segmented
            # wrongly cannot match this comparison whatever types it chose --
            # the Counters differ by a whole row -- so the plain figure carries
            # every `count` failure inside it and reads as a type problem. The
            # conditioned figure is the one that says anything about types.
            want_types = Counter(e.split(":")[1] for e in case["expect"] if ":" in e)
            have_types = Counter(r["type"] for r in got["rows"])
            agreed = want_types == have_types
            type_agreement["ok" if agreed else "differs"] += 1
            if produced == expected_rows:
                type_agreement["segmented_ok" if agreed else "segmented_differs"] += 1

        if case["keep"]:
            surface = visible(got)
            lost = [k for k in case["keep"] if not carries(k, surface)]
            hit("loss", not lost, "gone: " + ", ".join(lost) if lost else "")

        defects = []
        for row in got["rows"]:
            defects += [(row["title"], d)
                        for d in title_defects(row["title"], case["utterance"])]
        hit("title", not defects,
            "; ".join(f"{d} — \"{title}\"" for title, d in defects))
        for _, defect in defects:
            tallies["ALL"]["defect:" + defect.split(":")[0].split(" — ")[0]] += 1

        if case["reject"]:
            reading = interpretation(got)
            found = [r for r in case["reject"] if carries(r, reading)]
            hit("invention", not found,
                "reading still shows: " + ", ".join(found) if found else "")

    report(rows, tallies, failures, type_agreement, seen, labels_path)
    if show_failures:
        print_failures(failures)


def rate(counter, measure):
    ok, miss = counter[measure + "_ok"], counter[measure + "_miss"]
    total = ok + miss
    if total == 0:
        return "        —      "
    return f"{ok:>4}/{total:<4} ({100 * ok / total:5.1f}%)"


def set_title(labels_path):
    """The banner a set prints, from its own `# title:` line.

    The scorer is shared: everyday and adversarial hold out different things
    and must not print each other's name in a report someone later quotes.
    """
    for line in open(labels_path):
        if not line.startswith("#"):
            break
        key, sep, value = line.lstrip("#").strip().partition(":")
        if sep and key.strip().lower() == "title":
            return value.strip()
    return "EVERYDAY SPEECH HELD-OUT SET"


def report(rows, tallies, failures, type_agreement, seen, labels_path):
    directory = Path(labels_path).resolve().parent.name
    print()
    print(f"{set_title(labels_path)} — {len(rows)} captures, "
          f"{len(seen)} probe results, directory `{directory}`")
    print("=" * 78)
    print("Human-written held-out data. Not tuned against. Frame of reference")
    print("Monday 2026-08-03 10:00 America/Toronto.")
    print()

    domains = sorted({c["domain"] for c in rows})
    header = f"{'':<18}{'routing':>17}{'count':>17}{'loss':>17}{'invention':>17}"
    print(header)
    print("-" * 78)
    for scope in ["ALL"] + domains:
        counter = tallies[scope]
        name = "ALL DOMAINS" if scope == "ALL" else scope
        print(f"{name:<18}{rate(counter, 'routing'):>17}{rate(counter, 'count'):>17}"
              f"{rate(counter, 'loss'):>17}{rate(counter, 'invention'):>17}")
    print("-" * 78)

    overall = tallies["ALL"]
    print()
    print(f"  over-segmented (split)      {overall['split']}")
    print(f"  under-segmented (merge)     {overall['merge']}")
    print(f"  produced nothing at all     {overall['empty_miss']}")
    print(f"  missing probe results       {overall['unseen']}")
    segmented = type_agreement["segmented_ok"] + type_agreement["segmented_differs"]
    print(f"  item type matched the label {type_agreement['ok']}"
          f"/{type_agreement['ok'] + type_agreement['differs']}  (reported, never gated)")
    print(f"    of those segmented right  {type_agreement['segmented_ok']}"
          f"/{segmented}  ← the one that is about types")
    print()
    print(f"  genuinely ambiguous         {overall['ambiguous']}")
    print(f"  ACTED ON ANYWAY             {overall['unsafe']}"
          f"  ({100 * overall['unsafe'] / max(overall['ambiguous'], 1):.1f}% of them)")
    print()
    print("  The last number is harm rather than accuracy: a confident action on")
    print("  a capture whose meaning a careful human could not pin down. It is the")
    print("  one row that should only ever fall.")
    print("=" * 78)

    print()
    print("TITLE HYGIENE — does the shown title still carry something the")
    print("pipeline should have removed? A lower bound on defects, never a")
    print("judgement about how well a title reads.")
    print("-" * 78)
    print(f"{'':<18}{'clean titles':>20}")
    for scope in ["ALL"] + domains:
        counter = tallies[scope]
        name = "ALL DOMAINS" if scope == "ALL" else scope
        print(f"{name:<18}{rate(counter, 'title'):>20}")
    breakdown = sorted(((k[len('defect:'):], v) for k, v in tallies["ALL"].items()
                        if k.startswith("defect:")), key=lambda kv: -kv[1])
    if breakdown:
        print()
        for defect, count in breakdown:
            print(f"    {count:>4}  {defect}")
    print("-" * 78)

    families = sorted({f for c in rows for f in c["families"]})
    print()
    print("PER FAMILY — a whole-set average hides the family that is broken")
    print("-" * 78)
    print(f"{'family':<18}{'n':>4}{'routing':>17}{'count':>17}{'title':>17}")
    print("-" * 78)
    ranked = sorted(families, key=lambda f: (
        worst(tallies["fam:" + f]), -tallies["fam:" + f]["scored"]))
    for family in ranked:
        counter = tallies["fam:" + family]
        print(f"{family:<18}{counter['scored']:>4}{rate(counter, 'routing'):>17}"
              f"{rate(counter, 'count'):>17}{rate(counter, 'title'):>17}")
    print("-" * 78)
    print("Worst family first. `n` counts captures carrying the tag, so the")
    print("columns overlap: one capture can be filler, negation and multi-thought.")
    print()


def worst(counter):
    """Lowest pass rate across the gated measures, for ranking families."""
    rates = []
    for measure in ("routing", "count", "loss", "invention", "title"):
        ok, miss = counter[measure + "_ok"], counter[measure + "_miss"]
        if ok + miss:
            rates.append(ok / (ok + miss))
    return min(rates) if rates else 1.0


def print_failures(failures):
    print()
    print("#" * 78)
    print("# FAILURES — input, expectation, and what the pipeline actually did.")
    print("#")
    print("# Read these at review time. Do NOT use them to steer a fix: the")
    print("# moment one of these captures is tuned against, this set stops")
    print("# measuring generalisation. Reproduce the failure family in")
    print("# Tools/CorpusRunner/devsets/ and work there instead.")
    print("#" * 78)
    order = {"unsafe": 0, "empty": 1, "invention": 2, "loss": 3,
             "routing": 4, "count": 5, "title": 6}
    for measure, case, got, detail in sorted(failures, key=lambda f: order.get(f[0], 9)):
        print()
        print(f"{measure.upper():<10} {case['id']}  [{case['domain']}]  "
              f"families: {', '.join(case['families'])}")
        print(f"  said:     \"{case['utterance']}\"")
        print(f"  expected: {' | '.join(case['expect'])}   — {case['note']}")
        if detail:
            print(f"  problem:  {detail}")
        print("  pipeline output:")
        for line in got["block"].splitlines()[1:]:
            print("    " + line)


if __name__ == "__main__":
    main()
