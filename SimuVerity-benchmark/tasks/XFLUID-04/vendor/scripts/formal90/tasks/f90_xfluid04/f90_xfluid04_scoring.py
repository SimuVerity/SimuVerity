#!/usr/bin/env python3
"""Post-lock Python reproduction of F90-XFLUID-04 score semantics."""
from __future__ import annotations
import math,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[2]))
from formal90_scoring_core import base_receipt,clip,load_evidence,parser,write_receipt
TASK_ID="F90-XFLUID-04"
def low(x,g,b):return clip((b-float(x))/(b-g))
def high(x,b,g):return clip((float(x)-b)/(g-b))
def bottleneck(values,weights):
    values=[clip(v) for v in values];return math.sqrt(sum(v*w for v,w in zip(values,weights))/sum(weights)*min(values))
def score(e):
    f=e["facts"];rows=f.get("scenario_rows",[]);s=f.get("static_audit",{});p=f.get("paired_causality",{});technical=bool(f.get("score_inputs_valid",False))
    if not technical or not rows:return {"A":0,"Q":0,"M":0,"R":0,"D":0},0,False,list(f.get("gate_reasons",[])),{}
    n=rows[0]
    au={"initial_extension":low(n["initial_extension_error_mm"],3,8),"cycle_tracking":low(n["cycle_tracking_rmse_mm"],3,10),"upper_hold":low(n["upper_hold_error_mm"],2.5,7),"returned_home":low(n["return_error_mm"],3,8)}
    A=bottleneck(list(au.values()),[.12,.43,.25,.20])
    qu={"upper_overshoot":low(n["upper_overshoot_mm"],4,18),"tail_oscillation":low(n["tail_oscillation_mm"],.15,1.5),"tail_motion":low(n["tail_velocity_rms_mm_per_s"],.10,2),"velocity_bound":low(n["peak_velocity_mm_per_s"],80,180),"spool_bound":low(n["peak_spool_mm"],.12,.25)}
    Q=bottleneck(list(qu.values()),[.24,.20,.18,.18,.20])
    static_m=bottleneck([s[k] for k in ("hydraulic_power_path","metering_valve","double_acting_cylinder","electromechanical_valve_drive","scissor_load","measured_feedback","physical_output_origins","public_input_bindings")],[1]*8)
    extension=high(p["pressure_extension_difference_mm"],.04,.35);spool=high(p["pressure_spool_difference_mm"],.00010,.0010);causal=max(extension,spool)
    mu={"static_mechanism":static_m,"root_connectivity":s["root_physical_path_fraction"],"pressure_causality":causal}
    M=bottleneck(list(mu.values()),[.55,.20,.25])
    operating=[bottleneck([low(r["cycle_tracking_rmse_mm"],4,12),low(r["upper_hold_error_mm"],3,8),low(r["return_error_mm"],3,8),low(r["pressure_peak_tracking_error_mm"],4,12),low(r["peak_velocity_mm_per_s"],100,220),low(r["peak_spool_mm"],.15,.30)],[.30,.18,.16,.14,.10,.12]) for r in rows]
    drop=next(r for r in rows if r["id"]=="pressure_drop_pair")
    du={"extension_causality":extension,"spool_causality":spool,"extension_or_spool_causality":causal,"post_change_tracking":low(drop["pressure_tracking_rmse_mm"],3,8),"peak_change_error":low(drop["pressure_peak_tracking_error_mm"],4,12),"recovery":low(drop["pressure_recovery_s"],1,4),"returned_home":low(drop["return_error_mm"],3,8)}
    D=bottleneck([causal,causal,du["post_change_tracking"],du["peak_change_error"],du["recovery"],du["returned_home"]],[.15,.15,.25,.15,.15,.15]);R=min(operating)
    command=n["command_motion_fraction"]>=.70 and n["cycle_tracking_rmse_mm"]<=12 and n["return_error_mm"]<=10
    pressure=p["pressure_extension_difference_mm"]>=.04 or p["pressure_spool_difference_mm"]>=.00010
    gate=bool(s.get("core_path_qualified")) and command and pressure;reasons=[]
    if not bool(s.get("core_path_qualified")):reasons.append("core hydraulic-mechanical-feedback topology was not qualified")
    if not command:reasons.append("measured physical extension did not execute the declared command")
    if not pressure:reasons.append("paired pressure perturbation produced no qualified physical response")
    groups={"A":A,"Q":Q,"M":M,"R":R,"D":D};value=100*A**.22*Q**.16*M**.24*R**.23*D**.15 if gate else 0
    for label,x in zip(("A nominal accuracy","Q motion quality","M physical mechanism/causality","R worst operating point","D pressure-change response"),(A,Q,M,R,D)):
        if x<.60:reasons.append(f"{label} group below 0.60: {x:.4f}")
    return groups,value,gate,reasons,{"A":au,"Q":qu,"M":mu,"R":operating,"D":du}
def main():
    a=parser(TASK_ID).parse_args();e=load_evidence(a.evidence,TASK_ID);g,v,gate,reasons,u=score(e)
    r=base_receipt(a.evidence,e,g,v,policy_id="simuverity-101-v1:f90-xfluid-04:scoring",gate_reasons=reasons,gate_override=gate);r.update({"scenario_rows":e["facts"].get("scenario_rows",[]),"static_audit":e["facts"].get("static_audit",{}),"raw_metrics":{"paired_causality":e["facts"].get("paired_causality",{})},"utility_metrics":u});write_receipt(a.output,r)
if __name__=="__main__":main()
