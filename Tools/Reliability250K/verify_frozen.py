#!/usr/bin/env python3
"""Read-only Candidate47 identity check. Never compiles or runs production."""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RECORDS = ROOT / 'Docs/Understanding/Candidate47'

def sha(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--evidence-root', type=Path,
                        help='Optional preserved output/reliability-250k directory; verifies large evidence without rerunning it')
    args = parser.parse_args()
    manifest = json.loads((RECORDS / 'development/candidate47-source.json').read_text())
    actual_paths = {str(p.relative_to(ROOT)) for p in (ROOT / 'SpeakIt').rglob('*.swift')}
    failures = [f'Swift inventory differs: {sorted(actual_paths ^ set(manifest))}'] if actual_paths != set(manifest) else []
    checks = {ROOT / p: h for p, h in manifest.items()}
    frozen = json.loads((RECORDS / 'FROZEN_CANDIDATE.json').read_text())
    for original, expected in frozen['evaluator_identity'].items():
        checks[ROOT / ('Tools/' + original.split('/Tools/', 1)[1])] = expected
    if args.evidence_root:
        record = json.loads((RECORDS / 'evidence-integrity.json').read_text())
        checks.update({args.evidence_root / p: h for p, h in record['artifacts_sha256'].items()})
    for path, expected in checks.items():
        if not path.is_file() or sha(path) != expected:
            failures.append(str(path))
    if failures:
        raise SystemExit('Candidate47 identity FAILED:\n' + '\n'.join(failures))
    print(f'Candidate47 identity PASS: {len(manifest)} Swift files; {len(checks)} total hash checks. No production execution.')

if __name__ == '__main__':
    main()
