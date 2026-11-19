# SimuVerity result format

This document describes experiment metadata and result summaries.
Summary objects use schema version `1.0`.

## Layout

```text
runs/<experiment-id>/
  run.json
  summary.json
  run1/{run.json,summary.json}
  run2/{run.json,summary.json}
  run3/{run.json,summary.json}
```

## Metadata

Common fields are `schema_version`, `run_id`, `benchmark_release`,
`taskset_id`, `model`, `harness`, `condition`, `task_count`,
and `summary_file`. The summary filename is `summary.json`.
Parent metadata also specifies `aggregation: arithmetic_mean`,
`repeat_count: 3` and `repeat_ids: [run1,run2,run3]`.
Repeat metadata instead specifies `parent_run_id` and `repeat_id`.

## Summary values

Each summary repeats the experiment identity and reports `scored_count`,
`protocol_zero_count`, `score_sum`, `score_mean`, `delivered_count`,
`native_executable_count` and `g_pass_count`. Parent summaries additionally
report `repeat_count` and `result_count`; repeat summaries report
`parent_run_id` and `repeat_id`.

Scores use six decimal places and a 0-100 scale. Prerequisites obey
`g_pass_count <= native_executable_count <= delivered_count`.
Status-derived `scored_count` and `protocol_zero_count` describe separate
properties and may overlap.

A repeat's score sum is the sum of its task totals; its mean is the sum
divided by the task count, rounded to six decimal places with ROUND_HALF_UP.
A parent score sum is the sum of three-repeat task means, each rounded to
six decimal places before summation. The parent mean is that sum divided by
the task count. Parent counts sum the corresponding counts of all repeats.
Parent `result_count` equals `task_count * repeat_count`.

Because per-task rounding precedes the parent summation, a parent score
sum can differ slightly from the mean of the repeat sums. The validator
uses the corresponding rounding-error bound, retaining the published values.

## Aggregate tables and task membership

`leaderboard.csv` lists six complete 101-task experiments.
`ablations/mcp-10/summary.csv` lists the three ten-task MCP conditions and
their overall mean-score differences from Full MCP. These rows match the
corresponding parent summaries.

`tasksets/` lists benchmark membership using `task_id,collection`.
