#!/usr/bin/env python3
"""SpeechLab command line. Local-only: this program never calls a network API."""
import argparse
import json
from pathlib import Path
import sqlite3
import sys
import tempfile

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from Sources import adapters, catalog, coverage, evaluation, exchange, signatures
from Sources.contracts import load_contracts, read_jsonl, validate_blueprints, validate_renderings, write_json, write_jsonl

DEFAULT_BLUEPRINTS = HERE / 'data/blueprints.jsonl'
DEFAULT_RENDERINGS = HERE / 'data/renderings.jsonl'
DEFAULT_PROBE = HERE.parent / 'PipelineProbe/build/probe'


def phenomena(): return json.loads((HERE / 'config/phenomena.json').read_text())['phenomena']


def contracts(args): return load_contracts(args.blueprints, args.renderings)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    sub.add_parser('build-catalog', help='Rebuild deterministic semantic catalog and initial renderings')
    for name in ('validate', 'coverage', 'evaluate', 'sealed-evaluate', 'export-ai'):
        p = sub.add_parser(name)
        p.add_argument('--blueprints', type=Path, default=DEFAULT_BLUEPRINTS)
        p.add_argument('--renderings', type=Path, default=DEFAULT_RENDERINGS)
        if name == 'coverage': p.add_argument('--output', type=Path, default=HERE / 'artifacts/coverage')
        if name == 'export-ai':
            p.add_argument('--output', type=Path, default=HERE / 'artifacts/export-for-ai'); p.add_argument('--batch-size', type=int, default=50)
        if name in ('evaluate', 'sealed-evaluate'):
            p.add_argument('--probe', type=Path, default=DEFAULT_PROBE); p.add_argument('--preset', choices=['diagnostic', 'focused', 'broad', 'stress'], default='diagnostic')
            p.add_argument('--phenomenon', action='append'); p.add_argument('--limit', type=int); p.add_argument('--batch-size', type=int, default=100)
            p.add_argument('--worker-index', type=int, default=0); p.add_argument('--worker-count', type=int, default=1)
            if name == 'evaluate': p.add_argument('--database', type=Path, required=True)
            else: p.add_argument('--aggregate-output', type=Path, required=True)
    p = sub.add_parser('integrity'); p.add_argument('--database', type=Path, required=True); p.add_argument('--run-id')
    p = sub.add_parser('failure-pack'); p.add_argument('--database', type=Path, required=True); p.add_argument('--run-id', required=True); p.add_argument('--output', type=Path, required=True)
    p = sub.add_parser('import-renderings'); p.add_argument('input', type=Path); p.add_argument('--blueprints', type=Path, default=DEFAULT_BLUEPRINTS); p.add_argument('--renderings', type=Path, default=DEFAULT_RENDERINGS); p.add_argument('--output', type=Path, required=True)
    p = sub.add_parser('import-failure-analysis'); p.add_argument('input', type=Path); p.add_argument('--output', type=Path, required=True)
    p = sub.add_parser('adapter-registry'); p.add_argument('--local-root', type=Path); p.add_argument('--output', type=Path)
    p = sub.add_parser('import-public'); p.add_argument('dataset', choices=sorted(adapters.REGISTRY)); p.add_argument('input', type=Path); p.add_argument('--output', type=Path, required=True); p.add_argument('--text-field', default='text'); p.add_argument('--id-field', default='id'); p.add_argument('--limit', type=int)
    args = parser.parse_args(argv)

    if args.command == 'build-catalog':
        families, blueprints, renderings = catalog.build(); print(json.dumps({'families': len(families), 'blueprints': len(blueprints), 'renderings': len(renderings)})); return
    if args.command == 'adapter-registry':
        result = adapters.registry(args.local_root)
        if args.output: write_json(args.output, {'datasets': result})
        print(json.dumps(result, indent=2)); return
    if args.command == 'import-public':
        print(json.dumps(adapters.import_jsonl(args.dataset, args.input, args.output, text_field=args.text_field, id_field=args.id_field, limit=args.limit))); return
    if args.command == 'import-failure-analysis': print(json.dumps(exchange.import_failure_analysis(args.input, args.output))); return
    if args.command == 'integrity': print(json.dumps(evaluation.integrity(args.database, args.run_id), indent=2)); return
    if args.command == 'failure-pack': print(json.dumps(signatures.failure_pack(args.database, args.run_id, args.output))); return
    if args.command == 'import-renderings':
        b, r = load_contracts(args.blueprints, args.renderings); print(json.dumps(exchange.import_renderings(args.input, b, r, {p['id'] for p in phenomena()}, args.output))); return

    b, r = contracts(args)
    if args.command == 'validate': print(json.dumps({'blueprints': len(b), 'renderings': len(r), 'phenomena': len(phenomena()), 'valid': True})); return
    if args.command == 'coverage': print(json.dumps(coverage.report(b, r, phenomena(), args.output), indent=2)); return
    if args.command == 'export-ai': print(json.dumps(exchange.export_for_ai(b, r, phenomena(), args.output, batch_size=args.batch_size))); return
    if args.preset == 'diagnostic':
        diagnostic = HERE / 'artifacts/coverage/diagnostic-renderings.jsonl'
        if args.command == 'evaluate' and diagnostic.exists(): r = validate_renderings(list(read_jsonl(diagnostic)), b, {p['id'] for p in phenomena()})
        elif args.limit is None: args.limit = 100
    if args.preset == 'focused' and not args.phenomenon: parser.error('focused preset requires --phenomenon')
    if args.preset == 'broad' and args.limit is None: args.limit = 10_000
    if args.command == 'evaluate':
        result = evaluation.run(b, r, args.database, args.probe, preset=args.preset, phenomena=args.phenomenon,
                                worker_index=args.worker_index, worker_count=args.worker_count, limit=args.limit, batch_size=args.batch_size)
        print(json.dumps(result, indent=2)); return
    # Sealed boundary: only aggregate metrics leave a temporary private database.
    if 'sealed' not in str(args.renderings).casefold(): parser.error('sealed-evaluate requires a rendering path explicitly named sealed')
    args.aggregate_output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='speechlab-sealed-') as td:
        result = evaluation.run(b, r, Path(td) / 'private.sqlite', args.probe, preset=args.preset, phenomena=args.phenomenon,
                                worker_index=args.worker_index, worker_count=args.worker_count, limit=args.limit, batch_size=args.batch_size, sealed=True)
        public = {k: result[k] for k in ('run_id', 'cases', 'passed', 'failed', 'complete')}
        public['sealed'] = True; public['individual_failures_disclosed'] = False
        write_json(args.aggregate_output, public); print(json.dumps(public, indent=2))


if __name__ == '__main__': main()
