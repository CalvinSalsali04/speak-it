#!/usr/bin/env python3
"""The rules that make the Foundation Models path safe to point at a sealed set.

All three are properties of the source text, so they are checked on Linux on
every pull request rather than on a Mac by dispatch. That matters more here than
usual: the thing being protected is a held-out corpus, and a set that has been
sent to somebody's server cannot be made unseen again — there is no red build
that undoes it.

1. **Nothing in the interpretation path can reach the network.** Not a URL, not
   a URLSession, not a socket. The only model it may name is Apple's on-device
   `SystemLanguageModel`. "The path" is every tree that ends up in the binary,
   the probe included: the probe is the part that actually reads a set off disk,
   so a check that stopped at the app sources would be watching the half that
   never holds a capture.

2. **The deterministic half does not import FoundationModels.** The policy, the
   bridge and the schema have to compile and be testable where no model exists,
   or the safety argument is only checkable on hardware nobody in this
   repository has had.

3. **The prompt carries no quoted example text.** The first run on a device
   (46 `runon` captures, 2026-09-16) found the model copying its own brief into
   the transcript's place: ten captures emitted a segment quoted as the bare
   word `tomorrow`, which was the example inside the `@Guide` for
   `carriedContext`, and two more emitted sentences lifted from the
   instructions. An illustration sitting in a field's own description is a
   candidate value for that field. This rule is narrower than the defect: it
   catches an example somebody wrote in quotation marks, and it cannot catch
   one written without them. That is stated here rather than implied, because a
   check whose reach is assumed to match its name is how the wrong thing gets
   trusted.

None of these is a substitute for reading the code. They are here because all
three are easy to break by accident later, in a file nobody re-reads, and a
promise that is not mechanical stops being true quietly.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

#: Every tree that ends up inside the interpretation binary. The app sources are
#: the obvious half; the probe is the half that actually holds a sealed set's
#: text in memory, so a rule that stopped at `SpeakIt/Interpretation` would be
#: checking the side that never sees a capture. `Tools/PipelineProbe` is here
#: because `Tools/InterpretationProbe/build.sh` compiles two of its files.
SOURCES = [
    ROOT / "SpeakIt" / "Interpretation",
    ROOT / "Tools" / "InterpretationProbe",
    ROOT / "Tools" / "PipelineProbe",
]

#: Directory names skipped while walking. `build/` holds generated source slices
#: and the binary; it is scratch, not something a pull request can change.
SKIPPED_DIRECTORIES = {"build", ".build"}

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

#: The file holding the prompt: the instructions block and the `@Guide`
#: descriptions the schema generates against.
PROMPT_FILE = "ModelInterpreter.swift"

#: A quoted example. The opening mark has to follow whitespace, which is what
#: separates it from a possessive: the apostrophe in `person's` is preceded by
#: a letter and so can never open a span.
QUOTED_EXAMPLE = re.compile(r"(?<=\s)'[^']+'")


def code_lines(path):
    """Source with comment lines removed, so prose about the rule is not the rule."""
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        stripped = line.strip()
        if stripped.startswith("//"):
            continue
        yield number, line


def swift_files(root):
    """Every Swift file under `root`, at any depth, outside the scratch directories.

    Recursive on purpose: a nested directory is the cheapest way to add a file
    nobody re-reads, which is the failure this whole check exists to catch.
    """
    for path in sorted(root.rglob("*.swift")):
        if SKIPPED_DIRECTORIES.intersection(path.relative_to(root).parts[:-1]):
            continue
        yield path


def prompt_text(path):
    """The instructions block and every `@Guide` description, with line numbers.

    Both are prose the model is shown, and both were leaking. Read from the
    source rather than by importing anything, because this has to run on a
    machine with no Swift.
    """
    inside = False
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        if "static let instructions" in line:
            inside = True
            continue
        if inside:
            if line.strip() == '"""':
                inside = False
                continue
            yield number, "the instructions", line
            continue
        match = re.search(r'@Guide\(description:\s*"(.*)"\s*\)', line)
        if match:
            yield number, "a @Guide description", match.group(1)


def prompt_examples(path, relative):
    """Quoted example text anywhere the model can read it."""
    failures = []
    for number, where, text in prompt_text(path):
        for quoted in QUOTED_EXAMPLE.findall(text):
            failures.append(
                f"{relative}:{number} puts a quoted example in {where}: {quoted}. "
                "A quotable span is a value the model can copy into the field it "
                "describes; say what the thing is instead of quoting one"
            )
        # Inside a Swift multi-line string a double quote needs no escape, so
        # the instructions' own examples were plain `"..."` and the
        # apostrophe rule above never saw them. Two of the four leaking sites
        # were this shape; a rule that caught the other two and stopped would
        # have read as protection.
        if where == "the instructions" and '"' in text:
            failures.append(
                f"{relative}:{number} puts a quoted example in {where}: "
                f"{text.strip()[:60]}. A quotable span is a value the model can "
                "copy into a field; say what the thing is instead of quoting one"
            )
    return failures


def main():
    failures = []
    files = []
    for source in SOURCES:
        if not source.is_dir():
            print(f"interpretation isolation: {source} is missing")
            return 1
        found = list(swift_files(source))
        if not found:
            failures.append(f"{source.relative_to(ROOT)} contains no Swift files")
        files.extend(found)

    for path in files:
        relative = path.relative_to(ROOT)
        for number, line in code_lines(path):
            for symbol in NETWORK:
                if re.search(rf"\b{re.escape(symbol)}\b", line, flags=re.IGNORECASE):
                    failures.append(f"{relative}:{number} names {symbol}; this path is on-device only")
            for symbol in OTHER_MODELS:
                if re.search(rf"\b{re.escape(symbol)}\b", line):
                    failures.append(f"{relative}:{number} names {symbol}; the only model allowed is {ALLOWED_MODEL}")

        if path.name == PROMPT_FILE:
            failures.extend(prompt_examples(path, relative))

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

    trees = ", ".join(str(source.relative_to(ROOT)) for source in SOURCES)
    print(f"interpretation isolation ok: {len(files)} files across {trees}, on-device only")
    return 0


if __name__ == "__main__":
    sys.exit(main())
