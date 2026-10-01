#!/usr/bin/env python3
"""Python implementation of F90-XROBO-02 score semantics."""
from __future__ import annotations
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[2]))
from formal90_scoring_core import base_receipt,clip,load_evidence,parser,write_receipt
TASK_ID="F90-XROBO-02"
def q(x,good,bad):return clip((bad-float(x))/(bad-good))
def score(e):
    f=e["facts"];rows=f.get("scenario_rows",[]);audit=f.get("static_audit",{});gate=bool(f.get("score_inputs_valid",False))
    if not gate or not rows:return {"A":0,"Q":0,"M":0,"R":0,"D":0},0,list(f.get("gate_reasons",[])),{}
    n=rows[0]
    A=.55*q(n["q_error_max"],.035,.16)+.30*q(n["position_error_max"],.008,.065)+.15*q(n["orientation_error_max"],.025,.20)
    Q=.40*q(n["sync_peak"],.025,.16)+.30*q(n["final_speed_max"],.015,.22)+.30*q(n["torque_ratio_max"],1.0,1.08)
    static=sum(float(audit[k]) for k in ("joint_count_14","all_input_torque","all_computed_motion","all_position_sensed","all_velocity_sensed","all_torque_ports_connected","controller_present","no_prescribed_trajectory_blocks"))/8
    consistency=min(r["pose_consistency_score"] for r in rows);causal=min(r["target_motion_score"] for r in rows)
    M=.70*static+.15*consistency+.15*causal
    operating=[.45*q(r["q_error_max"],.055,.24)+.20*q(r["position_error_max"],.012,.10)+.15*q(r["sync_peak"],.035,.22)+.10*q(r["final_speed_max"],.025,.30)+.10*q(r["torque_ratio_max"],1.0,1.08) for r in rows]
    dynamic=[.45*q(r["post_event_q_error_max"],.06,.25)+.25*q(r["post_event_speed_max"],.025,.32)+.15*q(r["event_peak_speed"],1.8,5.5)+.15*r["event_response_score"] for r in rows[1:]]
    R=min(operating);D=min(dynamic);groups={"A":clip(A),"Q":clip(Q),"M":clip(M),"R":clip(R),"D":clip(D)}
    w=e["group_weights"];value=100*sum(w[k]*groups[k] for k in ("A","Q","M","R","D"))
    return groups,value,[],{"operating":operating,"dynamic":dynamic}
def main():
    a=parser(TASK_ID).parse_args();e=load_evidence(a.evidence,TASK_ID);g,v,reasons,d=score(e)
    r=base_receipt(a.evidence,e,g,v,policy_id="simuverity-101-v1:f90-xrobo-02:scoring",gate_reasons=reasons);r.update({"scenarios":e["facts"].get("scenario_rows",[]),"static_audit":e["facts"].get("static_audit",{}),"utility_metrics":d});write_receipt(a.output,r)
if __name__=="__main__":main()
