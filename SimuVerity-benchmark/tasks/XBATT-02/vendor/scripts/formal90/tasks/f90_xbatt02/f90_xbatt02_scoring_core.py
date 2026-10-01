#!/usr/bin/env python3
"""Pure-offline F90-XBATT-02 score semantics."""
from __future__ import annotations
import math,statistics,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[2]))
from formal90_offline_common import base_receipt,clip,load_evidence,parser,write_receipt
TASK_ID="F90-XBATT-02"
def q(x,g,b):return clip((b-float(x))/(b-g)) if b>g else float(float(x)<=g)
def high(x,g,b):return clip((float(x)-b)/(g-b)) if g>b else float(float(x)>=g)
def pair_scores(p):
    d=p["demand"];m=p["maldistribution"];r=p["regeneration"];l=p["low_soc_supervision"];c=p["cooling_chain"]
    demand=min(high(d["current_ratio"],1.75,1.10),high(d["heat_ratio"],2.5,1.10),high(d["soc_depletion_ratio"],1.75,1.05),high(d["temperature_rise_delta_K"],.35,.02),high(d["cooling_power_ratio"],1.5,1.02))
    mal=min(high(m["flow_cv_delta"],.10,.02),high(m["temperature_spread_delta_K"],.50,.05))
    regen=min(high(r["minimum_negative_current_fraction"],.95,.25),high(r["minimum_soc_gain"],.003,.0002),high(r["minimum_voltage_rise_per_cell_V"],.12,.02))
    low=min(high(l["minimum_soc"],.080,.055),high(l["attenuation_fraction"],.08,.005),q(l["limiter_consistency_error"],.03,.30),high(l["risk_attenuation_gain"],.12,.03),high(l["risk_attenuation_correlation"],.30,.05),high(l["post_limit_soc_change"],.01,.0005))
    cooling=min(high(c["minimum_pump_thermal_correlation"],.75,.10),high(c["minimum_flow_heat_correlation"],.85,.20))
    return {"demand":demand,"maldistribution":mal,"regeneration":regen,"low_soc_supervision":low,"cooling_chain":cooling}
def score(e):
    f=e["facts"];rows=f.get("scenario_rows",[]);s=f.get("physical_suite",{});static=f.get("static_audit",{});gate=bool(f.get("score_inputs_valid",False))
    if not gate:return {"A":0,"Q":0,"M":0,"R":0,"D":0},0,list(f.get("gate_reasons",[])),{}
    ps=pair_scores(f.get("causal_pairs",{}))
    n=next(r for r in rows if r["id"]=="nominal")
    A=clip(.35*q(n["delivery_nrmse"],.02,.14)+.20*q(n["peak_temperature_K"],314.5,318.5)+.15*q(n["temperature_spread_K"],2,5)+.15*high(n["minimum_soc"],.16,.08)+.15*high(n["minimum_cell_voltage_V"],3,2.75))
    worst_temp=max(r["peak_temperature_K"] for r in rows);worst_spread=max(r["temperature_spread_K"] for r in rows);worst_soc=min(r["minimum_soc"] for r in rows);worst_voltage=min(r["minimum_cell_voltage_V"] for r in rows)
    rating=max(max(r["pump_command_max"] for r in rows)-1,-min(r["pump_command_min"] for r in rows),(max(r["pump_power_max_W"] for r in rows)-500)/500,-min(r["pump_power_min_W"] for r in rows)/500,(max(r["branch_flow_max_kg_per_s"] for r in rows)-.06)/.06,-min(r["branch_flow_min_kg_per_s"] for r in rows)/.06,0)
    safety=[q(worst_temp,318,321),q(worst_spread,5,8),high(worst_soc,.08,.04),high(worst_voltage,2.75,2.45),q(rating,0,.10)]
    Q=clip(.65*min(safety)+.35*(.20*sum(safety)+q(max(r["limiter_consistency_error"] for r in rows),.04,.28))/2)
    static_score=.55*float(bool(static["dynamic_state_evidence"]))+.45*float(bool(static["output_contract_connected"]) and static["precomputed_direct_output_count"]==0)
    core=[q(s["current_closure_worst"],.005,.12),q(s["voltage_closure_worst"],.001,.03),q(s["pump_auxiliary_closure_worst"],.005,.12),q(s["coulomb_balance_worst"],.025,.16),q(s["thermal_balance_worst"],.06,.35),q(s["coolant_enthalpy_worst"],.01,.15)]
    physical_m=clip(.06*q(s["request_contract_worst"],.005,.06)+.08*core[0]+.07*core[1]+.07*core[2]+.05*q(s["reported_state_worst"],.002,.04)+.10*core[3]+.06*q(s["per_cell_voltage_spread_worst"],.03,.13)+.05*q(s["mixed_geometry_ratio_worst"],.02,.10)+.06*high(s["polarization_drop_min_V"],.006,.0004)+.07*high(s["heat_current_correlation_min"],.85,.25)+.11*core[4]+.08*core[5]+.04*q(s["coolant_passivity_worst"],0,.10)+.05*high(s["pump_thermal_correlation_min"],.75,.10)+.02*high(s["cooling_path_correlation_min"],.85,.20)+.03*static_score)
    physical_m=min(physical_m,.40+.60*min(core))
    # Demand response, maldistribution propagation, and the measured-state
    # cooling loop are independent public mechanism requirements.  Their
    # worst response must dominate M; otherwise nominal conservation metrics
    # can hide a disconnected cooling or maldistribution chain.
    mechanism_pairs=[ps["demand"],ps["maldistribution"],ps["cooling_chain"]]
    causal_m=clip(.75*min(mechanism_pairs)+.25*statistics.mean(mechanism_pairs))
    M=clip(.60*physical_m+.40*causal_m)
    range_ids=set(f["range_scenario_ids"]);rq=[clip(.20*q(r["peak_temperature_K"],318,321)+.16*q(r["temperature_spread_K"],5,8)+.18*high(r["minimum_soc"],.08,.04)+.18*high(r["minimum_cell_voltage_V"],2.75,2.45)+.14*q(r["delivery_nrmse"],.04,.22)+.14*q(r["limiter_consistency_error"],.04,.30)) for r in rows if r["id"] in range_ids]
    # Regeneration and low-SOC current supervision are the two independent
    # dynamic requirements.  Use their worst response plus a small mean term,
    # rather than mixing unrelated nominal/mechanism credit into D.
    R=min(rq)
    dynamic_pairs=[ps["regeneration"],ps["low_soc_supervision"]]
    D=clip(.75*min(dynamic_pairs)+.25*statistics.mean(dynamic_pairs))
    groups={"A":A,"Q":Q,"M":M,"R":R,"D":D};w=e["group_weights"]
    raw_value=100.0*math.prod(groups[k]**float(w[k]) for k in groups)
    findings=[]
    if s["current_closure_worst"]>.12 or s["voltage_closure_worst"]>.03:findings.append("PACK_ELECTRICAL_CORE_PATH_MISSING")
    if s["pump_auxiliary_closure_worst"]>.12:findings.append("PUMP_AUXILIARY_POWER_PATH_MISSING")
    if s["thermal_balance_worst"]>.40 or s["coolant_enthalpy_worst"]>.15:findings.append("THERMAL_COOLANT_CORE_PATH_MISSING")
    missing_core_chains=sum((ps["demand"]<.25,ps["maldistribution"]<.20,ps["regeneration"]<.25,ps["low_soc_supervision"]<.25,ps["cooling_chain"]<.25))
    if s["polarization_drop_min_V"]<.0004:findings.append("FINITE_RESPONSE_POLARIZATION_STATE_MISSING")
    value=raw_value
    reasons=list(findings)
    for key,threshold,label in (("demand",.25,"DEMAND_PAIR_CAUSALITY_FAILED"),("maldistribution",.20,"MALDISTRIBUTION_PAIR_CAUSALITY_FAILED"),("regeneration",.25,"REGENERATION_RESPONSE_FAILED"),("low_soc_supervision",.25,"LOW_SOC_SUPERVISION_FAILED"),("cooling_chain",.25,"CLOSED_LOOP_COOLING_CHAIN_FAILED")):
        if ps[key]<threshold:reasons.append(label)
    return groups,value,reasons,{"pair_scores":ps,"range":rq,"physical_mechanism_score":physical_m,"causal_mechanism_score":causal_m,"dynamic_pair_score":D,"missing_core_chain_count":missing_core_chains,"aggregation":"G*100*A^0.18*Q^0.12*M^0.34*R^0.20*D^0.16","raw_total":raw_value,"findings":findings}
def main():
    a=parser(TASK_ID).parse_args();e=load_evidence(a.evidence,TASK_ID);g,v,reasons,u=score(e)
    r=base_receipt(a.evidence,e,g,v,policy_id="simuverity-101-v1:f90-xbatt-02:scoring",gate_reasons=reasons);r.update({"scenario_rows":e["facts"].get("scenario_rows",[]),"metric_values":{"physical_suite":e["facts"].get("physical_suite",{}),"causal_pairs":e["facts"].get("causal_pairs",{})},"utility_metrics":u});write_receipt(a.output,r)
if __name__=="__main__":main()
