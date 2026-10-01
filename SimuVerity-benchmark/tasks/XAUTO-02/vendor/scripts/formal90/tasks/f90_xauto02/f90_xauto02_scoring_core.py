#!/usr/bin/env python3
"""Pure-offline F90-XAUTO-02 score semantics."""
from __future__ import annotations
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[2]))
from formal90_offline_common import base_receipt,clip,load_evidence,parser,total,write_receipt
TASK_ID="F90-XAUTO-02"
POLICY_ID="simuverity-101-v1:f90-xauto-02:scoring"
def failure_reasons(value):
    if value is None:return []
    if isinstance(value,str):return [value] if value else []
    return [str(reason) for reason in value if str(reason)]
def q(x,g,b):return clip((b-float(x))/(b-g))
def pair_scores(p):
    t=p["target_response"];r=p["road_response"];f=p["fault_response"]
    target=clip(.65*q(1/max(t["speed_separation"],1e-9),1/4,1/.8)+.35*q(1/max(t["torque_separation"],1e-9),1/250,1/35)) if t.get("valid") else 0
    road=clip(.40*q(1/max(r["road_rms_ratio"],1e-9),1/3.5,1/1.4)+.30*q(1/max(r["vertical_response_ratio"],1e-9),1/1.8,1/1.1)+.30*q(1/max(r["normal_response_ratio"],1e-9),1/1.8,1/1.1)) if r.get("valid") else 0
    fault=clip(.30*q(1/max(f["requested_torque_change"],1e-9),1/.18,1/.025)+.25*q(1/max(max(f["delivered_torque_change"],f["speed_effect"]),1e-9),1/.06,1/.008)+.25*q(f["loss_contract_error"],.01,.12)+.20*q(f["recovery_time"],.35,2.4)) if f.get("valid") else 0
    return {"target_response":target,"road_response":road,"fault_response":fault}
def score(e):
    f=e["facts"];rows=f.get("scenario_rows",[]);s=f.get("physical_suite",{});p=f.get("causal_pairs",{});static=f.get("static_audit",{});gate=bool(f.get("score_inputs_valid",False))
    if not gate:return {"A":0,"Q":0,"M":0,"R":0,"D":0},0,failure_reasons(f.get("gate_reasons",[])),{}
    ps=pair_scores(p)
    n=next(r for r in rows if r["id"]=="nominal")
    A=clip(.52*q(n["speed_tracking_nrmse"],.018,.12)+.18*q(n["final_speed_error"],.012,.10)+.18*q(n["body_vertical_accel_rms"],.75,3.4)+.12*q(max(n["pitch_peak"],n["roll_peak"]),.08,.32))
    Q=clip(.32*q(n["lift_fraction"],.002,.18)+.30*q(n["slip_p95"],.10,.45)+.22*q(n["command_ratio_peak"],.96,1.04)+.16*q(n["command_ripple"],.08,.55))
    q_static=.65*float(bool(static["dynamic_state_evidence"]))+.35*float(bool(static["output_contract_connected"]))
    balance={
        "longitudinal":q(s["longitudinal_balance_error"],.035,.28),
        "wheel":q(s["wheel_balance_error"],.06,.38),
        "vertical":q(s["vertical_balance_error"],.06,.38),
    }
    M=clip(.16*balance["longitudinal"]+.17*balance["wheel"]+.13*q(s["slip_kinematic_error"],.012,.10)+.16*balance["vertical"]+.10*q(s["roll_balance_error"],.10,.55)*float(s["roll_positive_inertia"])+.07*q(max(r["speed_error_report_error"] for r in rows),.005,.08)+.06*q(max(r["loss_delivery_error"] for r in rows),.01,.12)+.05*q_static+.05*ps["target_response"]+.05*ps["road_response"])
    # The public task requires the body, wheel and suspension states to evolve
    # causally from forces and moments.  Reserve 20% mechanism credit for
    # connected dynamic-state evidence; the remaining 80% is controlled by the
    # weakest longitudinal, wheel or vertical balance equation.  This avoids a
    # zero group for an incomplete (rather than absent) physical chain while
    # preventing good tracking from averaging away a failed conservation law.
    physical_balance_bottleneck=.20*q_static+.80*min(balance.values())
    M=min(M,.40+.60*ps["target_response"],.40+.60*ps["road_response"],
          physical_balance_bottleneck)
    range_ids=set(f["range_scenario_ids"]);dynamic_ids=set(f["dynamic_scenario_ids"])
    rq=[.42*q(r["speed_tracking_nrmse"],.035,.18)+.18*q(r["lift_fraction"],.01,.25)+.16*q(r["slip_p95"],.16,.60)+.14*q(max(r["pitch_peak"],r["roll_peak"]),.15,.48)+.10*q(r["command_ratio_peak"],.98,1.05) for r in rows if r["id"] in range_ids]
    dq=[.38*q(r["recovery_time"],.35,2.4)+.24*q(r["event_speed_error_peak"],.04,.22)+.20*q(r["loss_delivery_error"],.01,.12)+.18*q(r["loss_indicator_error"],.002,.05) for r in rows if r["id"] in dynamic_ids]
    R_base=clip(min(rq))
    contact_retention=min(
        clip(1.0-float(r["lift_fraction"]))
        for r in rows if r["id"] in range_ids
    )
    # The public contract requires useful tire contact over the declared joint
    # range.  Preserve 40% credit for the other valid range behaviors while the
    # remaining 60% follows the worst measured contact-retention fraction.
    R=min(R_base,.40+.60*contact_retention)
    D=clip(.75*min(dq)+.25*ps["fault_response"]);D=min(D,.35+.65*ps["fault_response"])
    groups={"A":A,"Q":Q,"M":M,"R":R,"D":D};w=e["group_weights"]
    # Match the D16/P7 outer aggregation: a weak required capability is not
    # erased by near-perfect quality or transient groups.
    value=total(True,[groups[k] for k in ("A","Q","M","R","D")],
                [w[k] for k in ("A","Q","M","R","D")])
    reasons=[]
    if s["longitudinal_balance_error"]>.28:reasons.append("LONGITUDINAL_FORCE_BALANCE_FAILED")
    if s["wheel_balance_error"]>.38:reasons.append("WHEEL_TORQUE_BALANCE_FAILED")
    if s["vertical_balance_error"]>.38:reasons.append("VERTICAL_FORCE_BALANCE_FAILED")
    if ps["target_response"]<.25:reasons.append("CLOSED_LOOP_TARGET_RESPONSE_FAILED")
    if ps["road_response"]<.25:reasons.append("ROAD_TO_SUSPENSION_CAUSAL_RESPONSE_FAILED")
    if ps["fault_response"]<.20:reasons.append("ACTUATOR_LOSS_CAUSAL_RESPONSE_FAILED")
    return groups,value,reasons,{"pair_scores":ps,"balance_scores":balance,
                                "physical_balance_bottleneck":physical_balance_bottleneck,
                                "range":rq,"range_base":R_base,
                                "tire_contact_range_bottleneck":{"contact_retention":contact_retention,"ceiling":.40+.60*contact_retention},
                                "dynamic":dq,
                                "aggregation":{"within_group":"dedicated weighted arithmetic means with causal ceilings","across_groups":"weighted geometric mean"}}
def main():
    a=parser(TASK_ID).parse_args();e=load_evidence(a.evidence,TASK_ID);g,v,reasons,d=score(e)
    r=base_receipt(a.evidence,e,g,v,policy_id=POLICY_ID,gate_reasons=reasons);r.update({"scenarios":e["facts"].get("scenario_rows",[]),"metric_values":{"physical_suite":e["facts"].get("physical_suite",{}),"causal_pairs":e["facts"].get("causal_pairs",{})},"utility_metrics":d});write_receipt(a.output,r)
if __name__=="__main__":main()
