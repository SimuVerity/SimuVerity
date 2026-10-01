#!/usr/bin/env python3
"""Post-lock Python reproduction of XP9 XAUTO01 score semantics."""
from __future__ import annotations
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[2]))
from formal90_offline_common import base_receipt,group,load_evidence,parser,tail,total,utility,weights,write_receipt
TASK_ID="F90-XAUTO-01"
def score(e):
    f=e["facts"];rows=f.get("scenario_rows",[]);s=f.get("suite_metrics",{});probe=f.get("brake_probe",{});gate=bool(f.get("score_inputs_valid",False))
    completion=min(max(1-float(probe.get("response_deficit",1)),0),1)
    if rows:
        n=rows[0]
        A=group([utility(n["final_speed_ratio"],[0,.008,.025,.07,.18,.42],[1,1,.95,.75,.30,0]),
                 utility(n["slip_regulation_violation"],[0,.004,.018,.06,.22,.65],[1,1,.94,.73,.27,0])],[.50,.50])
        Q=group([utility(n["lock_fraction"],[0,.004,.018,.065,.20,.55],[1,1,.94,.72,.25,0]),
                 utility(n["peak_yaw"],[0,.025,.065,.15,.35,.75],[1,1,.94,.72,.24,0]),
                 utility(n["peak_lateral"],[0,.12,.32,.80,2.1,5.0],[1,1,.94,.72,.24,0]),
                 utility(n["torque_ripple"],[0,.04,.10,.22,.50,1.0],[1,1,.94,.72,.25,0])],[.30,.25,.25,.20])
        q_plant=group([utility(s["longitudinal_error"],[0,.015,.045,.12,.30,.70],[1,1,.95,.75,.30,0]),
                       utility(s["wheel_error"],[0,.02,.06,.16,.38,.85],[1,1,.95,.75,.30,0]),
                       utility(s["pose_kinematic_error"],[0,.004,.015,.05,.16,.50],[1,1,.95,.75,.30,0]),
                       utility(s["yaw_dynamic_error"],[0,.025,.07,.18,.42,.90],[1,1,.94,.72,.25,0])],[.27,.27,.20,.26])
        q_boundary=group([utility(max(n["initial_speed_error"],n["initial_wheel_speed_error"]),[0,.001,.004,.015,.05,.18],[1,1,.95,.75,.30,0]),
                          utility(n["actuation_contract_error"],[0,.002,.008,.025,.10,.35],[1,1,.95,.75,.30,0]),
                          utility(probe["response_deficit"],[0,.03,.10,.25,.55,1],[1,1,.94,.72,.25,0])],[.25,.35,.40])
        M=group([utility(n["friction_envelope_violation"],[0,.002,.010,.040,.12,.35],[1,1,.95,.75,.30,0]),
                 utility(n["slip_kinematic_error"],[0,.006,.020,.060,.16,.45],[1,1,.95,.74,.28,0]),
                 utility(n["contact_causality_error"],[0,.002,.010,.040,.15,.45],[1,1,.94,.72,.25,0]),
                 utility(s["normal_load_error"],[0,.001,.004,.012,.04,.12],[1,1,.95,.75,.30,0]),q_plant,q_boundary,
                 utility(max(r["finite_physical_violation"] for r in rows),[0,1e-8,1e-6,1e-4,.01,.10,1],[1,.999,.995,.98,.80,.30,0])],
                [.15,.16,.13,.10,.24,.16,.06])
        M=min(M,.35+.65*completion)
    else:A=Q=M=0
    rq=[];dq=[];dynamic=[]
    for r in rows:
        rq.append(group([utility(r["final_speed_ratio"],[0,.015,.045,.11,.27,.58],[1,1,.93,.70,.24,0]),
                         utility(r["slip_regulation_violation"],[0,.008,.030,.10,.35,.80],[1,1,.92,.69,.22,0]),
                         utility(r["peak_yaw"],[0,.04,.10,.23,.52,1.05],[1,1,.92,.68,.20,0]),
                         utility(r["peak_lateral"],[0,.20,.55,1.35,3.4,7.0],[1,1,.92,.68,.20,0]),
                         utility(r["lock_fraction"],[0,.008,.03,.10,.30,.70],[1,1,.92,.68,.20,0])],[.25,.25,.18,.17,.15]))
        value=group([utility(r["recovery_time"],[0,.18,.40,.80,1.45,2.8],[1,1,.93,.72,.28,0]),
                     utility(r["event_consistency_error"],[0,.020,.060,.14,.30,.65],[1,1,.94,.72,.26,0])],[.72,.28])
        dq.append(value)
        if not str(r.get("scenario","")).startswith("brake_probe_"):dynamic.append(value)
    R=tail(rq);D=tail(dynamic)
    groups={"A":A,"Q":Q,"M":M,"R":R,"D":D}
    return groups,total(gate,[A,Q,M,R,D],weights(e)),{"range":rq,"dynamic":dynamic,"brake_mechanism_completion":completion}
def main():
    a=parser(TASK_ID).parse_args();e=load_evidence(a.evidence,TASK_ID);g,v,u=score(e)
    r=base_receipt(a.evidence,e,g,v,policy_id="simuverity-101-v1:p9-xauto01:scoring");r.update({"scenario_rows":e["facts"].get("scenario_rows",[]),"suite_metrics":e["facts"].get("suite_metrics",{}),"utility_metrics":u});write_receipt(a.output,r)
if __name__=="__main__":main()
