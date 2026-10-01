#!/usr/bin/env python3
"""Python implementation of F90-XROBO-01 GAQMRD semantics."""
from __future__ import annotations
import math,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[2]))
from formal90_scoring_core import base_receipt,clip,load_evidence,parser,write_receipt
TASK_ID="F90-XROBO-01"
def low(x,good,bad):return clip((bad-float(x))/(bad-good)) if float(x)>good else 1.0
def high(x,bad,good):return clip((float(x)-bad)/(good-bad)) if float(x)<good else 1.0
def band(x,lo,hi,lbad,hbad):
    x=float(x)
    if lo<=x<=hi:return 1.0
    if x<lo:return clip((x-lbad)/(lo-lbad))
    return clip((hbad-x)/(hbad-hi))
def bottleneck(values,weights):
    values=[clip(v) for v in values];den=sum(weights)
    return math.sqrt(sum(v*w for v,w in zip(values,weights))/den*min(values))
def pair(rows,low_id,high_id,kind,input_field):
    lo=next(r for r in rows if r["id"]==low_id);hi=next(r for r in rows if r["id"]==high_id)
    mean=lambda a,b:(a+b)/2
    power=abs(hi["electrical_power_rms_w"]-lo["electrical_power_rms_w"])/max(mean(hi["electrical_power_rms_w"],lo["electrical_power_rms_w"]),1e-9)
    motion=abs(hi["forward_displacement_m"]-lo["forward_displacement_m"])/max(mean(abs(hi["forward_displacement_m"]),abs(lo["forward_displacement_m"])),1e-9)
    if kind=="torque":raw=.60*power+.40*motion
    else:
        contact=sum(abs(a-b) for a,b in zip(hi["contact_duty_fractions"],lo["contact_duty_fractions"]))/len(hi["contact_duty_fractions"])
        vertical=abs(hi["vertical_ripple_m"]-lo["vertical_ripple_m"])/max(mean(hi["vertical_ripple_m"],lo["vertical_ripple_m"]),1e-9)
        load=abs(hi["load_current_rms_a"]-lo["load_current_rms_a"])/max(mean(hi["load_current_rms_a"],lo["load_current_rms_a"]),1e-9)
        raw=max(contact,vertical,power,load,motion)
    low_input=float(lo["values"][input_field]);high_input=float(hi["values"][input_field])
    span=abs(high_input-low_input)/max(mean(abs(high_input),abs(low_input)),1e-9)
    value=raw/span;util=high(value,.005,.08 if kind=="torque" else .06)
    return {"low_scenario":low_id,"high_scenario":high_id,"input_field":input_field,"value":value,"utility":util}
def score(e):
    f=e["facts"];rows=f.get("scenario_rows",[]);audit=f.get("static_audit",{});gate=bool(f.get("score_inputs_valid",False))
    if not gate or not rows:return {"A":0,"Q":0,"M":0,"R":0,"D":0},0,{},list(f.get("gate_reasons",[]))
    n=next(r for r in rows if r["id"]=="nominal")
    A=bottleneck([high(n["forward_displacement_m"],.60,3.50),high(n["positive_progress_fraction"],.55,.90),high(n["minimum_body_height_m"],.05,.25)],[.50,.25,.25])
    Q=bottleneck([low(n["lateral_span_m"],.01,.08),low(n["vertical_ripple_m"],.22,.65),band(n["bus_voltage_median_v"],20,28,10,40),low(n["battery_smoothing_ratio"],.95,1.40)],[.20,.25,.25,.30])
    torque=pair(rows,"torque_pair_low","torque_pair_high","torque","propulsive_torque_nm")
    stiffness=pair(rows,"ground_stiffness_pair_low","ground_stiffness_pair_high","ground","ground_stiffness_npm")
    damping=pair(rows,"ground_damping_pair_low","ground_damping_pair_high","ground","ground_damping_nspm")
    M=bottleneck([clip(audit["mechanism_fraction"]),min(low(r["body_kinematic_error_mps"],.03,.35) for r in rows),
                  min(low(r["contact_gait_mismatch_fraction"],.10,.45) for r in rows),min(low(r["initial_vx_error_fraction"],.025,.20) for r in rows),
                  torque["utility"],stiffness["utility"],damping["utility"]],[.35,.15,.15,.10,.15,.05,.05])
    non=[r for r in rows if r["id"]!="nominal"];operating=[]
    for r in non:
        operating.append(bottleneck([band(r["progress_ratio"],.55,1.45,.08,2.50),high(r["minimum_body_height_m"],.05,.22),
                                     high(min(r["contact_transition_counts"]),0,4),float(bool(r["electrical_dynamic"]))*band(r["bus_voltage_median_v"],18,30,8,42)],[.40,.25,.20,.15]))
    dynamics=[]
    for r in rows:
        dynamics.append(bottleneck([clip(min(r["landing_counts"])/2),high(r["gait_phase_coverage"],3,7),
                                    low(r["gait_establishment_time_s"],1.0,2.70),high(r["diagonal_alternation_count"],1,5)],[.35,.20,.20,.25]))
    R=min(operating);D=min(dynamics);groups={"A":A,"Q":Q,"M":M,"R":R,"D":D}
    w=e["group_weights"];value=100*A**w["A"]*Q**w["Q"]*M**w["M"]*R**w["R"]*D**w["D"]
    diagnostics={"propulsive_torque":torque,"ground_stiffness":stiffness,"ground_damping":damping,"range":operating,"dynamic":dynamics}
    return groups,value,diagnostics,[]
def main():
    a=parser(TASK_ID).parse_args();e=load_evidence(a.evidence,TASK_ID);g,v,d,reasons=score(e)
    r=base_receipt(a.evidence,e,g,v,policy_id="simuverity-101-v1:f90-xrobo-01:scoring",gate_reasons=reasons);r.update({"scenario_rows":e["facts"].get("scenario_rows",[]),"static_audit":e["facts"].get("static_audit",{}),"pair_diagnostics":d});write_receipt(a.output,r)
if __name__=="__main__":main()
