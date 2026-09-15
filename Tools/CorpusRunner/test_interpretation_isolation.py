#!/usr/bin/env python3
"""The two rules that make the Foundation Models path safe to point at a sealed set.

Both are properties of the source text, so they are checked on Linux on every
pull request rather than on a Mac by dispatch. That matters more here than
usual: the thing being protected is a held-out corpus, and a set that has been
sent to somebody's server cannot be made unseen again — there is no red build
that undoes it.

1. **Nothing in the interpretation path can reach the network.** Not a URL, not
   a URLSession, not a socket. The only model it may name is Apple's on-device
   `SystemLanguageModel`.

2. **The deterministic half does not import FoundationModels.** The policy, the
   bridge and the schema have to compile and be testable where no model exists,
   or the safety argument is only checkable on hardware nobody in this
   repository has had.

Neither rule is a substitute for reading the code. They are here because both
are easy to break by accident later, in a file nobody re-reads, and a promise
that is not mechanical stops being true quietly.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "SpeakIt" / "Interpretation"

#: Anything that could move a transcript off the device. Matched as whole words
#: so a comment saying "no network" does not fail its own check.
NETWORK = [
    "URLSession",
    "URLRequest",
    "NSURLConnection",
    "CFSocket",
    "NWConnection",
    "Network",
    "http",
    "https",
]

#: The only model the path may name.
ALLOWED_MODEL = "SystemLanguageModel"
OTHER_MODELS = ["OpenAI", "Anthropic", "Gemini", "CloudModel", "ServerModel", "MLModel"]

#: The files that must stay free of FoundationModels.
DETERMINISTIC = [
    "CaptureInterpretation.swift",
    "InterpretationPolicy.swift",
    "InterpretationBridge.swift",
]


def code_lines(path):
    """Source with comment lines removed, so prose about the rule is not the rule."""
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        stripped = line.strip()
        if stripped.startswith("//"):
            continue
        yield number, line


def main():
    if not SOURCE.is_dir():
        print(f"interpretation isolation: {SOURCE} is missing")
        return 1

    failures = []
    files = sorted(SOURCE.glob("*.swift"))
    if not files:
        failures.append(f"{SOURCE} contains no Swift files")

    for path in files:
        relative = path.relative_to(ROOT)
        for number, line in code_lines(path):
            for symbol in NETWORK:
                if re.search(rf"\b{re.escape(symbol)}\b", line, flags=re.IGNORECASE):
                    failures.append(f"{relative}:{number} names {symbol}; this path is on-device only")
            for symbol in OTHER_MODELS:
                if re.search(rf"\b{re.escape(symbol)}\b", line):
                    failures.append(f"{relative}:{number} names {symbol}; the only model allowed is {ALLOWED_MODEL}")

        if path.name in DETERMINISTIC:
            for number, line in code_lines(path):
                if "FoundationModels" in line:
                    failures.append(
                        f"{relative}:{number} imports FoundationModels; "
                        "the policy, bridge and schema must be testable without a model"
                    )

    if failures:
        print("interpretation isolation FAILED")
        for failure in failures:
            print(f"  {failure}")
        return 1

    print(f"interpretation isolation ok: {len(files)} files, on-device only")
    return 0


if __name__ == "__main__":
    sys.exit(main())
