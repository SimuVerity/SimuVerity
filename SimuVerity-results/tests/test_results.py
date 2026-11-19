"""Behavioral checks for the result format."""
import importlib.util
import csv
import json
from pathlib import Path
import shutil
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('validator',ROOT/'tools/validate_results.py')
validator=importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)


class ResultFormatTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root=Path(self.tmp.name)/'results'
        shutil.copytree(ROOT,self.root,ignore=shutil.ignore_patterns('__pycache__','.git'))

    def test_valid_results(self):
        self.assertEqual(validator.validate_repository(self.root),[])

    def test_rejects_unexpected_result_table(self):
        (self.root/'task-details.csv').write_text('task_id,total\nsample,10.000000\n',encoding='utf-8')
        self.assertTrue(validator.validate_repository(self.root))

    def test_rejects_unsupported_csv_schema(self):
        (self.root/'ratings.csv').write_text('candidate_id,evaluator_total,expert_mean\nsample,10.000000,1\n',encoding='utf-8')
        self.assertTrue(validator.validate_repository(self.root))

    def test_rejects_changed_published_mean(self):
        p=next((self.root/'runs').glob('*/summary.json'))
        v=json.loads(p.read_text());v['score_mean']='99.000000';p.write_text(json.dumps(v))
        self.assertTrue(validator.validate_repository(self.root))

    def test_rejects_missing_repeat_summary(self):
        next((self.root/'runs').glob('*/run2/summary.json')).unlink()
        self.assertTrue(validator.validate_repository(self.root))

    def test_rejects_unexpected_metadata_field(self):
        p=next((self.root/'runs').glob('*/run.json'))
        v=json.loads(p.read_text());v['scores_file']='scores.csv';p.write_text(json.dumps(v))
        self.assertTrue(validator.validate_repository(self.root))

    def test_rejects_impossible_gate_counts(self):
        p=next((self.root/'runs').glob('*/run1/summary.json'))
        v=json.loads(p.read_text());v['g_pass_count']=v['task_count']+1;p.write_text(json.dumps(v))
        self.assertTrue(validator.validate_repository(self.root))

    def test_rejects_deleted_aggregate_columns(self):
        for relative in ['leaderboard.csv','ablations/mcp-10/summary.csv']:
            with self.subTest(table=relative):
                p=self.root/relative
                original=p.read_bytes()
                with p.open(encoding='utf-8-sig',newline='') as f:ids=[r['run_id'] for r in csv.DictReader(f)]
                p.write_text('run_id\n'+'\n'.join(ids)+'\n',encoding='utf-8')
                self.assertTrue(validator.validate_repository(self.root))
                p.write_bytes(original)


if __name__=='__main__':unittest.main()
