#!/usr/bin/env python3
"""XROBO-10 source groups with strict geometric, no post-total caps."""
from __future__ import annotations
import argparse,json,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[2]))
from geometric_scoring_adapter import adapt_source_result,load_current
SOURCE=Path(__file__).with_name("f90_xrobo10_scoring_core.py")
METRICS=load_current(SOURCE, "xrobo10_current_source")
WEIGHTS={"A":.20,"Q":.20,"M":.25,"R":.20,"D":.15}
MAPPING={"two workcells":"A/M","core feedback path":"M","actor transfer":"A/M/R/D","completed products":"A/R/D","shuttle coverage":"A/D","ball-offset response":"M/R/D","actuator torque":"Q/M"}
def score_evidence(e):
 return adapt_source_result(METRICS.score_evidence(e),schema="simuverity.f90-xrobo10-score.v1",policy_id="simuverity-101-v1:f90-xrobo-10:scoring",weights=WEIGHTS,primary_total_key="raw_score",cap_conditions_already_represented_in_groups=MAPPING)
def main():
 p=argparse.ArgumentParser();p.add_argument("evidence",type=Path);p.add_argument("--out",type=Path);a=p.parse_args();r=score_evidence(json.loads(a.evidence.read_text(encoding="utf-8-sig")));t=json.dumps(r,indent=2,ensure_ascii=False,allow_nan=False)+"\n";(a.out.write_text(t,encoding="utf-8") if a.out else print(t,end=""))
if __name__=="__main__":main()
