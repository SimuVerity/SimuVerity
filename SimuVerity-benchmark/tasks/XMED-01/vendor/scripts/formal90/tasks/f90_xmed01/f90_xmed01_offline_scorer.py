#!/usr/bin/env python3
"""Post-lock Python reproduction of XP9 XMED01 score semantics."""
from __future__ import annotations
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[2]))
from formal90_offline_common import base_receipt,group,load_evidence,parser,tail,total,utility,weights,write_receipt
TASK_ID="F90-XMED-01"
def ceiling(pressure):return utility(max(float(pressure)-35,0),[0,.05,.15,.30,.75,1.0],[1,1,.90,.55,.10,0])
def score(e):
    f=e["facts"];rows=f.get("scenario_rows",[]);causal=float(f.get("causal_error",1e9));fit=f.get("causal_fit",{});leak=f.get("leak_evidence",{});airway=f.get("airway_evidence",{});margin=f.get("aligned_actuator_margin");gate=bool(f.get("score_inputs_valid",False));causal_cap=None
    if rows:
        n=rows[0]
        A=group([utility(n["plateau_error"],[0,.35,.75,1.5,4,8],[1,1,.92,.72,.25,0]),
                 utility(n["peep_error"],[0,.2,.5,1,2.5,5],[1,1,.93,.75,.30,0])],[.65,.35])
        if not n.get("breath_cycle_present",False):A=0
        Q=group([utility(n["tidal_volume_ratio_error"],[0,.04,.10,.22,.45,.90],[1,1,.94,.72,.25,0]),
                 utility(n["plateau_std"],[0,.25,.6,1.5,4],[1,1,.92,.65,0]),ceiling(n["max_pressure"]),
                 utility(max(r["negative_volume_ratio"] for r in rows),[0,.005,.015,.04,.10,.25],[1,.99,.94,.72,.25,0])],[.30,.18,.42,.10])
        physiology=group([utility(n["mass_residual"],[0,.015,.04,.10,.30],[1,1,.9,.55,0]),
                          utility(max(r["circuit_flow_residual"] for r in rows),[0,.003,.012,.04,.14,.45],[1,1,.94,.72,.25,0]),
                          utility(n["alveolar_residual"],[0,.002,.01,.04,.15,.50],[1,1,.94,.72,.25,0]),
                          utility(airway["error"],[0,.004,.015,.05,.18,.55],[1,1,.94,.72,.25,0])],[.24,.28,.22,.26])
        q_causal=utility(causal,[0,.22,.40,.65,1.0,1.5],[1,1,.94,.72,.25,0])
        device=group([utility(margin,[-.3,0,.15,.35,.7],[0,.25,.65,1,1]),
                      utility(max(r["alarm_strategy_error"] for r in rows),[0,.03,.09,.20,.42,.80],[1,1,.94,.72,.25,0]),
                      utility(leak["error"],[0,.025,.07,.16,.36,.75],[1,1,.94,.72,.25,0]),q_causal,
                      utility(max(max(r["cycle_period_error"],r["ie_ratio_error"]) for r in rows),[0,.015,.04,.10,.25,.60],[1,1,.94,.72,.25,0])],[.16,.18,.22,.27,.17])
        M=group([physiology,device],[.48,.52]);causal_cap=.25+.75*q_causal;M=min(M,causal_cap)
        if not n.get("breath_cycle_present",False):M=min(M,.25)
        if physiology<=0 and device<=0:M=0
    else:A=Q=M=0
    rq=[];dq=[]
    for r in rows:
        if not r.get("breath_cycle_present",False):rq.append(0);dq.append(0);continue
        rq.append(group([utility(r["plateau_error"],[0,.5,1,2.5,6,10],[1,1,.9,.65,.2,0]),
                         utility(r["peep_error"],[0,.3,.7,1.5,3.5,6],[1,1,.9,.7,.25,0]),
                         utility(r["tidal_volume_ratio_error"],[0,.06,.14,.30,.58,1.0],[1,1,.92,.69,.23,0]),ceiling(r["max_pressure"]),
                         utility(r["alarm_strategy_error"],[0,.05,.13,.28,.55,.90],[1,1,.92,.68,.22,0])],[.28,.17,.18,.25,.12]))
        dq.append(group([utility(r["recovery_time"],[0,.4,.9,1.8,3.5,6],[1,1,.9,.68,.25,0]),
                         utility(r["obstruction_response_deficit"],[0,.02,.08,.25,.70,1],[1,1,.92,.68,.22,0]),
                         utility(r["obstruction_ratio_error"],[0,.04,.12,.28,.58,1.0],[1,1,.92,.68,.22,0])],[.45,.25,.30]))
    R=tail(rq);D=tail(dq);cap=ceiling(max((r["max_pressure"] for r in rows),default=float("inf")))
    groups={"A":A,"Q":Q,"M":M,"R":R,"D":D}
    value=total(gate,[A,Q,M,R,D],weights(e))
    return groups,value,{"range":rq,"dynamic":dq,"safety_ceiling_utility":cap,"causal_mechanism_utility_ceiling":causal_cap,"future_valve_causality":fit}
def main():
    a=parser(TASK_ID).parse_args();e=load_evidence(a.evidence,TASK_ID);g,v,u=score(e)
    r=base_receipt(a.evidence,e,g,v,policy_id="simuverity-101-v1:p9-xmed01:scoring");r.update({"scenario_rows":e["facts"].get("scenario_rows",[]),"utility_metrics":u});write_receipt(a.output,r)
if __name__=="__main__":main()
