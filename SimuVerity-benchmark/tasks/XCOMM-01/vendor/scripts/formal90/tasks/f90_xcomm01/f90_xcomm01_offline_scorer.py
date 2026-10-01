#!/usr/bin/env python3
"""Post-lock Python reproduction of XP9 XCOMM01 score semantics."""
from __future__ import annotations
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[2]))
from formal90_offline_common import base_receipt,group,load_evidence,parser,tail,total,utility,weights,write_receipt
TASK_ID="F90-XCOMM-01"
def score(e):
    f=e["facts"];rows=f.get("scenario_rows",[]);s=f.get("suite_metrics",{});rcs=f.get("rcs_probe",{});probe=f.get("input_probe",{});report=f.get("report_consistency",{});gate=bool(f.get("score_inputs_valid",False))
    if rows:
        n=rows[0]
        A=group([utility(n["two_target_report_fraction"],[0,.20,.50,.80,.98,1],[0,.18,.48,.76,.96,1]),
                 utility(n["range_error"],[0,.18,.45,1.2,3.5,8],[1,1,.94,.72,.25,0]),
                 utility(n["velocity_error"],[0,.10,.30,.8,2.4,6],[1,1,.94,.72,.25,0])],[.24,.42,.34])
        if n["two_target_report_fraction"]<=0:A=0
        q_variation=group([utility(report["confidence_variation_worst"],[0,.002,.01,.04,.15,.50],[0,.15,.45,.72,.94,1]),
                           utility(report["lock_variation_worst"],[0,.002,.01,.04,.15,.50],[0,.15,.45,.72,.94,1]),
                           utility(report["false_alarm_variation_worst"],[0,.002,.01,.04,.12,.40],[0,.15,.45,.72,.94,1])],[.38,.32,.30])
        Q=group([utility(n["impairment_ratio_error"],[0,.08,.18,.38,.75,1.4],[1,1,.94,.72,.25,0]),
                 utility(report["confidence_order_typical"],[0,.20,.40,.50,.65,.80,1],[0,.12,.45,.68,.90,.98,1]),
                 utility(report["lock_order_typical"],[0,.20,.40,.50,.65,.80,1],[0,.12,.45,.68,.90,.98,1]),
                 utility(report["false_alarm_order_typical"],[0,.20,.40,.50,.65,.80,1],[0,.12,.45,.68,.90,.98,1]),q_variation],[.28,.20,.18,.16,.18])
        q_target=utility(n["target_spectral_prominence"],[0,2,5,15,50,200],[0,.18,.48,.76,.94,1])
        q_iqr=utility(n["iq_detection_range_error"],[0,.25,.60,1.5,4,10],[1,1,.94,.72,.25,0])
        q_iqv=utility(n["iq_detection_velocity_error"],[0,.15,.40,1.0,3,7],[1,1,.94,.72,.25,0])
        q_input=group([utility(max(probe["snr_log_response"],0),[0,.01,.035,.08,.16,.30],[.15,.30,.52,.75,.93,1]),
                       utility(max(probe["clutter_log_response"],0),[0,.01,.035,.08,.16,.30],[.15,.30,.52,.75,.93,1])],[.50,.50])
        M=group([q_target,
                 utility(n["order_violation"],[0,.001,.01,.04,.15,.5],[1,1,.94,.74,.30,0]),
                 utility(n["interference_detection"],[0,.20,.50,.75,.92,1],[0,.15,.45,.72,.93,1]),
                 utility(n["event_spectral_evidence"],[0,.03,.08,.16,.28,.45],[0,.18,.48,.76,.94,1]),q_iqr,q_iqv,
                 utility(n["status_spectral_alignment"],[0,.25,.50,.72,.90,1],[0,.15,.45,.72,.93,1]),
                 utility(n["parity_leakage"],[0,.02,.06,.15,.35,.70],[1,1,.94,.72,.25,0]),
                 utility(max(rcs["min_log_response"],0),[0,.01,.035,.08,.16,.30],[.15,.30,.52,.75,.93,1]),q_input],
                [.084,.049,.063,.063,.161,.154,.126,.10,.10,.10])
        waveform=q_target>0;reported=n["two_target_report_fraction"]>0;aligned=q_iqr>0 or q_iqv>0
        if not waveform and not reported:M=0
        elif not waveform or not reported or not aligned:M=min(M,.25)
    else:A=Q=M=0
    prefixes=("rcs_","snr_","clutter_","interference_probe_")
    primary=[r for r in rows if not str(r.get("scenario","")).startswith(prefixes)]
    rq=[];dq=[]
    for r in primary:
        rq.append(group([utility(r["range_error"],[0,.30,.75,1.8,5,11],[1,1,.93,.68,.22,0]),
                         utility(r["velocity_error"],[0,.18,.50,1.3,3.8,8],[1,1,.93,.68,.22,0]),
                         utility(r["iq_detection_range_error"],[0,.35,.85,2.0,5,12],[1,1,.93,.68,.22,0]),
                         utility(r["iq_detection_velocity_error"],[0,.22,.55,1.4,3.8,9],[1,1,.93,.68,.22,0])],[.28,.25,.25,.22]))
        continuity=group([utility(r["event_range_error"],[0,.35,.85,2,5,12],[1,1,.93,.68,.22,0]),
                          utility(r["event_velocity_error"],[0,.22,.55,1.4,3.8,9],[1,1,.93,.68,.22,0])],[.55,.45])
        response=max(utility(r["event_signature"],[0,.05,.12,.25,.45,.75],[.18,.38,.68,.92,1,1]),continuity)
        dq.append(group([utility(r["recovery_time"],[0,.004,.010,.022,.045,.09],[1,1,.93,.70,.25,0]),response,
                         utility(r["interference_detection"],[0,.20,.50,.75,.92,1],[0,.15,.45,.72,.93,1]),
                         utility(r["interference_false_positive"],[0,.005,.02,.06,.16,.40],[1,1,.93,.70,.25,0]),
                         utility(r["event_spectral_evidence"],[0,.03,.08,.16,.28,.45],[0,.18,.48,.76,.94,1]),
                         utility(r["event_ratio_error"],[0,.10,.25,.50,.90,1.5],[1,1,.94,.72,.25,0]),
                         utility(r["status_spectral_alignment"],[0,.25,.50,.72,.90,1],[0,.15,.45,.72,.93,1])],[.25,.15,.10,.10,.12,.13,.15]))
    if rq:
        R=tail(rq)
        suite_q=group([utility(s["event_monotonic_fraction"],[0,.25,.50,.75,.99,1],[0,.12,.42,.72,.94,1]),
                       utility(s["event_scale_residual"],[0,.08,.18,.35,.60,1],[1,1,.94,.72,.25,0])],[.55,.45])
        D=group([tail(dq),suite_q],[.75,.25])
        if not any(r["event_spectral_evidence"]>0 for r in primary):D=0
    else:R=D=0
    groups={"A":A,"Q":Q,"M":M,"R":R,"D":D}
    return groups,total(gate,[A,Q,M,R,D],weights(e)),{"range":rq,"dynamic":dq}
def main():
    a=parser(TASK_ID).parse_args();e=load_evidence(a.evidence,TASK_ID);g,v,u=score(e)
    r=base_receipt(a.evidence,e,g,v,policy_id="simuverity-101-v1:p9-xcomm01:scoring");r.update({"scenario_rows":e["facts"].get("scenario_rows",[]),"cross_scenario_metrics":e["facts"].get("suite_metrics",{}),"utility_metrics":u});write_receipt(a.output,r)
if __name__=="__main__":main()
