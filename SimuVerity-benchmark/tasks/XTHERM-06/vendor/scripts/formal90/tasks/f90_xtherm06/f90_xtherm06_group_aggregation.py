#!/usr/bin/env python3
"""XTHERM-06 strict geometric scorer with copied-command check inside M."""
from __future__ import annotations
import argparse,json,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[2]))
from geometric_scoring_adapter import adapt_source_result,load_current
SOURCE=Path(__file__).with_name("f90_xtherm06_scoring_core.py")
METRICS=load_current(SOURCE, "xtherm06_current_source")
WEIGHTS={"A":.15,"Q":.15,"M":.30,"R":.20,"D":.20}
MAPPING={"copied speed command":"M (20% authenticity constraint; pass leaves M unchanged)"}
def _migrate(groups,source):
 copied=bool(source.get("diagnostics",{}).get("shortcut_checks",{}).get("copied_speed_command_detected"));groups=dict(groups);groups["M"]*=.8+.2*float(not copied);return groups
def score_evidence(e):
 return adapt_source_result(METRICS.score_evidence(e),schema="simuverity.f90-xtherm06-score.v1",policy_id="simuverity-101-v1:f90-xtherm-06:scoring",weights=WEIGHTS,primary_total_key="score",cap_conditions_already_represented_in_groups=MAPPING,transform_groups=_migrate)
def main():
 p=argparse.ArgumentParser();p.add_argument("evidence",type=Path);p.add_argument("--out",type=Path);a=p.parse_args();r=score_evidence(json.loads(a.evidence.read_text(encoding="utf-8-sig")));t=json.dumps(r,indent=2,ensure_ascii=False,allow_nan=False)+"\n";(a.out.write_text(t,encoding="utf-8") if a.out else print(t,end=""))
if __name__=="__main__":main()
