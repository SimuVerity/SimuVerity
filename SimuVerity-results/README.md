# SimuVerity Results

This directory provides experimental results for six agent systems evaluated
on 101 tasks and a three-condition, ten-task MCP ablation. Each experiment
has three repeats.

## Complete 101-task experiments

The score columns are averages across three repeats. Prerequisite counts
cover 303 task-repeat pairs per system.

| Model | Harness | Score sum | Mean | Delivered | Native executable | G pass |
|---|---|---:|---:|---:|---:|---:|
| Claude Opus 4.8 | Claude Code | 4328.360891 | 42.855058 | 287 | 262 | 233 |
| GPT-5.5 | Codex | 4214.213333 | 41.724884 | 299 | 287 | 229 |
| DeepSeek-V4-Pro | Claude Code | 2868.302156 | 28.399031 | 294 | 267 | 186 |
| Qwen3.8-Max | Claude Code | 2526.490388 | 25.014756 | 272 | 245 | 163 |
| GLM-5.3-Flash | Claude Code | 502.690996 | 4.977139 | 291 | 146 | 40 |
| Qwen3.8-27B-FP8 | Claude Code | 161.892651 | 1.602898 | 92 | 41 | 19 |

`leaderboard.csv` contains the same six system-level summaries.

## MCP ablation

`ablations/mcp-10/summary.csv` reports the overall results under Full MCP,
No-Simulation MCP and Batch-only conditions. These ten-task experiments are
reported separately from the 101-task leaderboard.

## Files

- `runs/<experiment>/summary.json`: the three-repeat aggregate.
- `runs/<experiment>/run1/summary.json`, `run2/summary.json`, and
  `run3/summary.json`: overall statistics for each repeat.
- `run.json` beside each summary: experiment identity and aggregation metadata.
- `tasksets/`: task membership lists.
- `schemas/results-format.md`: aggregate fields and rounding conventions.

## Validate

Python 3.11 or newer is sufficient; no third-party package is required.

```shell
python -B tools/validate_results.py
python -B -m unittest discover -s tests -v
```

Validation checks all nine experiments and 27 repeats, matches aggregate
tables to their summaries, and checks prerequisite counts, score arithmetic
and metadata consistency.

## License

Apache License, Version 2.0. See `LICENSE` and `NOTICE`.
