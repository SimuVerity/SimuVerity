#!/usr/bin/env python3
"""Post-lock Python reproduction of F90-XFLUID-02 score semantics."""
from __future__ import annotations
import math,statistics,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[2]))
from formal90_scoring_core import base_receipt,clip,load_evidence,parser,write_receipt
TASK_ID="F90-XFLUID-02"
def low(x,g,b):return clip((b-float(x))/(b-g))
def high(x,b,g):return clip((float(x)-b)/(g-b))
def band(x,lg,hg,lb,hb):
    x=float(x)
    return 1 if lg<=x<=hg else high(x,lb,lg) if x<lg else low(x,hg,hb)
def corr(a,b):
    if len(set(a))<2 or len(set(b))<2:return 0
    ma=statistics.mean(a);mb=statistics.mean(b)
    numerator=sum((x-ma)*(y-mb) for x,y in zip(a,b))
    denominator=math.sqrt(sum((x-ma)**2 for x in a)*sum((y-mb)**2 for y in b))
    return clip(numerator/denominator) if denominator else 0
def target(rows,values):
    commands=[v["pump_speed_rpm"]*(1+v["speed_step_fraction"]) for v in values]
    speeds=[r["shaft_speed_mean"] for r in rows];pressures=[v["output_pressure_bar"] for v in values];measured=[r["outlet_pressure_mean"] for r in rows]
    speed_span=(max(speeds)-min(speeds))/max(max(commands)-min(commands),1e-9)
    return .40*high(corr(commands,speeds),.55,.92)+.20*band(speed_span,.45,1.35,.15,1.80)+.40*high(corr(pressures,measured),.65,.95)
def paired(fault,control,values):
    selected=max(1,min(3,round(values["fault_cylinder"])))-1;control_flow=max(control["outlet_flow_mean"],1e-9)
    flow_drop=(control["outlet_flow_mean"]-fault["outlet_flow_mean"])/control_flow
    selected_drop=(control["plunger_flow_mean"][selected]-fault["plunger_flow_mean"][selected])/max(abs(control["plunger_flow_mean"][selected]),1e-9)
    others=[i for i in range(3) if i!=selected]
    other=sum((control["plunger_flow_mean"][i]-fault["plunger_flow_mean"][i])/max(abs(control["plunger_flow_mean"][i]),1e-9) for i in others)/2
    selectivity=selected_drop-other;effect=.60*high(flow_drop,.015,.10)+.40*high(selectivity,.015,.12);continuity=high(fault["outlet_flow_mean"]/control_flow,.45,.78)
    return {"selected_cylinder":selected+1,"outlet_flow_drop_fraction":flow_drop,"selected_plunger_drop_fraction":selected_drop,"other_plunger_drop_fraction":other,"selectivity":selectivity,"fault_continuity_fraction":fault["outlet_flow_mean"]/control_flow,"effect_score":effect,"continuity_score":continuity,"score":.65*effect+.35*continuity}
def score(e):
    f=e["facts"];rows=f.get("scenario_rows",[]);values=f.get("scenario_values",[]);static=f.get("static_audit",{});gate=bool(f.get("score_inputs_valid",False))
    reasons=f.get("gate_reasons",[])
    if isinstance(reasons,str):reasons=[reasons]
    else:reasons=list(reasons)
    if not gate or not rows:return {"A":0,"Q":0,"M":0,"R":0,"D":0},0,reasons,{}
    n=rows[0]
    A=.45*low(n["final_speed_error"],.03,.20)+.20*low(n["pressure_error"],.05,.20)+.25*band(n["volumetric_efficiency"],.72,1.05,.35,1.30)+.10*high(n["outlet_flow_mean"],4,18)
    Q=.25*low(n["pressure_ripple"],.03,.12)+.25*low(n["flow_ripple"],.35,.80)+.35*low(n["plunger_balance"],.08,.35)+.15*low(n["reverse_flow_ratio"],.02,.15)
    static_m=sum(float(static[k]) for k in ("three_plungers","six_check_valves","finite_fluid_compliance","speed_feedback_loop","physical_torque_sensor","fault_parameters_in_plant"))/6
    target_response=target(rows,values)
    # The public task requires an actual triplex positive-displacement pump.
    # Behaviour-only closure and command response retain partial credit, but
    # cannot substitute for the six representation-neutral physical features
    # recorded by the current static audit.
    M=.75*static_m+.10*min(r["flow_closure_score"] for r in rows)+.05*min(r["power_consistency_score"] for r in rows)+.10*target_response
    operating=[.45*low(r["final_speed_error"],.04,.22)+.20*low(r["pressure_error"],.06,.22)+.20*band(r["volumetric_efficiency"],.68,1.08,.30,1.35)+.15*low(r["plunger_balance"],.12,.45) for r in rows]
    steps=[.60*low(r["final_speed_error"],.04,.22)+.40*low(r["step_response_error"],.25,1.10) for r in rows]
    ids=[r["id"] for r in rows];fi=ids.index("paired_fault");ci=ids.index("paired_control");pair=paired(rows[fi],rows[ci],values[fi])
    R=min(operating);D=.65*min(steps)+.35*pair["score"];groups={"A":A,"Q":Q,"M":M,"R":R,"D":D};w=e["group_weights"]
    value=0.0 if any(groups[k]<=0 for k in groups) else 100*math.exp(sum(w[k]*math.log(groups[k]) for k in groups))
    value=max(0.0,min(100.0,value))
    return groups,value,[],{"operating":operating,"step_scores":steps,"paired_fault_metrics":pair,"target_response":target_response}
def main():
    a=parser(TASK_ID).parse_args();e=load_evidence(a.evidence,TASK_ID);g,v,reasons,d=score(e)
    r=base_receipt(a.evidence,e,g,v,policy_id="simuverity-101-v1:f90-xfluid-02:scoring",gate_reasons=reasons);r.update({"scenario_rows":e["facts"].get("scenario_rows",[]),"static_audit":e["facts"].get("static_audit",{}),"utility_metrics":d});write_receipt(a.output,r)
if __name__=="__main__":main()
