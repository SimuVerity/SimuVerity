#!/usr/bin/env python3
"""Post-lock Python reproduction of XP9 XBATT01 score semantics."""
from __future__ import annotations
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[2]))
from formal90_offline_common import base_receipt,group,load_evidence,parser,tail,total,utility,weights,write_receipt
TASK_ID="F90-XBATT-01"
def score(e):
    f=e["facts"];rows=f.get("scenario_rows",[]);spread=f.get("spread_evidence",{});cool=f.get("cooling_evidence",{});fault=f.get("fault_evidence",{});control=f.get("control_evidence",{});gate=bool(f.get("score_inputs_valid",False))
    if rows:
        n=rows[0]
        A=group([utility(n["peak_temperature"],[260,307.5,310.5,313.5,316.5,321],[1,1,.94,.74,.30,0]),
                 utility(n["peak_spread"],[0,.35,.75,1.45,2.6,4.5],[1,1,.94,.73,.28,0]),
                 utility(max(40-n["min_module_voltage"],0),[0,.20,.55,1.2,2.5,5],[1,1,.94,.73,.28,0]),
                 utility(max(.30-n["min_soc"],0),[0,.01,.03,.07,.13,.25],[1,1,.94,.74,.30,0])],[.32,.28,.22,.18])
        Q=group([utility(n["safety_violation"],[0,.02,.08,.22,.60,1.5],[1,1,.93,.70,.24,0]),
                 utility(n["aux_energy_Wh"],[0,.20,.50,1.2,3.0,6.5],[1,1,.94,.74,.30,0]),
                 utility(n["alarm_mismatch"],[0,.002,.01,.04,.15,.45],[1,1,.94,.72,.25,0]),
                 utility(max(r["cooling_rating_violation"] for r in rows),[0,.002,.01,.04,.15,.45],[1,1,.94,.72,.25,0])],[.40,.22,.22,.16])
        q_pack=utility(max(r["series_voltage_residual"] for r in rows),[0,1e-6,2e-5,2e-4,2e-3,.02],[1,1,.95,.75,.30,0])
        q_charge=utility(max(r["charge_residual"] for r in rows),[0,2e-4,8e-4,.003,.012,.05],[1,1,.95,.74,.28,0])
        q_thermal=utility(max(r["thermal_residual"] for r in rows),[0,.004,.015,.05,.16,.45],[1,1,.94,.73,.27,0])
        q_fault_event=utility(max(r["fault_event_deficit"] for r in rows),[0,.01,.04,.12,.35,.80],[1,1,.95,.74,.28,0])
        q_fault_pair=utility(fault["response_deficit"],[0,.01,.04,.12,.35,.80],[1,1,.95,.74,.28,0])
        q_current=utility(max(r["current_profile_error"] for r in rows),[0,.06,.10,.16,.28,.50],[1,1,.95,.74,.28,0])
        q_electrical=utility(max(r["electrical_coupling_error"] for r in rows),[0,.05,.12,.24,.45,.85],[1,1,.95,.74,.28,0])
        q_initial=utility(max(r["initial_soc_error"] for r in rows),[0,1e-4,6e-4,.003,.015,.08],[1,1,.95,.75,.30,0])
        q_heat=utility(max(r["total_heat_residual"] for r in rows),[0,2e-5,2e-4,.002,.02,.15],[1,1,.95,.75,.30,0])
        q_spread=utility(spread["error"],[0,.035,.09,.20,.42,.80],[1,1,.95,.75,.30,0])
        q_transport=utility(cool["transport_error"],[0,.015,.045,.12,.30,.70],[1,1,.95,.75,.30,0])
        q_hydraulic=utility(cool["hydraulic_error"],[0,.02,.06,.15,.35,.75],[1,1,.95,.75,.30,0])
        q_aux=utility(cool["auxiliary_error"],[0,.02,.06,.15,.35,.75],[1,1,.95,.75,.30,0])
        profile=sum(float(bool(r["electrical_step_evidence"])) for r in rows)/len(rows)
        q_profile=q_current*profile
        q_electrical_group=group([q_pack,q_charge,q_electrical,q_initial],[.17,.23,.36,.24])
        q_exchange=utility(max(r["thermal_exchange_direction_error"] for r in rows),[0,.001,.01,.04,.15,.50],[1,1,.95,.75,.30,0])
        q_thermal_group=group([q_thermal,q_heat,q_spread,q_exchange],[.35,.22,.28,.15])
        q_cooling_group=group([q_fault_event,q_fault_pair,q_transport,q_hydraulic,q_aux],[.20,.18,.24,.21,.17])
        M=group([q_electrical_group,q_thermal_group,q_cooling_group,q_profile],[.29,.25,.23,.23])
        M=min(M,.45+.55*q_profile)
        if not cool.get("active_regulation_supported",False):M=min(M,.55)
        if not spread.get("thermal_spread_supported",False):M=min(M,.55)
        if max(r["total_heat_residual"] for r in rows)>.15:M=min(M,.45)
        if max(r["thermal_residual"] for r in rows)>.15:M=min(M,.45)
        if max(r["coolant_enthalpy_capacity_error"] for r in rows)>1e-8 or max(r["coolant_outlet_passivity_error"] for r in rows)>1e-8:M=min(M,.45)
    else:A=Q=M=q_profile=0
    rq=[];dq=[]
    for r in rows:
        rq.append(group([utility(r["peak_temperature"],[260,313.5,315.5,317.5,320,324],[1,1,.92,.68,.22,0]),
                         utility(r["peak_spread"],[0,.55,1.15,2.1,3.4,5.5],[1,1,.92,.69,.23,0]),
                         utility(max(36-r["min_module_voltage"],0),[0,.10,.35,.9,2.0,4.5],[1,1,.92,.69,.23,0]),
                         utility(max(.15-r["min_soc"],0),[0,.005,.02,.055,.12,.25],[1,1,.92,.68,.22,0]),
                         utility(r["safety_violation"],[0,.03,.10,.28,.75,1.8],[1,1,.92,.68,.22,0])],[.28,.24,.18,.12,.18]))
        if r["fault_severity"]<=.001:dq.append(1)
        else:dq.append(group([utility(r["recovery_time"],[0,3,8,17,35,65],[1,1,.92,.70,.26,0]),
                              utility(r["thermal_recovery_margin"],[-.05,-.025,-.012,-.004,.002,.02],[0,.20,.55,.82,.96,1]),
                              utility(max(r["fault_event_deficit"],r["event_physical_response_deficit"]),[0,.01,.04,.12,.35,.80],[1,1,.93,.71,.25,0])],[.38,.32,.30]))
    R=tail(rq)
    if rq:
        pair_dynamic=utility(fault["response_deficit"],[0,.01,.04,.12,.35,.80],[1,1,.93,.71,.25,0])
        D=group([tail(dq),pair_dynamic,q_profile],[.60,.25,.15]);D=min(D,.55+.45*q_profile)
        if not cool.get("active_regulation_supported",False):D=min(D,.35)
        if not control.get("active_control_response_supported",False):D=min(D,.40)
    else:D=0
    groups={"A":A,"Q":Q,"M":M,"R":R,"D":D}
    return groups,total(gate,[A,Q,M,R,D],weights(e)),{"range":rq,"dynamic":dq,"multilevel_profile_evidence":q_profile}
def main():
    a=parser(TASK_ID).parse_args();e=load_evidence(a.evidence,TASK_ID);g,v,u=score(e)
    r=base_receipt(a.evidence,e,g,v,policy_id="simuverity-101-v1:p9-xbatt01:scoring");r.update({"scenario_rows":e["facts"].get("scenario_rows",[]),"cross_scenario_metrics":{"spread":e["facts"].get("spread_evidence",{}),"cooling":e["facts"].get("cooling_evidence",{}),"paired_fault":e["facts"].get("fault_evidence",{}),"paired_active_control":e["facts"].get("control_evidence",{})},"utility_metrics":u});write_receipt(a.output,r)
if __name__=="__main__":main()
