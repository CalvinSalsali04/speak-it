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
broken measure cannot reach a report. Checked both ways round, so this gate is
not itself the thing that cannot fail — with every test in the suite turned
into a no-op it reports all eleven as unprotected and exits non-zero.

Two kinds of break, because the scorer records results two ways:

  * measures routed through `hit()` are forced to pass unconditionally
  * counters tallied directly are suppressed so they can never report

Run it from the repository root:

    python3 Tools/CorpusRunner/everyday/measure-gate.py
"""
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


def suite_notices(pattern, replacement):
    """Apply one mutation to a scratch copy and report whether the suite fails."""
    with tempfile.TemporaryDirectory() as tmp:
        root = pathlib.Path(tmp) / HERE.name
        shutil.copytree(HERE, root)
        text = (root / "score.py").read_text()
        mutated, count = re.subn(pattern, replacement, text)
        if count == 0:
            raise SystemExit(
                f"measure-gate: no call site matched {pattern!r}. The scorer "
                f"was restructured and this gate is now checking nothing — fix "
                f"the pattern rather than deleting the case.")
        (root / "score.py").write_text(mutated)
        result = subprocess.run([sys.executable, str(root / "test_score.py")],
                                capture_output=True, text=True)
        return result.returncode != 0


def main():
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

    print()
    if unprotected:
        print(f"measure gate FAILED: {', '.join(unprotected)} can be broken "
              f"without the suite noticing, so a silent zero there would read "
              f"as a clean score.", file=sys.stderr)
        return 1
    print(f"measure gate ok: all {len(FORCED) + len(SUPPRESSED)} measures are "
          f"protected by the suite.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
