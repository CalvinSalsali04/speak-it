#!/usr/bin/env python3
"""Renders the failing assertions of an `xcresulttool` summary as markdown.

Split out of `unit-tests.sh` so the same rendering reaches the job log and the
GitHub job summary, and so it can be read without reading shell quoting.

    xcresult-failures.py "<title>" <summary.json>
"""
import json
import sys

title, path = sys.argv[1], sys.argv[2]
data = json.load(open(path))
print(f"### {title}")
print()
print("| Result | Passed | Failed | Skipped |")
print("|---|---|---|---|")
print(f"| {data.get('result', '?')} | {data.get('passedTests', '?')} | "
      f"{data.get('failedTests', '?')} | {data.get('skippedTests', '?')} |")
failures = data.get("testFailures", [])
# Enough to see a pattern across suites. A run that fails in more places than
# this has a cause the first sixty already name.
for failure in failures[:60]:
    text = " ".join(failure.get("failureText", "").split())[:400]
    print(f"- `{failure.get('testName', '?')}` - {text}")
if len(failures) > 60:
    print(f"- ...and {len(failures) - 60} more")
