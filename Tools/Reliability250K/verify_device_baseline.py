#!/usr/bin/env python3
"""Read-only canonical device-baseline identity check. Never compiles or runs production.

Sibling of `verify_frozen.py`, which answers "is this tree Candidate47?". This
answers two different questions about the tree device evidence is gathered from:

1. Is this tree the canonical device baseline, byte for byte?
2. Does it differ from Candidate47 in EXACTLY the deviations the receipt names,
   and no others?

The second question is the one prose cannot hold. "Two intentional deviations"
is true the day it is written and silently stops being true the first time
somebody lands a third. Here a third deviation fails the check by name.

Only question 1 reads the working tree. It pins a tree, so it must fail the
moment `main` legitimately moves -- that is what a baseline is -- and it is
therefore not wired into CI. Run it against a fresh checkout of the baseline
commit, which is the only tree it describes.

Question 2 compares the baseline manifest with Candidate47's, and the receipt
with both, and first checks that Candidate47's manifest is itself the file that
was frozen -- otherwise every deviation below is measured against an altered
reference. Those are three frozen files; no working tree is read, so they cannot
redden when `main` legitimately moves. `--receipt-only` runs exactly those, and
that is what CI runs. It catches the realistic mistake -- somebody regenerates
the manifest after landing a change and leaves the receipt claiming two -- and
it is honest about the rest: a receipt-only PASS says the three documents agree
with each other, and says NOTHING about whether any checkout matches them.
"""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

#: Every file this check reads, relative to the repository root. Declared
#: because a check nobody can invoke is indistinguishable from one that holds:
#: editing any of these changes the verdict, so editing any of them has to
#: start the CI job that runs the check. `test_score.py` reads this name and
#: fails when one of them matches no path filter that starts `language-tools`.
#:
#: It is a declaration, so it can drift from what the code opens. Two things
#: stop that: the module resolves its own paths through it, below, so a read
#: that is not listed has to bypass the constant deliberately; and
#: `test_score.py` also checks that no other repository path literal appears
#: in this file. Both were falsified when this was written.
INPUTS = (
    'Docs/Understanding/DeviceBaseline/device-baseline-source.json',
    'Docs/Understanding/DeviceBaseline/RECEIPT.json',
    'Docs/Understanding/Candidate47/development/candidate47-source.json',
    'Docs/Understanding/Candidate47/evidence-integrity.json',
    'Docs/Understanding/Candidate47/FROZEN_CANDIDATE.json',
)

MANIFEST_PATH, RECEIPT_PATH, REFERENCE_PATH, EVIDENCE_PATH, FROZEN_PATH = (
    ROOT / rel for rel in INPUTS)


def sha(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--quiet', action='store_true', help='print nothing on success')
    parser.add_argument('--receipt-only', action='store_true',
                        help='check only that the receipt and the two manifests agree; '
                             'read no working tree, so safe to run in CI')
    args = parser.parse_args()

    manifest = json.loads(MANIFEST_PATH.read_text())
    receipt = json.loads(RECEIPT_PATH.read_text())
    failures = []

    # 1. Inventory and contents against the baseline manifest. The ONLY check that
    #    reads the working tree, and therefore the only one that cannot run in CI.
    if not args.receipt_only:
        actual = {str(p.relative_to(ROOT)) for p in (ROOT / 'SpeakIt').rglob('*.swift')}
        if actual != set(manifest):
            failures.append(f'Swift inventory differs: {sorted(actual ^ set(manifest))}')
        for rel, expected in sorted(manifest.items()):
            path = ROOT / rel
            if not path.is_file():
                failures.append(f'missing: {rel}')
            elif sha(path) != expected:
                failures.append(f'content differs: {rel}')

    # 0. The reference manifest itself. Everything below measures deviations
    #    AGAINST Candidate47's manifest, so an edit to that file makes a real
    #    deviation disappear and leaves every other check here green. Its
    #    SHA-256 was already recorded twice when Candidate47 was frozen, in
    #    evidence-integrity.json and in FROZEN_CANDIDATE.json, but nothing
    #    recomputed it: verify_frozen.py consults artifacts_sha256 only under
    #    --evidence-root, and resolves those paths against the preserved
    #    output directory rather than against the manifest it just read. The
    #    value was present and unchecked, which reads exactly like a check.
    #
    #    Both recorded copies are used rather than one copied into the receipt:
    #    a fourth copy would be a fourth thing to drift. Requiring the two to
    #    agree means a single edit anywhere in the set fails by name.
    reference = REFERENCE_PATH
    recorded = {
        EVIDENCE_PATH.name:
            json.loads(EVIDENCE_PATH.read_text())
            ['artifacts_sha256'].get('development/candidate47-source.json'),
        FROZEN_PATH.name:
            json.loads(FROZEN_PATH.read_text())
            ['artifacts_sha256'].get('candidate47-source.json'),
    }
    measured_reference = sha(reference)
    for source, expected in sorted(recorded.items()):
        if expected is None:
            failures.append(f'{source} no longer records the Candidate47 manifest hash')
        elif expected != measured_reference:
            failures.append(
                f"Candidate47's own manifest does not match the hash {source} "
                f'recorded when it was frozen: every deviation measured below '
                f'is against an altered reference')

    # 2. The deviation set against Candidate47 must be exactly what the receipt claims.
    #    Candidate47's manifest is read, never written.
    frozen = json.loads(reference.read_text())
    declared = {entry['path'] for entry in receipt['deviations_from_candidate47']['files']}
    measured = {rel for rel, h in manifest.items() if frozen.get(rel) != h}

    for rel in sorted(measured - declared):
        failures.append(f'UNDECLARED deviation from Candidate47: {rel}')
    for rel in sorted(declared - measured):
        failures.append(f'declared deviation is absent (receipt is stale): {rel}')
    if set(manifest) != set(frozen):
        failures.append(f'Swift inventory differs from Candidate47: {sorted(set(manifest) ^ set(frozen))}')

    # 3. The receipt's own per-file hashes must match both sides, so the receipt
    #    cannot drift from the manifest it describes.
    for entry in receipt['deviations_from_candidate47']['files']:
        rel = entry['path']
        if frozen.get(rel) != entry['candidate47_sha256']:
            failures.append(f'receipt quotes a stale Candidate47 hash for {rel}')
        if manifest.get(rel) != entry['device_baseline_sha256']:
            failures.append(f'receipt quotes a stale baseline hash for {rel}')

    if failures:
        raise SystemExit('Device baseline identity FAILED:\n  ' + '\n  '.join(failures))

    if args.quiet:
        return

    if args.receipt_only:
        print(f'Device baseline receipt PASS: the receipt and both manifests agree on '
              f'{len(measured)} deviation(s) across {len(manifest)} Swift files.')
        for entry in receipt['deviations_from_candidate47']['files']:
            kind = 'provenance only' if entry.get('provenance_only') else 'behavioural'
            print(f"  {entry['path']} ({kind})")
        print(f"  Candidate47's manifest is the frozen one ({measured_reference[:8]}), "
              f'agreed by {len(recorded)} records')
        print('  NO working tree was read: this says nothing about whether any')
        print('  checkout matches the manifest. Run without --receipt-only for that.')
        return

    same = len(manifest) - len(measured)
    print(f'Device baseline identity PASS: {len(manifest)} Swift files, '
          f'{same} byte-identical to Candidate47, '
          f'{len(measured)} declared deviation(s). No production execution.')
    for entry in receipt['deviations_from_candidate47']['files']:
        kind = 'provenance only' if entry.get('provenance_only') else 'behavioural'
        print(f"  {entry['path']} ({kind})")
    print(f"  Candidate47's manifest is the frozen one ({measured_reference[:8]}), "
          f'agreed by {len(recorded)} records')
    established = receipt['commit']['swift_tree_established_by']
    print(f'  Swift tree established by {established}')
    print('  a PASS describes THIS checkout, whichever commit it stands on')


if __name__ == '__main__':
    main()
