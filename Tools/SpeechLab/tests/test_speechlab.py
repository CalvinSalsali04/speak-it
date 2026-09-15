import json
from pathlib import Path
import sqlite3
import stat
import subprocess
import sys
import tempfile
import unittest

LAB = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(LAB))

from Sources import catalog, coverage, evaluation, exchange, signatures
from Sources.contracts import (digest, load_contracts, read_jsonl, rendering_identity,
                               semantic_identity, validate_blueprints, validate_renderings)


class SpeechLabTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.blueprints, cls.renderings = load_contracts(LAB / 'data/blueprints.jsonl', LAB / 'data/renderings.jsonl')
        cls.phenomena = json.loads((LAB / 'config/phenomena.json').read_text())['phenomena']
        cls.phenomenon_ids = {p['id'] for p in cls.phenomena}

    def test_schema_validation_and_catalog_size(self):
        self.assertGreaterEqual(len(self.blueprints), 250)
        self.assertEqual(len(self.blueprints), len({b['family_id'] for b in self.blueprints.values()}))

    def test_deterministic_semantic_identity(self):
        bp = next(iter(self.blueprints.values()))
        self.assertEqual(semantic_identity(bp), semantic_identity(json.loads(json.dumps(bp))))

    def test_catalog_generation_is_byte_deterministic(self):
        with tempfile.TemporaryDirectory() as td:
            one, two = Path(td) / 'one', Path(td) / 'two'
            catalog.build(one, seed=17); catalog.build(two, seed=17)
            for name in ('family-definitions.jsonl', 'blueprints.jsonl', 'renderings.jsonl'):
                self.assertEqual((one / name).read_bytes(), (two / name).read_bytes())

    def test_duplicate_blueprint_ids_rejected(self):
        bp = next(iter(self.blueprints.values()))
        with self.assertRaises(ValueError): validate_blueprints([bp, bp])

    def test_surface_wording_does_not_create_semantic_identity(self):
        bp = json.loads(json.dumps(next(iter(self.blueprints.values()))))
        first = semantic_identity(bp); bp['source_provenance']['wording_note'] = 'different surface plan'
        self.assertEqual(first, semantic_identity(bp))

    def test_rendering_duplicate_detection(self):
        r = json.loads(json.dumps(next(iter(self.renderings.values()))))
        r['rendering_id'] = 'rd-' + '0' * 24
        with self.assertRaises(ValueError): validate_renderings([next(iter(self.renderings.values())), r], self.blueprints, self.phenomenon_ids)

    def test_lineage_rejects_self_reference(self):
        r = json.loads(json.dumps(next(iter(self.renderings.values()))))
        r['mutation_lineage'] = [r['rendering_id']]
        with self.assertRaises(ValueError): validate_renderings([r], self.blueprints, self.phenomenon_ids)

    def _probe(self, directory):
        path = Path(directory) / 'fake-probe'
        path.write_text("""#!/usr/bin/env python3
import json,sys
for text in sys.stdin:
 text=text.strip()
 if text: print(json.dumps({'text':text,'items':[],'operations':[]}))
""")
        path.chmod(path.stat().st_mode | stat.S_IXUSR)
        return path

    def test_runner_resume_and_complete_retention(self):
        with tempfile.TemporaryDirectory() as td:
            sample = dict(list(self.renderings.items())[:3]); db = Path(td) / 'run.sqlite'; probe = self._probe(td)
            one = evaluation.run(self.blueprints, sample, db, probe, limit=3, batch_size=2)
            two = evaluation.run(self.blueprints, sample, db, probe, limit=3, batch_size=2)
            self.assertEqual(one['retained_rows'], 3); self.assertEqual(two['retained_rows'], 3)
            self.assertEqual(evaluation.integrity(db)[0]['records'], 3)

    def test_integrity_detects_corrupt_record(self):
        with tempfile.TemporaryDirectory() as td:
            sample = dict(list(self.renderings.items())[:1]); db = Path(td) / 'run.sqlite'
            result = evaluation.run(self.blueprints, sample, db, self._probe(td), limit=1)
            con = sqlite3.connect(db); con.execute("UPDATE results SET payload_hash='bad'"); con.commit(); con.close()
            with self.assertRaises(ValueError): evaluation.integrity(db, result['run_id'])

    def test_integrity_detects_missing_record(self):
        with tempfile.TemporaryDirectory() as td:
            sample = dict(list(self.renderings.items())[:2]); db = Path(td) / 'run.sqlite'
            result = evaluation.run(self.blueprints, sample, db, self._probe(td), limit=2)
            con = sqlite3.connect(db); con.execute('DELETE FROM results WHERE rendering_id=(SELECT rendering_id FROM results LIMIT 1)'); con.commit(); con.close()
            with self.assertRaises(ValueError): evaluation.integrity(db, result['run_id'])

    def test_failure_signature_stability(self):
        payload = {'difference': {'changed_fields': ['person_preservation'], 'lost_facts': ['Maya Chen'], 'invented_metadata': [], 'expected_item_count': 1, 'actual_item_count': 1},
                   'expected': {'items': [{'person': 'Maya Chen', 'location': None, 'facts': ['Call Maya']}]}}
        self.assertEqual(signatures.normalize_difference(payload), signatures.normalize_difference(json.loads(json.dumps(payload))))

    def test_coverage_and_set_cover(self):
        selected, gaps = coverage.greedy_set_cover(self.blueprints, self.renderings, {'phenomenon:' + p for p in self.phenomenon_ids})
        self.assertFalse(gaps); self.assertLessEqual(len(selected), len(self.phenomenon_ids))

    def test_sealed_name_boundary(self):
        source = (LAB / 'speechlab.py').read_text()
        self.assertIn("'sealed' not in str(args.renderings).casefold()", source)
        self.assertIn('individual_failures_disclosed', source)

    def test_sealed_command_releases_only_aggregate(self):
        with tempfile.TemporaryDirectory() as td:
            td = Path(td); probe = self._probe(td); bp_path = td / 'sealed-blueprints.jsonl'; rd_path = td / 'sealed-renderings.jsonl'
            bp = next(iter(self.blueprints.values())); rd = next(r for r in self.renderings.values() if r['blueprint_id'] == bp['blueprint_id'])
            bp_path.write_text(json.dumps(bp) + '\n'); rd_path.write_text(json.dumps(rd) + '\n')
            aggregate = td / 'aggregate.json'
            subprocess.run([sys.executable, str(LAB / 'speechlab.py'), 'sealed-evaluate', '--blueprints', str(bp_path),
                            '--renderings', str(rd_path), '--probe', str(probe), '--aggregate-output', str(aggregate)],
                           check=True, text=True, capture_output=True)
            result = json.loads(aggregate.read_text())
            self.assertEqual(set(result), {'run_id', 'cases', 'passed', 'failed', 'complete', 'sealed', 'individual_failures_disclosed'})
            self.assertFalse(result['individual_failures_disclosed'])

    def test_import_export_roundtrip(self):
        with tempfile.TemporaryDirectory() as td:
            out = Path(td) / 'export'; exchange.export_for_ai(self.blueprints, self.renderings, self.phenomena, out, batch_size=2)
            bp = next(iter(self.blueprints.values())); row = {'blueprint_id': bp['blueprint_id'], 'text': 'A wholly unique imported speech rendering.',
                  'phenomena': ['uncertainty'], 'meaning_preservation': 'uncertain', 'generator': {'kind':'external_ai','name':'test','version':'1'},
                  'provenance': {'test': True}, 'seed': None, 'mutation_lineage': [], 'equivalence_class': bp['blueprint_id']}
            incoming = Path(td) / 'incoming.jsonl'; incoming.write_text(json.dumps(row) + '\n')
            combined = Path(td) / 'combined.jsonl'; result = exchange.import_renderings(incoming, self.blueprints, self.renderings, self.phenomenon_ids, combined)
            self.assertEqual(result['imported'], 1); self.assertEqual(len(list(read_jsonl(combined))), len(self.renderings) + 1)

    def test_taxonomy_has_counterexamples_and_policy(self):
        self.assertGreaterEqual(len(self.phenomena), 60)
        for p in self.phenomena:
            self.assertTrue(p['examples']); self.assertTrue(p['counterexamples'])
            self.assertIn('blind_mutation_suitable', p); self.assertIn('safety_level', p)


if __name__ == '__main__': unittest.main()
