# SimuVerity Results

This repository publishes score tables for SimuVerity. It contains six
complete 101-task Agent experiments and a three-condition, ten-task MCP
ablation, each with three individual repeats. The `SimuVerity-benchmark/`
directory of the same repository contains the task definitions and evaluators.

Only result tables and their machine-checkable metadata are included here.
Agent submissions, simulation traces, evaluator evidence, and reference models
are not part of this repository.

## Complete 101-task experiments

The score columns below are the arithmetic means across three repeats. The
prerequisite columns count task-repeat pairs, so their denominator is 303 per
experiment.

| Model | Harness | Score sum | Mean | Delivered | Native executable | G pass |
|---|---|---:|---:|---:|---:|---:|
| Claude Opus 4.8 | Claude Code | 4328.360891 | 42.855058 | 287 | 262 | 233 |
| GPT-5.5 | Codex | 4214.213333 | 41.724884 | 299 | 287 | 229 |
| DeepSeek-V4-Pro | Claude Code | 2868.302156 | 28.399031 | 294 | 267 | 186 |
| Qwen3.8-Max | Claude Code | 2526.490388 | 25.014756 | 272 | 245 | 163 |
| GLM-5.3-Flash | Claude Code | 502.690996 | 4.977139 | 291 | 146 | 40 |
| Qwen3.8-27B-FP8 | Claude Code | 161.892651 | 1.602898 | 92 | 41 | 19 |

The root `leaderboard.csv` compares only these six experiments because they
use the same 101-task set. Across them, 1,535 of 1,818 task-repeat pairs
delivered a candidate, 1,248 were natively executable, and 870 passed G.

## MCP ablation

The ten-task ablation uses Claude Opus 4.8 with Claude Code under three tool
conditions:

- `full_mcp`: the complete persistent official MATLAB/Simulink MCP interface,
  including simulation execution;
- `no_simulation`: modeling and static operations remain available, while
  simulation execution is disabled;
- `batch_only`: no persistent official MCP interface; file operations and
  stateless MATLAB batch execution remain available.

The condition-level parent aggregates are in
`ablations/mcp-10/summary.csv`. The per-task parent means and score differences
are in `ablations/mcp-10/comparison.csv`. These ten-task results are not mixed
into the 101-task leaderboard.

## Format

Every experiment directory under `runs/` contains parent aggregate
`run.json`, `scores.csv`, and `summary.json` files, plus direct `run1`, `run2`,
and `run3` subdirectories. Each subdirectory is one individual repeat and uses
the 13-column task-result format.

The parent task table contains each task's three-repeat mean for `total` and
the applicable A/Q/M/C/R/D dimensions. It also records how many of the three
repeats passed each prerequisite layer. Parent summary counts cover all three
sets of task rows; parent score sum and mean cover the averaged task table.
All published score values use fixed six-decimal reporting precision; parent
values are rounded after the three-repeat arithmetic aggregation.
Totals and populated dimension scores both use a 0–100 scale. Evaluator formulas
use dimension utilities on a 0–1 scale, obtained by dividing each dimension score
by 100; only applicable dimensions participate.

The prerequisite layers are `delivered`, `native_executable`, and `g_pass`.
They cannot be inferred from status or score: in particular, a candidate can
pass G and still receive total zero. To reproduce a repeat's post-G dimension
means, keep only its `g_pass=true` rows; for each dimension, average the non-empty
values directly. To reproduce end-to-end dimension means, count a dimension value as
zero whenever `g_pass=false`: the parent task table keeps the diagnostic dimension
values of natively executable G failures, so averaging its columns directly
does not give the published end-to-end rows.

The complete field and aggregation contract is documented in
`schemas/results-format.md`.

## Validate

Python 3.11 or newer is sufficient; no third-party package is required.

```shell
python -B tools/validate_results.py
python -B -m unittest discover -s tests -v
```

The validator checks all nine experiment layouts, 27 individual repeats,
1,908 individual task rows, and 636 parent task rows. It independently derives
the parent means and counts, checks task-set and prerequisite semantics, locks
the published experiment-level targets, and verifies the Full MCP
correspondence with the matching Opus repeat. Positive-total uniqueness and
same-task zero-total dimension-vector uniqueness are checked across individual
repeats, with the exceptions defined in the format contract.

## License

The repository is available under the Apache License, Version 2.0. See
`LICENSE` and `NOTICE`.
