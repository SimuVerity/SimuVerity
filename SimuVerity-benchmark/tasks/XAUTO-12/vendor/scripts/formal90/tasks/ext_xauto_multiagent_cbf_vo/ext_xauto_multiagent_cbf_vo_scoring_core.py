"""Implementation-neutral, partial-output scorer for EXT-XAUTO-MULTIAGENT-CBF-VO."""
from __future__ import annotations
import argparse, copy, json, math, sys
from pathlib import Path
from typing import Any
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "shared"))
from ext_scoring_common import strict_weighted_geometric

TASK_ID = "EXT-XAUTO-MULTIAGENT-CBF-VO"
WEIGHTS = {"A": .24, "Q": .10, "M": .24, "C": .22, "R": .12, "D": .08}
EXPECTED = 4

def low(x: Any, full: float, zero: float) -> float:
    try: x=float(x)
    except (TypeError, ValueError): return 0.0
    return 0.0 if not math.isfinite(x) else max(0., min(1., (zero-x)/(zero-full)))

def high(x: Any, zero: float, full: float) -> float:
    try: x=float(x)
    except (TypeError, ValueError): return 0.0
    return 0.0 if not math.isfinite(x) else max(0., min(1., (x-zero)/(full-zero)))

def avg(v: list[float]) -> float: return sum(v)/len(v) if v else 0.0
def state_available(s: dict[str,Any]) -> bool: return bool(s.get("state_available", s.get("state_width") == 40)) and s.get("state_width") == 40
def control_available(s: dict[str,Any]) -> bool: return bool(s.get("control_available", s.get("control_width") == 32)) and s.get("control_width") == 32
def sim_valid(s: dict[str,Any]) -> bool: return bool(s.get("simulation_valid", s.get("valid", False)))

def navigation(s: dict[str,Any]) -> float:
    if not state_available(s): return 0.0
    return avg([high(s.get("mean_active_progress"),.18,.5), high(s.get("worst_active_progress"),.05,.35), low(s.get("mean_terminal_goal_error_m"),14,32)])

def safety(s: dict[str,Any]) -> float:
    if not state_available(s): return 0.0
    return avg([high(s.get("minimum_separation_margin_m"),-.15,.25), low(s.get("collision_fraction"),0,.02), low(s.get("kinematic_rmse_mps"),.08,.8)])

def replay_utility(ss: list[dict[str,Any]]) -> float:
    if not all(state_available(s) for s in ss): return 0.0
    ratios=[]
    for i in range(len(ss)):
        for j in range(i+1,len(ss)):
            mi=ss[i].get("mission_signature",[]); mj=ss[j].get("mission_signature",[])
            ri=ss[i].get("response_signature",[]); rj=ss[j].get("response_signature",[])
            if not (len(mi)==len(mj)==len(ri)==len(rj)==32): return 0.0
            md=math.sqrt(sum((float(a)-float(b))**2 for a,b in zip(mi,mj)))
            if md>1e-9: ratios.append(math.sqrt(sum((float(a)-float(b))**2 for a,b in zip(ri,rj)))/md)
    return high(min(ratios) if ratios else 0.,.005,.12)

def score(e: dict[str,Any]) -> dict[str,Any]:
    ss=e.get("scenarios",[])
    checks={
        "schema": e.get("schema") in {"simuverity.ext-xauto-multiagent-cbf-vo-evidence.v1","simuverity.ext-xauto-multiagent-cbf-vo-evidence.v1"},
        "task": e.get("task_id")==TASK_ID,
        "lifecycle": all(bool(e.get(k)) for k in ("load_ok","update_ok","compile_ok")),
        "scenario_count": len(ss)==EXPECTED,
        "scenario_simulation_validity": len(ss)==EXPECTED and all(sim_valid(s) for s in ss),
    }
    gate=1.0 if all(checks.values()) else 0.0
    if not ss:
        groups={k:0. for k in WEIGHTS}
    else:
        nav=[navigation(s) for s in ss]; safe=[safety(s) for s in ss]
        state_q=[1. if state_available(s) and s.get("finite") and s.get("coverage_fraction",0)>=.999 else 0. for s in ss]
        control_q=[1. if control_available(s) and s.get("finite") and s.get("coverage_fraction",0)>=.999 else 0. for s in ss]
        q=[avg([state_q[i],control_q[i]]) for i in range(len(ss))]
        control_guard=min(high(s.get("control_rms"),1e-5,.05) if control_available(s) else 0.0 for s in ss)
        copy_guard=min(low(s.get("goal_copy_fraction",1),.01,.8) if state_available(s) else 0.0 for s in ss)
        coupled=avg([high(s.get("avoidance_modulation"),1e-5,.03) if state_available(s) and control_available(s) else 0.0 for s in ss])
        c=min(copy_guard,replay_utility(ss),avg([coupled,control_guard]))
        m=min(avg(safe),control_guard)
        r=min(avg([nav[i],safe[i]]) for i in range(len(ss)))
        dyn=[avg([
            low(s.get("control_bound_violation_fraction"),0,.03) if control_available(s) else 0.0,
            low(s.get("solver_exit_fraction"),0,.03) if control_available(s) else 0.0,
            low(s.get("passive_motion_rmse_m"),.03,.5) if state_available(s) else 0.0,
            low(s.get("passive_control_rms"),1e-6,.02) if control_available(s) else 0.0,
        ]) for s in ss]
        groups={"A":avg(nav),"Q":min(q),"M":m,"C":c,"R":r,"D":min(dyn)}
    total=strict_weighted_geometric(gate,groups,WEIGHTS)
    return {
        "schema":"simuverity.ext-score.v1","task_id":TASK_ID,"evaluation_policy_id":"simuverity-101-v1:ext-xauto-multiagent-cbf-vo:scoring",
        "G":100*gate,"groups":{k:round(100*v,6) for k,v in groups.items()},"weights":WEIGHTS,
        "total_raw":round(total,6),"raw_threshold":90,"normalize_threshold_to_100":False,
        "aggregation":"G_times_strict_weighted_geometric_mean","epsilon_floor":False,"post_total_cap":False,
        "gate_checks":checks,"partial_output_policy":"missing public channels zero only metrics that require them",
        "scenario_results":[{"id":s.get("id"),"simulation_valid":sim_valid(s),"state_available":state_available(s),"control_available":control_available(s),"navigation":round(100*navigation(s),6),"safety":round(100*safety(s),6)} for s in ss]
    }

def shortcut_sanity(e: dict[str,Any]) -> dict[str,Any]:
    base=score(e); checks={}
    missing=copy.deepcopy(e); missing["scenarios"][0].update(control_available=False,control_width=0)
    partial=score(missing); checks["missing_control_preserves_gate_but_zeros_control_mechanism"]=(partial["G"]==100 and partial["groups"]["M"]==0 and partial["total_raw"]==0)
    copied=copy.deepcopy(e)
    for s in copied["scenarios"]: s.update(goal_copy_fraction=1.0,avoidance_modulation=0.0)
    cs=score(copied); checks["copied_goal_loses_score"]=cs["total_raw"]<base["total_raw"]
    replay=copy.deepcopy(e)
    if replay.get("scenarios"):
        sig=replay["scenarios"][0].get("response_signature",[])
        for s in replay["scenarios"]: s["response_signature"]=sig
    rs=score(replay); checks["single_replay_loses_score"]=rs["total_raw"]<base["total_raw"]
    return {"task_id":TASK_ID,"checks":checks,"pass":all(checks.values())}

def main() -> int:
    p=argparse.ArgumentParser(); p.add_argument("--evidence",required=True,type=Path); p.add_argument("--output",required=True,type=Path); p.add_argument("--shortcut-output",type=Path); a=p.parse_args()
    e=json.loads(a.evidence.read_text(encoding="utf-8")); r=score(e); a.output.parent.mkdir(parents=True,exist_ok=True); a.output.write_text(json.dumps(r,indent=2)+"\n",encoding="utf-8")
    if a.shortcut_output: a.shortcut_output.write_text(json.dumps(shortcut_sanity(e),indent=2)+"\n",encoding="utf-8")
    return 0
if __name__=="__main__": raise SystemExit(main())
