"""Proves this scorer's test suite actually protects every measure it reports.

A measure that silently always reports `ok` is worse than a missing measure:
it reads as a perfect score, and a perfect score is exactly what nobody
investigates. Tests that only assert the happy path cannot catch that.

So each measure is broken on purpose, one at a time, and the suite must
notice. This is the argument `Tools/CorpusRunner/mutation-gate.sh` already
makes about the gating corpus — delete a subsystem and prove the corpus
would fail — applied to the instrument instead of to the app.

"Protected" means *some* test in the suite fails when that measure breaks —
not necessarily the one named after it. That is the property worth having: a
broken measure cannot reach a report.

A mutation harness reports "the suite noticed" by running the suite and reading
its exit status, which means nothing unless the suite passes when nothing has
been mutated. The first version of this file did not check that, and it was
wrong: it copied this directory alone, which left 14 tests failing before any
mutation was applied, so every measure came back "protected" whatever the
mutation did. It reported all eleven protected; the truth was nine, with
`count` and `ambiguous` genuinely uncovered. So the control runs first here and
the gate refuses to report at all if it is red.

Neutering the whole suite is NOT that control and does not substitute for it:
no-op tests cannot fail, so that path exits zero and reads as "unprotected" —
it shows the harness responds to the tests being gone, never that it responds
to a measure breaking.

Two kinds of break, because the scorer records results two ways:

  * measures routed through `hit()` are forced to pass unconditionally
  * counters tallied directly are suppressed so they can never report

Run it from the repository root:

    python3 Tools/CorpusRunner/everyday/measure-gate.py
"""
import contextlib
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve().parent

#: Measures recorded through `hit()`. Forced to always pass.
FORCED = ["routing", "count", "loss", "title", "invention", "empty"]

#: Counters tallied straight into `tallies`. Suppressed entirely.
SUPPRESSED = ["unsafe", "split", "merge", "ambiguous", "unseen"]

#: Measures that are neither, listed as (name, pattern, replacement). This file
#: claims to cover every measure the scorer reports, so a reported number that
#: does not fit the two shapes above has to be written out rather than left
#: off -- otherwise the claim is true only of the measures that were easy.
REWRITTEN = [
    ("item type", r"agreed = want_types == have_types", "agreed = True"),
]


ROOT = HERE.parents[2]

#: Sibling directories the suite reaches for: corpora to check the sealed sets
#: against, and the Swift sources the leak check harvests. They are linked
#: rather than copied, so the scratch tree differs from the real one in exactly
#: one file — the mutated scorer.
LINKED = [ROOT / "SpeakItTests",
          ROOT / "Tools/CorpusRunner/devsets",
          ROOT / "Tools/CorpusRunner/heldout",
          ROOT / "Tools/CorpusRunner/adversarial"]


@contextlib.contextmanager
def scratch_tree():
    """A copy of this directory that still sits at the right depth in a repo.

    Copying `everyday/` alone and running the suite there fails 14 tests before
    any mutation is applied: `leak-check.py` resolves the repository root as
    `parents[3]`, and the tests reach sideways for `heldout/` and the rest. A
    harness whose baseline is already red reports every mutation as noticed,
    which is the exact defect this file exists to catch, in this file.
    """
    with tempfile.TemporaryDirectory() as tmp:
        root = pathlib.Path(tmp)
        (root / "Tools/CorpusRunner").mkdir(parents=True)
        shutil.copytree(HERE, root / "Tools/CorpusRunner" / HERE.name)
        for path in LINKED:
            if path.exists():
                link = root / path.relative_to(ROOT)
                link.parent.mkdir(parents=True, exist_ok=True)
                link.symlink_to(path, target_is_directory=True)
        yield root / "Tools/CorpusRunner" / HERE.name


def run_suite(root):
    """The suite's exit status, run against the scorer sitting in `root`."""
    return subprocess.run([sys.executable, str(root / "test_score.py")],
                          capture_output=True, text=True).returncode


def baseline_is_clean():
    """The control. Without it every verdict below is vacuous.

    A mutation harness answers "did the suite notice?" by running the suite and
    reading its status. That answer only means anything if the suite passes
    when nothing has been mutated.
    """
    with scratch_tree() as root:
        return run_suite(root) == 0


def suite_notices(pattern, replacement):
    """Apply one mutation to a scratch copy and report whether the suite fails."""
    with scratch_tree() as root:
        text = (root / "score.py").read_text()
        mutated, count = re.subn(pattern, replacement, text)
        if count == 0:
            raise SystemExit(
                f"measure-gate: no call site matched {pattern!r}. The scorer "
                f"was restructured and this gate is now checking nothing — fix "
                f"the pattern rather than deleting the case.")
        (root / "score.py").write_text(mutated)
        return run_suite(root) != 0


def main():
    if not baseline_is_clean():
        print("measure gate FAILED: the suite does not pass on an unmutated "
              "copy, so every verdict below would read 'protected' whatever "
              "the mutation did. Fix the scratch tree or the suite first.",
              file=sys.stderr)
        return 1

    unprotected = []
    print(f"{'measure':<12} {'broken by':<24} verdict")
    print("-" * 56)
    for measure in FORCED:
        ok = suite_notices(rf'hit\("{measure}", ', f'hit("{measure}", True or ')
        unprotected += [] if ok else [measure]
        print(f"{measure:<12} {'forced to always pass':<24} "
              f"{'protected' if ok else 'UNPROTECTED'}")
    for counter in SUPPRESSED:
        ok = suite_notices(rf'tallies\[scope\]\["{counter}"\] \+= 1',
                           f'tallies[scope]["{counter}"] += 0')
        unprotected += [] if ok else [counter]
        print(f"{counter:<12} {'suppressed entirely':<24} "
              f"{'protected' if ok else 'UNPROTECTED'}")
    for name, pattern, replacement in REWRITTEN:
        ok = suite_notices(re.escape(pattern), replacement)
        unprotected += [] if ok else [name]
        print(f"{name:<12} {'always agrees':<24} "
              f"{'protected' if ok else 'UNPROTECTED'}")

    print()
    if unprotected:
        print(f"measure gate FAILED: {', '.join(unprotected)} can be broken "
              f"without the suite noticing, so a silent zero there would read "
              f"as a clean score.", file=sys.stderr)
        return 1
    total = len(FORCED) + len(SUPPRESSED) + len(REWRITTEN)
    print(f"measure gate ok: all {total} measures are "
          f"protected by the suite.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
