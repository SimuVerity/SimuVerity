# SimuVerity Benchmark

SimuVerity is a 101-task benchmark for agents that build MATLAB and Simulink systems from public engineering requirements. This repository contains the task contracts, official scenarios, reference assets or import recipes, evidence extractors, and current offline scorers. Published model results are in the `SimuVerity-results/` directory of the same repository.

## Repository contents

Each `tasks/<task_id>/` directory contains:

- `public_spec.json`: the English prompt sent to the Agent;
- `official_scenarios.json`: evaluator-owned scenarios;
- `system_profile.json`: public, machine-checkable system metadata;
- `extractor/`: the public evidence-extraction entry point and dependency list;
- `scorer.py` and `scorer/manifest.json`: the current offline scorer;
- `reference/`: either redistributable reference files or a local import recipe;
- `task.json`: the bindings between those assets.

The system profile is public metadata for understanding and validating the task package. It is not sent to the Agent and is not read by simulation or scoring.

The release is `simuverity-101-v1`: 101 tasks across ten domains: XELEC (9), XAERO (10), XAUTO (11), XBATT (10), XCOMM (9), XFLUID (11), XMECH (11), XMED (9), XROBO (10), and XTHERM (11). Sixty-eight references are bundled and 33 are materialized from public MATLAB examples available in the user's own installation. Ten of the bundled references (XAERO-01, XAUTO-01, XAUTO-02, XBATT-01, XBATT-02, XCOMM-01, XFLUID-01, XMECH-01, XMED-01, and XTHERM-01) are original SimuVerity models, marked by `reference.source_kind = "expert_built"` in their `task.json`; the other 58 are redistributed third-party projects and research artifacts.

## Download and install

All files, including large model files, are stored directly in this
repository, so no Git LFS setup is required.

Static release and system-profile validation need only Python 3.11 or newer and the standard library:

```text
python -B tools/validate_system_profiles.py
python -B tools/validate_release.py
```

Install the Python runtime used by generation, extraction orchestration, and offline scoring with:

```text
python -m pip install -e .
```

The main dependencies are NumPy 1.26 or newer and h5py 3.10 or newer. Reference workflows can use `python -m pip install -e ".[reference]"`; this installs SciPy plus the public simulator dependencies CasADi, pandas, and Matplotlib. Tests can use `python -m pip install -e ".[test]"`.

Candidate evaluation requires MATLAB R2025a, Simulink, and the products used by the submitted model and the selected task's evaluator. It does not require a local-importer reference to be downloaded or prepared. Preparing or replaying a local-importer reference additionally requires the corresponding public MathWorks example to be available in that MATLAB installation.

## Inspect tasks

```text
python -m simuverity tasks list
python -m simuverity tasks show XELEC-14
python -m simuverity doctor
```

`doctor` reports the local Python and MATLAB capabilities without modifying task assets.

## Reference assets

Validate a bundled reference or prepare a locally imported reference with:

```text
simuverity assets prepare XELEC-14
simuverity assets prepare XAUTO-09
simuverity assets prepare --all
```

Use `--dry-run` to inspect an import plan without starting MATLAB. Local assets are stored under `%LOCALAPPDATA%\SimuVerity\assets\simuverity-101-v1` unless `--asset-root` is supplied.

## Generation and evaluation

Generation and evaluation are separate commands so one evaluation failure cannot stop later Agent runs:

```text
simuverity generate XELEC-14 --agent codex --model <model> --mcp-config <mcp.json>
simuverity evaluate XELEC-14 --submission <submission-directory>
```

`simuverity run` is the one-task convenience command. Optional `--generation-run-id` and `--scoring-run-id` values name fresh run directories; otherwise SimuVerity creates them. Generation receives only the prompt and the configured MATLAB/Simulink tool interface. Reference assets, scenarios, scorers, system profiles, and prior results are evaluator-owned.

For the isolation conditions used in the runs, outbound network access of the agent process and the MATLAB session was blocked at the operating-system level on the evaluation server, and the MATLAB example directories were removed. The remaining isolation measures are implemented in this repository.

Scoring a submitted Agent model does not require `simuverity assets prepare`, including for local-importer tasks. Run the asset command only when you want to inspect, validate, or replay the reference model.

Evaluation creates a read-only submission copy, a separate writable runtime copy, isolated MATLAB preferences and cache directories, and an `evidence_bundle` containing the extracted JSON, official scenario copy, and any declared artifacts or sidecars. Offline rescoring reads that bundle and does not start MATLAB:

```text
simuverity rescore XELEC-14 --evidence-bundle <evidence_manifest.json>
```

Every score result includes the total, the G gate outcome, the applicable A/Q/M/C/R/D dimensions, metric values, scenario results, and failure reasons.

## Tests

```text
python -B -m pytest -q
```

The static validators intentionally use no third-party schema package. They check the release structure directly with Python's standard library.

## License

First-party code is licensed under Apache-2.0. Third-party reference assets retain their upstream licenses and notices under `licenses/third_party/` and within the relevant task directories. Author names and contact addresses that appear inside bundled third-party reference files (model metadata, READMEs, and source headers) belong to the upstream projects and are retained as their licenses require; they do not identify the SimuVerity authors.
