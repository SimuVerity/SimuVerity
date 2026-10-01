from __future__ import annotations

import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

from validate_release import (  # noqa: E402
    _direct_policy_id_values,
    _evaluator_version_match,
    _json_identity_fields,
    _scan_bytes,
    _scan_first_party_identity_terms,
    _scan_matlab_error_identifiers,
)


class ReleaseScanTests(unittest.TestCase):
    def test_user_profile_path_is_rejected_without_a_specific_username(self) -> None:
        failures: list[str] = []
        value = b"C:" + b"\\Users\\Example\\project\\file.json"
        _scan_bytes(value, failures, "probe.txt")
        self.assertTrue(failures)

    def test_private_workspace_path_is_rejected_without_a_specific_drive(self) -> None:
        failures: list[str] = []
        value = b"E:" + b"\\Claude_code\\private\\asset.json"
        _scan_bytes(value, failures, "probe.txt")
        self.assertTrue(failures)

    def test_first_party_identity_term_is_rejected(self) -> None:
        failures: list[str] = []
        value = b"SHA" + b"-256: " + b"0" * 64
        _scan_first_party_identity_terms(value, failures, "notice.md")
        self.assertTrue(failures)

    def test_raw_credential_and_path_checks_remain_active(self) -> None:
        failures: list[str] = []
        value = b"sk-" + b"a" * 40 + b" C:" + b"\\Users\\Example\\private"
        _scan_bytes(value, failures, "probe.txt")
        self.assertTrue(any("credential-like" in e for e in failures))
        self.assertTrue(any("private workflow" in e for e in failures))

    def test_legacy_matlab_error_identifier_is_rejected(self) -> None:
        failures: list[str] = []
        _scan_matlab_error_identifiers(
            b'error("F90:Probe:Failure", "probe");', failures, "probe.m"
        )
        self.assertTrue(failures)

    def test_simuverity_and_matlab_error_identifiers_are_allowed(self) -> None:
        failures: list[str] = []
        value = (
            b'error("SimuVerity:F90:Probe:Failure", "probe");\n'
            b'warning("off", "MATLAB:dispatcher:UnresolvedFunctionHandle");'
        )
        _scan_matlab_error_identifiers(value, failures, "probe.m")
        self.assertFalse(failures)

    def test_internal_evaluator_revision_path_is_rejected(self) -> None:
        self.assertEqual(
            _evaluator_version_match(
                Path("tasks/XELEC-14/scorer/scorer_v4.py"), b""
            ),
            "path",
        )

    def test_internal_evaluator_revision_symbol_is_rejected(self) -> None:
        self.assertEqual(
            _evaluator_version_match(
                Path("tasks/XELEC-14/scorer.py"), b"def _apply_v4(value): return value"
            ),
            "content",
        )

    def test_internal_evaluator_revision_embedded_in_runtime_identity_is_rejected(self) -> None:
        self.assertEqual(
            _evaluator_version_match(
                Path("tasks/XAUTO-11/extractor/run.m"),
                b'scoringRunId = "f90_xauto11_v2_manual";',
            ),
            "content",
        )

    def test_public_v1_and_matlab_file_format_are_allowed(self) -> None:
        payload = (
            b"simuverity-101-v1 simuverity.evidence-bundle.v1 "
            b"save(path, '-v7.3'); v0 = 0; v1 = 1; v2 = 2;"
        )
        self.assertIsNone(
            _evaluator_version_match(Path("src/simuverity/evaluation/io.py"), payload)
        )

    def test_fixed_d_model_block_identity_is_allowed(self) -> None:
        self.assertIsNone(
            _evaluator_version_match(
                Path("tasks/XELEC-14/official_scenarios.json"),
                b'{"path": "model/__v4_truth_voltage"}',
            )
        )

    def test_nested_policy_id_values_are_discovered(self) -> None:
        payload = {
            "contract": {"score_policy": {"policy_id": "old-policy"}},
            "scenarios": [{"id": "nominal"}],
        }
        self.assertEqual(
            list(_direct_policy_id_values(payload)),
            [("contract.score_policy.policy_id", "old-policy")],
        )


if __name__ == "__main__":
    unittest.main()
