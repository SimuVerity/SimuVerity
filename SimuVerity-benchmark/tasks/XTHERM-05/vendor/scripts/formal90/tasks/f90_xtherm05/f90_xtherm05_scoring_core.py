#!/usr/bin/env python3
"""Post-lock Python reproduction of F90-XTHERM-05 score semantics."""
from __future__ import annotations
import math,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[2]))
from formal90_scoring_core import base_receipt,clip,load_evidence,parser,write_receipt
TASK_ID="F90-XTHERM-05"
def low(x,g,b):return clip((b-float(x))/(b-g))
def high(x,b,g):return clip((float(x)-b)/(g-b))
def band(x,lg,hg,lb,hb):
    x=float(x)
    return 1 if lg<=x<=hg else high(x,lb,lg) if x<lg else low(x,hg,hb)
def bottleneck(values,weights):
    values=[clip(v) for v in values];den=sum(weights)
    return math.sqrt(sum(v*w for v,w in zip(values,weights))/den*min(values))
def score(e):
    f=e["facts"];rows=f.get("scenario_rows",[]);static=f.get("static_audit",{});flow=f.get("paired_flow",{});current=f.get("paired_current",{});technical=bool(f.get("score_inputs_valid",False))
    if not technical or not rows:return {"A":0,"Q":0,"M":0,"R":0,"D":0},0,False,list(f.get("gate_reasons",[])),{}
    n=rows[0]
    au={"initial_temperature":low(n["initial_temperature_error_K"],.15,2.0),"pre_step_charging":band(n["pre_current_utilization"],.15,.98,.02,1.25),"post_step_charging":band(n["post_current_utilization"],.15,.98,.02,1.25),"voltage":band(n["voltage_tail_V"],2.7,4.25,1.5,5.0)}
    A=bottleneck(list(au.values()),[.20,.30,.30,.20])
    qu={"battery_uniformity":low(n["battery_spread_K"],2.5,12),"plate_uniformity":low(n["plate_spread_K"],2.5,12),"tail_drift":low(abs(n["battery_tail_drift_K_per_s"]),.015,.12),"battery_spatial_field":high(n["battery_distinct_tail_channels"],3,12),"plate_spatial_field":high(n["plate_distinct_tail_channels"],3,12)}
    Q=bottleneck(list(qu.values()),[.30,.25,.15,.15,.15])
    static_m=bottleneck([static[k] for k in ("distributed_battery","distributed_plate","thermal_liquid_path","physical_coolant_sensing","physical_charging_path","feedback_evidence","public_input_bindings")],[1]*7)
    mu={"static_mechanism":static_m,"flow_pressure_causality":high(flow["pressure_ratio"],1.15,2.0),"flow_thermal_causality":math.sqrt(high(flow["battery_improvement_K"],.02,.35)*high(flow["plate_improvement_K"],.01,.25))}
    M=bottleneck(list(mu.values()),[.50,.25,.25])
    operating=[bottleneck([band(r["battery_tail_max_K"],278,326,270,345),low(r["battery_spread_K"],4,15),band(r["coolant_pressure_drop_bar"],.001,4.0,0,12),band(abs(r["coolant_temperature_rise_K"]),.001,15,0,35),band(r["post_current_utilization"],.12,1.05,.02,1.30)],[.28,.22,.15,.10,.25]) for r in rows]
    common=min(band(r["post_current_utilization"],.80,1.05,.20,1.30) for r in rows if r["id"] in ("current_pair_up","current_pair_control","current_pair_down"))
    prematch=low(current["maximum_pre_pair_relative_difference"],.015,.10)
    dynamic=[bottleneck([band(current["up_effect_fraction"],.85,1.15,.30,1.70),prematch,common],[.55,.20,.25]),bottleneck([band(current["down_effect_fraction"],.85,1.15,.30,1.70),prematch,common],[.55,.20,.25])]
    R=min(operating);D=min(dynamic)
    spatial=n["battery_distinct_tail_channels"]>=2 and n["plate_distinct_tail_channels"]>=2
    flow_gate=flow["pressure_ratio"]>1.02 and (flow["battery_improvement_K"]>0 or flow["plate_improvement_K"]>0)
    current_gate=.30<current["up_effect_fraction"]<1.70 and .30<current["down_effect_fraction"]<1.70
    gate=bool(static.get("core_path_qualified")) and spatial and flow_gate and current_gate
    reasons=[]
    if not spatial:reasons.append("required temperature channels did not form independent spatial fields")
    if not flow_gate:reasons.append("coolant-flow perturbation did not act causally on pressure and temperature")
    if not current_gate:reasons.append("CC-active limit triplet did not produce near-1:1 total-pack ampere response")
    groups={"A":A,"Q":Q,"M":M,"R":R,"D":D};value=100*A**.20*Q**.17*M**.25*R**.23*D**.15 if gate else 0
    for label,x in zip(("A nominal accuracy","Q temperature-field quality","M physical mechanism/causality","R worst operating point","D current-limit-change response"),(A,Q,M,R,D)):
        if x<.60:reasons.append(f"{label} group below 0.60: {x:.4f}")
    return groups,value,gate,reasons,{"A":au,"Q":qu,"M":mu,"R":operating,"D":dynamic}
def main():
    a=parser(TASK_ID).parse_args();e=load_evidence(a.evidence,TASK_ID);g,v,gate,reasons,u=score(e)
    r=base_receipt(a.evidence,e,g,v,policy_id="simuverity-101-v1:f90-xtherm-05:scoring",gate_reasons=reasons,gate_override=gate);r.update({"scenario_rows":e["facts"].get("scenario_rows",[]),"static_audit":e["facts"].get("static_audit",{}),"raw_metrics":{"paired_flow":e["facts"].get("paired_flow",{}),"paired_current":e["facts"].get("paired_current",{})},"utility_metrics":u});write_receipt(a.output,r)
if __name__=="__main__":main()
