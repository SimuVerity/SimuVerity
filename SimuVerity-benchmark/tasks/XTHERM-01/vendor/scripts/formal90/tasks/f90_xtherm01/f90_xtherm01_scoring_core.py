#!/usr/bin/env python3
"""Post-lock Python reproduction of harder-thermal XTHERM02 semantics."""
from __future__ import annotations
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[2]))
from formal90_scoring_core import base_receipt,group,load_evidence,parser,tail,total,utility,weights,write_receipt
TASK_ID="F90-XTHERM-01"
def score(e):
    f=e["facts"];rows=f.get("scenario_rows",[]);s=f.get("suite_metrics",{});gate=bool(f.get("score_inputs_valid",False))
    if rows:
        n=rows[0]
        A=group([utility(n["cabin_error"],[0,.20,.45,.90,1.8,4.0],[1,1,.95,.75,.28,0]),
                 utility(n["component_excess"],[0,.15,.50,1.5,4,10],[1,1,.95,.75,.28,0])],[.62,.38])
        Q=group([utility(n["cabin_ripple"],[0,.04,.12,.35,1.0,3.0],[1,1,.94,.72,.25,0]),
                 utility(n["comfort_violation"],[0,.01,.04,.12,.35,.80],[1,1,.94,.72,.25,0]),
                 utility(n["component_violation"],[0,.002,.01,.04,.16,.60],[1,1,.94,.72,.25,0]),
                 utility(n["actuator_chatter"],[0,.005,.02,.06,.18,.55],[1,1,.94,.72,.25,0])],[.24,.34,.27,.15])
        q_storage=group([utility(v,[0,.015,.05,.14,.36,.85],[1,1,.94,.72,.25,0]) for v in s["storage_residual"]]+[float(bool(s["storage_coefficients_physical"]))],[1,1,1,1,1.5])
        q_passive=utility(s["passivity_violation"],[0,.001,.005,.02,.08,.30],[1,1,.95,.75,.28,0])
        q_input=group([utility(s["generation_schedule_residual"],[0,.002,.008,.025,.08,.25],[1,1,.95,.75,.30,0]),
                       utility(s["cabin_gain_causality_residual"],[0,.02,.07,.18,.45,1.0],[1,1,.94,.72,.25,0])],[.58,.42])
        q_capacity=group([utility(s["capacity_schedule_residual"],[0,.002,.008,.025,.08,.25],[1,1,.95,.75,.30,0]),
                          utility(s["capacity_exceedance_residual"],[0,.001,.004,.015,.06,.25],[1,1,.95,.74,.27,0]),
                          utility(s["allocation_residual"],[0,.003,.012,.04,.14,.45],[1,1,.94,.72,.25,0])],[.38,.34,.28])
        q_power=group([utility(s["condenser_residual"],[0,.003,.012,.04,.14,.45],[1,1,.94,.72,.25,0]),
                       utility(s["cop_violation"],[0,.001,.004,.015,.06,.25],[1,1,.95,.74,.27,0]),
                       utility(s["energy_residual"],[0,.002,.008,.025,.08,.25],[1,1,.95,.75,.30,0]),
                       utility(s["actuator_contract_violation"],[0,.001,.004,.015,.06,.25],[1,1,.95,.74,.27,0])],[.25,.20,.30,.25])
        M=group([q_storage,q_passive,q_input,q_capacity,q_power],[.28,.13,.16,.23,.20])
        if not s.get("core_thermal_storage",False) or s.get("static_setpoint_shortcut",False):M=0
        elif not s.get("core_shared_capacity",False):M=min(M,.45)
        elif not s.get("core_component_coolant_path",False):M=min(M,.55)
    else:A=Q=M=0
    rq=[];dq=[]
    for r in rows:
        rq.append(group([utility(r["cabin_error"],[0,.30,.65,1.3,2.7,5.5],[1,1,.93,.70,.24,0]),
                         utility(r["comfort_violation"],[0,.02,.07,.20,.50,.90],[1,1,.93,.70,.24,0]),
                         utility(r["component_excess"],[0,.25,.80,2.2,5.5,13],[1,1,.93,.70,.24,0]),
                         utility(r["component_peak_excess"],[0,.25,.80,2.2,5.5,13],[1,1,.93,.70,.24,0]),
                         utility(r["capacity_exceedance_residual"],[0,.001,.004,.015,.06,.25],[1,1,.95,.74,.27,0])],[.30,.17,.23,.17,.13]))
        q_load=1 if float(r["inputs"]["component_heat_step_fraction"])<=0 else utility(r["load_actuation_response"],[0,.01,.03,.08,.18,.35],[0,.25,.55,.82,1,1])
        q_safety=group([utility(r["event_component_excess"],[0,.20,.65,1.8,4.5,11],[1,1,.93,.70,.24,0]),
                        utility(r["event_component_violation"],[0,.002,.01,.04,.16,.60],[1,1,.94,.72,.25,0])],[.60,.40])
        if float(r["inputs"]["compressor_capacity_loss"])<=0:q_response=q_excursion=q_recovery=1
        else:
            q_response=utility(r["capacity_response_strength"],[0,.004,.012,.035,.10,.25],[0,.25,.55,.82,1,1])
            if r["capacity_binding"]<.90 and r["capacity_event_excursion"]<=.20:q_response=max(q_response,.95)
            q_excursion=utility(r["capacity_event_excursion"],[0,.10,.25,.60,1.5,3.5],[1,1,.94,.72,.25,0])
            q_recovery=utility(r["capacity_recovery_time"],[0,60,150,300,600,1050],[1,1,.92,.70,.25,0])
        dq.append(group([q_load,utility(r["load_recovery_time"],[0,60,180,360,700,1400],[1,1,.92,.70,.25,0]),q_safety,
                         utility(r["capacity_schedule_residual"],[0,.002,.008,.025,.08,.25],[1,1,.95,.75,.30,0]),
                         q_response,q_excursion,q_recovery],[.17,.19,.16,.10,.13,.12,.13]))
    R=tail(rq);D=tail(dq)
    if not s.get("core_dynamic_interventions",False):D=0
    groups={"A":A,"Q":Q,"M":M,"R":R,"D":D}
    return groups,total(gate,[A,Q,M,R,D],weights(e)),{"range":rq,"dynamic":dq}
def main():
    a=parser(TASK_ID).parse_args();e=load_evidence(a.evidence,TASK_ID);g,v,u=score(e)
    r=base_receipt(a.evidence,e,g,v,policy_id="simuverity-101-v1:f90-xtherm-01:scoring")
    r.update({"scenario_rows":e["facts"].get("scenario_rows",[]),"suite_metrics":e["facts"].get("suite_metrics",{}),"utility_metrics":u});write_receipt(a.output,r)
if __name__=="__main__":main()
