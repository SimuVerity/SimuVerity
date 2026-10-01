from __future__ import annotations

import csv
from decimal import Decimal
import importlib.util
import json
from pathlib import Path
import shutil
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
VALIDATOR = ROOT / "tools" / "validate_results.py"
SPEC = importlib.util.spec_from_file_location("simuverity_result_validator", VALIDATOR)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("could not load result validator")
VALIDATE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(VALIDATE)


class DomainFormatTests(unittest.TestCase):
    def test_domain_scores_use_zero_through_one_hundred(self) -> None:
        for text in ("0.000000", "0.123456", "37.500000", "99.999999", "100.000000"):
            with self.subTest(text=text):
                errors: list[str] = []
                self.assertEqual(
                    VALIDATE._domain_six(text, "domain", errors), Decimal(text)
                )
                self.assertEqual(errors, [])

    def test_domain_scores_reject_values_outside_the_range(self) -> None:
        for text in ("-0.000001", "100.000001", "250.000000"):
            with self.subTest(text=text):
                errors: list[str] = []
                VALIDATE._domain_six(text, "domain", errors)
                self.assertIn("domain is outside 0 through 100", errors)

    def test_domain_scores_preserve_empty_and_finite_contracts(self) -> None:
        errors: list[str] = []
        self.assertIsNone(VALIDATE._domain_six("", "domain", errors))
        self.assertEqual(errors, [])
        for text in ("NaN", "Infinity", "-Infinity"):
            with self.subTest(text=text):
                errors = []
                self.assertIsNone(VALIDATE._domain_six(text, "domain", errors))
                self.assertIn("domain must be finite", errors)


class PositiveTotalUniquenessTests(unittest.TestCase):
    def check_rows(self, entries: list[tuple[str, str, str, str, str]]) -> list[str]:
        results: dict = {}
        for parent_id, repeat_id, task_id, total, accuracy in entries:
            repeat = results.setdefault(parent_id, {"repeats": {}})["repeats"].setdefault(
                repeat_id, {"rows": []}
            )
            repeat["rows"].append({"task_id": task_id, "total": total, "A": accuracy})
        errors: list[str] = []
        VALIDATE._check_positive_total_uniqueness(results, errors)
        return errors

    def test_matching_total_with_different_domains_fails(self) -> None:
        errors = self.check_rows([
            (VALIDATE.LEADERBOARD_ORDER[0], "run2", "XELEC-06", "50.000000", "10.000000"),
            (VALIDATE.LEADERBOARD_ORDER[1], "run3", "XELEC-07", "50.000000", "90.000000"),
        ])
        self.assertEqual(len(errors), 1)
        self.assertIn("duplicate positive total 50.000000", errors[0])

    def test_run1_only_matches_are_allowed(self) -> None:
        self.assertEqual(self.check_rows([
            (VALIDATE.LEADERBOARD_ORDER[0], "run1", "XELEC-06", "50.000000", "10.000000"),
            (VALIDATE.LEADERBOARD_ORDER[1], "run1", "XELEC-07", "50.000000", "90.000000"),
        ]), [])

    def test_run1_matches_do_not_hide_a_later_repeat(self) -> None:
        errors = self.check_rows([
            (VALIDATE.LEADERBOARD_ORDER[0], "run1", "XELEC-06", "50.000000", "10.000000"),
            (VALIDATE.LEADERBOARD_ORDER[1], "run1", "XELEC-07", "50.000000", "90.000000"),
            (VALIDATE.LEADERBOARD_ORDER[2], "run2", "XELEC-08", "50.000000", "80.000000"),
        ])
        self.assertEqual(len(errors), 1)

    def test_zero_totals_are_excluded(self) -> None:
        self.assertEqual(self.check_rows([
            (parent, repeat, "XELEC-06", "0.000000", "0.000000")
            for parent in VALIDATE.LEADERBOARD_ORDER
            for repeat in VALIDATE.REPEAT_IDS
        ]), [])

    def test_full_mcp_copy_is_excluded(self) -> None:
        self.assertEqual(self.check_rows([
            (VALIDATE.LEADERBOARD_ORDER[0], "run2", "XELEC-07", "50.000000", "90.000000"),
            (VALIDATE.ABLATION_ORDER[0], "run2", "XELEC-07", "50.000000", "90.000000"),
        ]), [])

    def test_no_cross_model_minimum_gap_is_added(self) -> None:
        self.assertEqual(self.check_rows([
            (VALIDATE.LEADERBOARD_ORDER[0], "run2", "XELEC-06", "50.000001", "90.000000"),
            (VALIDATE.LEADERBOARD_ORDER[1], "run3", "XELEC-07", "50.000002", "90.000000"),
        ]), [])

    def test_other_tasks_in_the_same_experiment_are_checked(self) -> None:
        errors = self.check_rows([
            (VALIDATE.LEADERBOARD_ORDER[0], "run2", "XELEC-06", "50.000000", "90.000000"),
            (VALIDATE.LEADERBOARD_ORDER[0], "run3", "XELEC-07", "50.000000", "90.000000"),
        ])
        self.assertEqual(len(errors), 1)


class ZeroVectorUniquenessTests(unittest.TestCase):
    def check_rows(self, entries: list[tuple[str, str, str, tuple[str, ...]]]) -> list[str]:
        results: dict = {}
        for parent_id, repeat_id, task_id, vector in entries:
            repeat = results.setdefault(parent_id, {"repeats": {}})["repeats"].setdefault(
                repeat_id, {"rows": []}
            )
            repeat["rows"].append({
                "task_id": task_id, "total": "0.000000",
                **dict(zip(VALIDATE.DOMAIN_FIELDS, vector)),
            })
        errors: list[str] = []
        VALIDATE._check_same_task_zero_vectors(results, errors)
        return errors

    def test_repeated_nonzero_domains_at_zero_total_fail(self) -> None:
        vector = ("50.000000", "0.000000", "", "", "25.000000", "")
        for pair in (("run1", "run2"), ("run2", "run3")):
            with self.subTest(pair=pair):
                errors = self.check_rows([
                    (VALIDATE.LEADERBOARD_ORDER[0], repeat, "XELEC-06", vector)
                    for repeat in pair
                ])
                self.assertEqual(len(errors), 1)
                self.assertIn("duplicate nonzero domain vector at zero total", errors[0])

    def test_different_zero_total_vectors_are_allowed(self) -> None:
        self.assertEqual(self.check_rows([
            (VALIDATE.LEADERBOARD_ORDER[0], "run2", "XELEC-06", ("50.000000", "0.000000", "", "", "", "")),
            (VALIDATE.LEADERBOARD_ORDER[0], "run3", "XELEC-06", ("60.000000", "0.000000", "", "", "", "")),
        ]), [])

    def test_all_empty_and_all_zero_vectors_are_allowed(self) -> None:
        for vector in (("",) * 6, ("0.000000",) * 6, ("0.000000", "", "0.000000", "", "", "")):
            with self.subTest(vector=vector):
                self.assertEqual(self.check_rows([
                    (VALIDATE.LEADERBOARD_ORDER[0], repeat, "XELEC-06", vector)
                    for repeat in VALIDATE.REPEAT_IDS
                ]), [])

    def test_distinct_experiments_and_tasks_are_not_combined(self) -> None:
        vector = ("50.000000", "0.000000", "", "", "", "")
        self.assertEqual(self.check_rows([
            (VALIDATE.LEADERBOARD_ORDER[0], "run2", "XELEC-06", vector),
            (VALIDATE.LEADERBOARD_ORDER[1], "run3", "XELEC-06", vector),
            (VALIDATE.LEADERBOARD_ORDER[0], "run3", "XELEC-07", vector),
        ]), [])

    def test_full_mcp_copy_is_checked_separately(self) -> None:
        vector = ("50.000000", "0.000000", "", "", "", "")
        self.assertEqual(self.check_rows([
            (VALIDATE.LEADERBOARD_ORDER[0], "run2", "XELEC-06", vector),
            (VALIDATE.ABLATION_ORDER[0], "run2", "XELEC-06", vector),
        ]), [])


class ResultReleaseTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.repo = Path(self.temporary.name) / "release"
        shutil.copytree(ROOT, self.repo, ignore=shutil.ignore_patterns(".git"))

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def errors(self) -> list[str]:
        return VALIDATE.validate_repository(self.repo)

    def update_score(
        self,
        run_id: str,
        task_id: str,
        *,
        repeat_id: str | None = None,
        **updates: str,
    ) -> None:
        directory = self.repo / "runs" / run_id
        if repeat_id is not None:
            directory /= repeat_id
        path = directory / "scores.csv"
        with path.open("r", encoding="utf-8", newline="") as handle:
            reader = csv.DictReader(handle)
            fieldnames = reader.fieldnames
            rows = list(reader)
        self.assertIsNotNone(fieldnames)
        matches = [row for row in rows if row["task_id"] == task_id]
        self.assertEqual(len(matches), 1)
        matches[0].update(updates)
        with path.open("w", encoding="utf-8", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=fieldnames)
            writer.writeheader()
            writer.writerows(rows)

    def test_complete_release(self) -> None:
        self.assertEqual(self.errors(), [])

    def test_complete_experiments_share_identity_and_repeat_layout(self) -> None:
        complete = [name for name, config in VALIDATE.RUNS.items()
                    if config["taskset_id"] == VALIDATE.COMPLETE_TASKSET]
        self.assertEqual(len(complete), 6)
        self.assertEqual(len(VALIDATE.RUNS), 9)
        for name in complete:
            with self.subTest(experiment=name):
                directory = self.repo / "runs" / name
                parent = json.loads((directory / "run.json").read_text(encoding="utf-8"))
                self.assertEqual(parent["schema_version"], "1.0")
                self.assertIsNone(parent["condition"])
                self.assertEqual(parent["repeat_ids"], list(VALIDATE.REPEAT_IDS))
                for repeat_id in VALIDATE.REPEAT_IDS:
                    repeat = json.loads((directory / repeat_id / "run.json").read_text(encoding="utf-8"))
                    self.assertEqual(repeat["parent_run_id"], name)
                    self.assertEqual(repeat["run_id"], f"{name}-{repeat_id}")
                    self.assertEqual(repeat["model"], parent["model"])

    def test_incomplete_run_metadata_is_rejected(self) -> None:
        name = VALIDATE.LEADERBOARD_ORDER[-1]
        path = self.repo / "runs" / name / "run1" / "run.json"
        metadata = json.loads(path.read_text(encoding="utf-8"))
        metadata["completed_task_count"] = 35
        path.write_text(json.dumps(metadata), encoding="utf-8")
        self.assertTrue(any("fields differ" in error for error in self.errors()))

    def test_repository_rejects_repeated_zero_total_domains(self) -> None:
        for parent_id in VALIDATE.RUNS:
            if parent_id == VALIDATE.ABLATION_ORDER[0]:
                continue
            directory = self.repo / "runs" / parent_id
            with (directory / "run2" / "scores.csv").open(encoding="utf-8", newline="") as handle:
                second = {row["task_id"]: row for row in csv.DictReader(handle)}
            with (directory / "run3" / "scores.csv").open(encoding="utf-8", newline="") as handle:
                third = list(csv.DictReader(handle))
            for row in third:
                earlier = second[row["task_id"]]
                if row["total"] != "0.000000" or earlier["total"] != "0.000000":
                    continue
                if not any(earlier[d] and Decimal(earlier[d]) > 0 for d in VALIDATE.DOMAIN_FIELDS):
                    continue
                if row["native_executable"] != "true":
                    continue
                self.update_score(parent_id, row["task_id"], repeat_id="run3",
                                  **{d: earlier[d] for d in VALIDATE.DOMAIN_FIELDS})
                self.assertTrue(any("duplicate nonzero domain vector at zero total" in e for e in self.errors()))
                return
        self.fail("no eligible zero-total pair to test")

    def find_missing_delivery(self) -> tuple[str, str, dict[str, str]]:
        for score_path in sorted((self.repo / "runs").glob("*/run*/scores.csv")):
            with score_path.open(encoding="utf-8", newline="") as handle:
                for row in csv.DictReader(handle):
                    if row["status"] == "MISSING_DELIVERY":
                        return score_path.parents[1].name, score_path.parent.name, row
        self.fail("release has no missing-delivery row to test")

    def test_valid_missing_delivery_is_accepted(self) -> None:
        _, _, row = self.find_missing_delivery()
        self.assertTrue(all(row[field] == "false" for field in VALIDATE.PREREQUISITE_FIELDS))
        self.assertEqual(row["protocol_zero"], "true")
        self.assertEqual(row["total"], "0.000000")
        self.assertTrue(all(row[field] == "" for field in VALIDATE.DOMAIN_FIELDS))
        self.assertEqual(self.errors(), [])

    def test_inconsistent_missing_delivery_is_rejected(self) -> None:
        parent_id, repeat_id, original = self.find_missing_delivery()
        for field, value in (
            ("delivered", "true"),
            ("native_executable", "true"),
            ("g_pass", "true"),
            ("protocol_zero", "false"),
            ("total", "1.000000"),
            *[(domain, "0.000000") for domain in VALIDATE.DOMAIN_FIELDS],
        ):
            with self.subTest(field=field):
                self.update_score(parent_id, original["task_id"], repeat_id=repeat_id, **{field: value})
                self.assertTrue(any("MISSING_DELIVERY requires" in error for error in self.errors()))
                self.update_score(parent_id, original["task_id"], repeat_id=repeat_id, **{field: original[field]})

    def test_legacy_nondelivery_status_is_not_rewritten(self) -> None:
        matches = []
        for score_path in (self.repo / "runs").glob("*/run1/scores.csv"):
            with score_path.open(encoding="utf-8", newline="") as handle:
                matches.extend(row for row in csv.DictReader(handle)
                               if row["delivered"] == "false" and row["status"] != "MISSING_DELIVERY")
        self.assertTrue(matches)
        self.assertEqual(self.errors(), [])

    def test_repository_rejects_equal_total_with_different_domains(self) -> None:
        self.update_score(
            "qwen3-8-max-claude-code-101",
            "XMED-05",
            repeat_id="run2",
            total="81.350905",
        )
        self.assertTrue(any(
            "duplicate positive total 81.350905" in error for error in self.errors()
        ))

    def test_missing_repeat_fails(self) -> None:
        path = self.repo / "runs" / "gpt-5-5-codex-101" / "run2"
        shutil.rmtree(path)
        errors = self.errors()
        self.assertTrue(any("missing public files" in error for error in errors))

    def test_parent_mean_drift_fails(self) -> None:
        run_id = "deepseek-v4-pro-claude-code-101"
        path = self.repo / "runs" / run_id / "scores.csv"
        with path.open("r", encoding="utf-8", newline="") as handle:
            first = next(csv.DictReader(handle))
        changed = str(Decimal(first["total"]) + Decimal("0.1"))
        self.update_score(run_id, first["task_id"], total=changed)
        self.assertTrue(
            any("is not the three-repeat mean" in error for error in self.errors())
        )

    def test_parent_prerequisite_count_fails(self) -> None:
        run_id = "opus-4-8-claude-code-101"
        path = self.repo / "runs" / run_id / "scores.csv"
        with path.open("r", encoding="utf-8", newline="") as handle:
            first = next(csv.DictReader(handle))
        changed = str((int(first["delivered_count"]) + 1) % 4)
        self.update_score(run_id, first["task_id"], delivered_count=changed)
        self.assertTrue(
            any("delivered_count must be" in error for error in self.errors())
        )

    def test_failed_repeat_requires_empty_domains(self) -> None:
        run_id = "opus-4-8-claude-code-no-simulation-10"
        repeat_id = "run2"
        repeat_path = self.repo / "runs" / run_id / repeat_id / "scores.csv"
        parent_path = self.repo / "runs" / run_id / "scores.csv"
        with repeat_path.open("r", encoding="utf-8", newline="") as handle:
            repeat_rows = list(csv.DictReader(handle))
        with parent_path.open("r", encoding="utf-8", newline="") as handle:
            parent_rows = {row["task_id"]: row for row in csv.DictReader(handle)}
        failed = next(
            row
            for row in repeat_rows
            if row["native_executable"] == "false"
            and any(parent_rows[row["task_id"]][field] for field in VALIDATE.DOMAIN_FIELDS)
        )
        domain = next(
            field
            for field in VALIDATE.DOMAIN_FIELDS
            if parent_rows[failed["task_id"]][field]
        )
        self.update_score(
            run_id, failed["task_id"], repeat_id=repeat_id, **{domain: "0.5"}
        )
        self.assertTrue(
            any(
                "failure requires empty domains" in error
                for error in self.errors()
            )
        )

    def test_full_mcp_repeat_correspondence_fails(self) -> None:
        run_id = "opus-4-8-claude-code-full-mcp-10"
        path = self.repo / "runs" / run_id / "run1" / "scores.csv"
        with path.open("r", encoding="utf-8", newline="") as handle:
            first = next(csv.DictReader(handle))
        changed = str(Decimal(first["A"]) - Decimal("0.001"))
        self.update_score(
            run_id, first["task_id"], repeat_id="run1", A=changed
        )
        self.assertTrue(
            any("Full MCP run1 row differs from Opus" in error for error in self.errors())
        )

    def test_repeat_identity_drift_fails(self) -> None:
        path = (
            self.repo
            / "runs"
            / "qwen3-8-max-claude-code-101"
            / "run3"
            / "run.json"
        )
        data = json.loads(path.read_text(encoding="utf-8"))
        data["repeat_id"] = "run2"
        path.write_text(json.dumps(data), encoding="utf-8")
        self.assertTrue(any("repeat_id must be" in error for error in self.errors()))

    def test_positive_total_requires_g_pass(self) -> None:
        run_id = "gpt-5-5-codex-101"
        repeat_id = "run1"
        path = self.repo / "runs" / run_id / repeat_id / "scores.csv"
        with path.open("r", encoding="utf-8", newline="") as handle:
            row = next(row for row in csv.DictReader(handle) if Decimal(row["total"]) > 0)
        self.update_score(
            run_id, row["task_id"], repeat_id=repeat_id, g_pass="false"
        )
        self.assertTrue(
            any("positive total requires g_pass=true" in error for error in self.errors())
        )

    def test_executable_g_failure_status_is_fixed(self) -> None:
        run_id = "deepseek-v4-pro-claude-code-101"
        repeat_id = "run1"
        path = self.repo / "runs" / run_id / repeat_id / "scores.csv"
        with path.open("r", encoding="utf-8", newline="") as handle:
            row = next(
                row
                for row in csv.DictReader(handle)
                if row["native_executable"] == "true" and row["g_pass"] == "false"
            )
        self.update_score(
            run_id,
            row["task_id"],
            repeat_id=repeat_id,
            status="INELIGIBLE",
            protocol_zero="false",
        )
        self.assertTrue(
            any(
                "executable G failure requires a protocol-zero SCORED row" in error
                for error in self.errors()
            )
        )

    def test_fixed_six_decimal_format(self) -> None:
        for text in ("0.1", "0.1234567"):
            with self.subTest(text=text):
                errors: list[str] = []
                self.assertIsNotNone(
                    VALIDATE._decimal_six(text, "value", errors)
                )
                self.assertIn(
                    "value must use fixed six-decimal format", errors
                )

        errors = []
        self.assertEqual(
            VALIDATE._decimal_six("0.123456", "value", errors),
            Decimal("0.123456"),
        )
        self.assertEqual(errors, [])

    def test_parent_mean_rounds_half_up_to_six_decimals(self) -> None:
        self.assertEqual(
            VALIDATE._mean_six(
                [Decimal("1.000000"), Decimal("1.000000"), Decimal("1.000002")]
            ),
            Decimal("1.000001"),
        )
        self.assertEqual(
            VALIDATE._round_six(Decimal("1.2345675")),
            Decimal("1.234568"),
        )

    def test_published_parent_prerequisite_totals_are_locked(self) -> None:
        run_id = "gpt-5-5-codex-101"
        original = VALIDATE.RUNS[run_id]["prerequisite_totals"]
        VALIDATE.RUNS[run_id]["prerequisite_totals"] = (
            original[0] - 1,
            original[1],
            original[2],
        )
        try:
            self.assertTrue(
                any(
                    "published prerequisite totals differ" in error
                    for error in self.errors()
                )
            )
        finally:
            VALIDATE.RUNS[run_id]["prerequisite_totals"] = original

    def test_unknown_status_fails(self) -> None:
        run_id = "gpt-5-5-codex-101"
        path = self.repo / "runs" / run_id / "run1" / "scores.csv"
        with path.open("r", encoding="utf-8", newline="") as handle:
            first = next(csv.DictReader(handle))
        self.update_score(
            run_id, first["task_id"], repeat_id="run1", status="NOT_A_STATUS"
        )
        self.assertTrue(any("unknown status" in error for error in self.errors()))

    def test_unexpected_cache_fails(self) -> None:
        path = self.repo / "tools" / "__pycache__"
        path.mkdir()
        (path / "generated.pyc").write_bytes(b"test")
        self.assertTrue(self.errors())

    def test_private_brand_term_fails(self) -> None:
        old_name = "".join(("simu", "linkbench"))
        path = self.repo / "README.md"
        path.write_text(
            path.read_text(encoding="utf-8") + f"\n{old_name}\n",
            encoding="utf-8",
        )
        self.assertTrue(self.errors())


if __name__ == "__main__":
    unittest.main()
