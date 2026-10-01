# SimuVerity result format

This document defines version `1.0` of the result-table contract. JSON objects
use exactly the fields listed below. Paths are repository-relative file names;
absolute paths and parent traversal are invalid.

## Run layout

Each directory under `runs/` is one three-repeat experiment. Its top-level
files are the arithmetic aggregate, and its `run1`, `run2`, and `run3`
subdirectories contain the three individual repeats:

```text
runs/<experiment-id>/
  run.json
  scores.csv
  summary.json
  run1/{run.json,scores.csv,summary.json}
  run2/{run.json,scores.csv,summary.json}
  run3/{run.json,scores.csv,summary.json}
```

The parent `run.json` has the common identity and file fields plus:

- `aggregation`: always `arithmetic_mean`;
- `repeat_count`: always `3`;
- `repeat_ids`: always `["run1", "run2", "run3"]`.

Each repeat `run.json` has the common identity and file fields plus
`parent_run_id` and `repeat_id`. Its `run_id` is
`<parent_run_id>-<repeat_id>`. The common fields are:

```text
schema_version, run_id, benchmark_release, taskset_id, model, harness,
condition, task_count, scores_file, summary_file
```

The contract version is `1.0`, the benchmark release is
`simuverity-101-v1`, and both file fields are local file names.

## Individual-repeat files

An individual `scores.csv` has the fixed header:

```text
task_id,status,protocol_zero,total,A,Q,M,C,R,D,delivered,native_executable,g_pass
```

Allowed statuses are `SCORED`, `INVALID_CANDIDATE`, `MISSING_DELIVERY`,
`TIMEOUT`, `PROTOCOL_ZERO`, and `INELIGIBLE`. `protocol_zero` and the three
prerequisite fields are strict lowercase `true` or `false` values. Every
`total` and populated A/Q/M/C/R/D cell is a fixed-point decimal string with
exactly six digits after the decimal point. Values use decimal
`ROUND_HALF_UP`; an empty non-applicable dimension remains empty. Totals range
from 0 through 100, and populated dimensions also range from 0 through 100.
To express a reported dimension score in the evaluator's utility scale, divide
it by 100. The weighted geometric formula uses applicable dimensions as
`G * 100 * product((dimension / 100) ** weight)`; G is the qualification gate
and does not receive a weight.

Positive six-decimal totals must be distinct across individual-repeat rows
whenever a match includes `run2` or `run3`, even if dimension values differ.
Run1-only matches, zero totals, and the checked Full MCP/Opus correspondence
are excluded. This rule does not impose a minimum gap between otherwise
distinct totals, and it does not apply to parent aggregates.

Within one experiment and task, zero-total rows containing nonzero dimensions
must not repeat the complete dimension vector when a match includes `run2` or
`run3`. All-empty and all-zero vectors remain allowed, as does the checked
Full MCP/Opus correspondence. This check does not compare different tasks or
experiments and does not apply to parent aggregates.

The prerequisite fields mean:

- `delivered`: a formal candidate model was delivered;
- `native_executable`: the candidate completed the required native execution
  path and became scorable;
- `g_pass`: the candidate passed engineering qualification gate G.

They always satisfy `g_pass <= native_executable <= delivered`. A positive
total requires `g_pass=true`. If delivery or native execution fails, all
applicable dimension cells are empty. A G-passing zero retains all applicable
dimensions and has at least one applicable dimension equal to zero. A natively
executable G failure uses `status=SCORED` and `protocol_zero=true`; a G pass
uses `status=SCORED` and `protocol_zero=false`.

`MISSING_DELIVERY` requires all three prerequisites to be `false`,
`protocol_zero=true`, total zero, and all dimension cells empty. This is a
one-way rule: retained terminal statuses do not change solely because
`delivered=false`.

The individual `summary.json` repeats the run identity, includes
`parent_run_id` and `repeat_id`, and records:

```text
scored_count, protocol_zero_count,
score_sum, score_mean,
delivered_count, native_executable_count, g_pass_count
```

Counts are integers derived from that repeat's task rows. `score_sum` is the
sum of the stored six-decimal task totals, rounded and displayed with six
decimal places. `score_mean` is that stored sum divided by `task_count`, then
rounded and displayed in the same form.

## Parent aggregate files

The parent `scores.csv` has the fixed header:

```text
task_id,total,A,Q,M,C,R,D,delivered_count,native_executable_count,g_pass_count
```

For each task, `total` is the Decimal arithmetic mean of its three stored
six-decimal repeat totals, rounded with `ROUND_HALF_UP` and displayed with six
decimal places. Each applicable dimension is calculated and displayed in the same
way; an empty applicable value in an unsuccessful repeat contributes zero,
while a dimension that does not apply remains empty. Each prerequisite count is
the number of `true` values among the three repeats and is therefore an integer
from 0 through 3.

The parent `summary.json` adds `repeat_count` and `result_count` to the common
summary fields. `result_count` is `task_count * repeat_count`. Status,
protocol-zero and prerequisite counts are totals across all
individual-repeat rows. Parent `score_sum` and `score_mean` are derived from
the parent task table, not from a fourth run.

## Task sets and aggregate tables

Task-set files contain `task_id,collection`. The complete task set has 101 rows;
the MCP ablation task set has ten rows and is a subset in the same published
order.

`leaderboard.csv` contains only the six complete parent experiments. The MCP
condition summary contains the three ablation parents. Their repeat and result
counts and all aggregate values must match the corresponding parent summaries.
The MCP task comparison contains the three parent totals and the two differences
from Full MCP; statuses remain properties of individual repeats. Every aggregate
score, mean, and difference in these tables uses the same fixed six-decimal
format and `ROUND_HALF_UP` rule.
