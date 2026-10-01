#!/usr/bin/env python3
"""Post-lock Python reproduction of XP9 XFLUID01 score semantics."""
from __future__ import annotations
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[2]))
from formal90_offline_common import base_receipt,group,load_evidence,parser,tail,total,utility,weights,write_receipt
TASK_ID="F90-XFLUID-01"
def score(e):
    f=e["facts"];rows=f.get("scenario_rows",[]);s=f.get("suite_metrics",{});gate=bool(f.get("score_inputs_valid",False))
    if rows:
        n=rows[0]
        q_angle=[utility(v,[0,.12,.30,.70,1.8,4.5],[1,1,.95,.75,.28,0]) for v in n["angle_error_by_axis"]]
        q_vel=[utility(v,[0,.08,.20,.50,1.4,4],[1,1,.95,.73,.25,0]) for v in n["tail_velocity_by_axis"]]
        A=group(q_angle+q_vel,[.78/3]*3+[.22/3]*3)
        q_valve=[utility(v,[0,.002,.008,.025,.08,.20],[1,1,.95,.73,.25,0]) for v in n["valve_ripple_by_axis"]]
        Q=group([utility(n["pump_ripple"],[0,.002,.008,.025,.08,.22],[1,1,.95,.75,.28,0])]+q_valve+
                [utility(n["flow_utilization"],[0,.65,.85,.95,1.00,1.18],[1,1,.96,.88,.70,0])],[.35]+[.25/3]*3+[.40])
        q_cont=[utility(v,[0,.018,.05,.13,.32,.70],[1,1,.94,.72,.25,0]) for v in s["continuity_residual"]]
        q_open=[utility(v,[0,.025,.07,.17,.38,.75],[1,1,.94,.72,.25,0]) for v in s["opening_flow_residual"]]
        q_torque=[utility(v,[0,.018,.05,.13,.32,.70],[1,1,.94,.72,.25,0]) for v in s["pressure_torque_residual"]]
        q_power=[utility(v,[0,.015,.045,.12,.30,.68],[1,1,.94,.72,.25,0]) for v in s["hydraulic_power_residual"]]
        q_mech=[utility(v,[0,.025,.07,.17,.38,.78],[1,1,.94,.72,.25,0]) for v in s["mechanical_residual"]]
        q_envelope=group([
            utility(max(r["supply_pressure_upper_violation"] for r in rows),[0,.002,.008,.025,.08,.25],[1,1,.95,.75,.28,0]),
            utility(max(r["negative_supply_pressure_violation"] for r in rows),[0,.001,.004,.015,.06,.25],[1,1,.95,.75,.28,0]),
            utility(max(r["branch_pressure_envelope_violation"] for r in rows),[0,.002,.008,.025,.08,.25],[1,1,.95,.75,.28,0]),
            utility(max(r["negative_branch_flow_violation"] for r in rows),[0,.001,.004,.015,.06,.25],[1,1,.95,.75,.28,0]),
            utility(max(r["negative_pump_flow_violation"] for r in rows),[0,.001,.004,.015,.06,.25],[1,1,.95,.75,.28,0]),
            utility(max(r["valve_bound_violation"] for r in rows),[0,.001,.004,.015,.06,.25],[1,1,.95,.75,.28,0])],[1]*6)
        hydraulic=q_cont+q_open+q_torque+q_power+[
            utility(s["state_rate_residual"],[0,.006,.018,.05,.15,.45],[1,1,.95,.75,.28,0]),
            utility(max(r["pump_flow_residual"] for r in rows),[0,.006,.018,.05,.15,.45],[1,1,.95,.75,.28,0]),
            utility(s["zero_valve_flow_ratio"],[0,.001,.004,.015,.06,.25],[1,1,.95,.75,.28,0]),q_envelope,
            float(bool(s["hydraulic_coefficients_physical"])),float(bool(s["opening_flow_positive"])),float(bool(s["pressure_torque_positive"]))]
        q_hydraulic=group(hydraulic,[1]*19)
        q_mechanical=group(q_mech+[float(bool(s["mechanical_coefficients_physical"]))],[1]*4)
        q_dead=1 if s.get("deadband_compensation_credit",False) else utility(s["deadband_effect_strength"],[0,.0005,.0015,.004,.012,.04],[0,.28,.62,.88,1,1])
        q_ledger=group([utility(s["leak_passivity_violation"],[0,.001,.004,.015,.06,.25],[1,1,.95,.75,.28,0]),
                        utility(s["leak_monotonic_violation"],[0,.001,.01,.06,.22,.60],[1,1,.95,.75,.28,0]),q_dead,
                        utility(n["hydraulic_activity"],[0,120,350,900,2200,5000],[0,.25,.60,.88,1,1])],[.26,.24,.22,.28])
        M=group([q_hydraulic,q_mechanical,q_ledger],[.48,.28,.24])
        if not s.get("core_hydraulic_path",False):M=0
    else:A=Q=M=0
    rq=[];dq=[]
    for r in rows:
        qe=group([utility(v,[0,.20,.50,1.2,3.0,7.0],[1,1,.93,.70,.25,0]) for v in r["angle_error_by_axis"]],[1]*3)
        qv=group([utility(v,[0,.12,.30,.75,2.0,5.0],[1,1,.93,.70,.25,0]) for v in r["tail_velocity_by_axis"]],[1]*3)
        rq.append(group([qe,qv,utility(r["min_pressure_ratio"],[0,.45,.60,.72,.82,1.0],[0,.25,.62,.88,1,1]),
                         utility(r["flow_utilization"],[0,.68,.86,.96,1.00,1.20],[1,1,.95,.86,.70,0])],[.42,.16,.22,.20]))
        dq.append(group([utility(r["recovery_time"],[0,.20,.55,1.1,2.2,4.0],[1,1,.93,.70,.25,0]),
                         utility(r["leak_conductance_gain"]-1,[0,.03,.10,.28,.65,1.20],[0,.30,.65,.90,1,1]),
                         max(utility(r["event_compensation"],[0,.001,.004,.012,.04,.12],[0,.30,.65,.90,1,1]),
                             utility(r["event_motion_response"],[0,.0005,.002,.007,.025,.08],[0,.30,.65,.90,1,1]))],[.45,.30,.25]))
    R=tail(rq);D=tail(dq)
    if not s.get("core_leak_event",False):D=0
    groups={"A":A,"Q":Q,"M":M,"R":R,"D":D}
    return groups,total(gate,[A,Q,M,R,D],weights(e)),{"range":rq,"dynamic":dq}
def main():
    a=parser(TASK_ID).parse_args();e=load_evidence(a.evidence,TASK_ID);g,v,u=score(e)
    r=base_receipt(a.evidence,e,g,v,policy_id="simuverity-101-v1:p9-xfluid01:scoring");r.update({"scenario_rows":e["facts"].get("scenario_rows",[]),"suite_metrics":e["facts"].get("suite_metrics",{}),"utility_metrics":u});write_receipt(a.output,r)
if __name__=="__main__":main()
