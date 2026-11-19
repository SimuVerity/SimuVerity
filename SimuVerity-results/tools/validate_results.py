"""Validate SimuVerity experiment summaries and result tables."""
from pathlib import Path
from decimal import Decimal, InvalidOperation, ROUND_HALF_UP
import csv
import json
import re
import sys

ROOT=Path(__file__).resolve().parents[1]
REPEATS=['run1','run2','run3']
COUNT_KEYS=['scored_count','protocol_zero_count','delivered_count','native_executable_count','g_pass_count']
IDENTITY=['schema_version','run_id','benchmark_release','taskset_id','model','harness','condition','task_count']
MAIN=['opus-4-8-claude-code-101','gpt-5-5-codex-101','deepseek-v4-pro-claude-code-101',
      'qwen3-8-max-claude-code-101','glm-5-3-flash-claude-code-101','qwen3-8-27b-fp8-claude-code-101']
ABLATION=['opus-4-8-claude-code-'+c+'-10' for c in ['full-mcp','no-simulation','batch-only']]
Q=Decimal('.000001')
LEADERBOARD_FIELDS=['run_id','model','harness','benchmark_release','taskset_id','task_count','repeat_count','result_count',
                    'scored_count','protocol_zero_count','score_sum','score_mean','delivered_count','native_executable_count','g_pass_count']
ABLATION_FIELDS=['condition','run_id','model','harness','taskset_id','task_count','repeat_count','result_count',
                 'scored_count','protocol_zero_count','score_sum','score_mean','delta_vs_full_mean',
                 'delivered_count','native_executable_count','g_pass_count']


def validate_repository(root):
    root=Path(root);errors=[];parents={}
    def require(ok,context):
        if not ok:errors.append(context)
    def load(path):
        try:return json.loads(path.read_text(encoding='utf-8-sig'))
        except (OSError,ValueError) as exc:
            errors.append(f'{path.relative_to(root)}: {exc}');return None
    def table(path):
        try:
            with path.open(encoding='utf-8-sig',newline='') as f:return list(csv.DictReader(f))
        except (OSError,ValueError) as exc:
            errors.append(f'{path.relative_to(root)}: {exc}');return []
    def decimal(value,label):
        if not isinstance(value,str) or not re.fullmatch(r'\d+\.\d{6}',value):
            errors.append(f'{label}: expected a nonnegative six-decimal score');return None
        try:return Decimal(value)
        except InvalidOperation:errors.append(f'{label}: invalid decimal');return None
    def integer(value):return type(value) is int and value>=0

    for p in root.rglob('*'):
        if not p.is_file():continue
        if p.name in ['scores.csv','comparison.csv']:
            errors.append(f'{p.relative_to(root)}: unexpected result file')
        if p.suffix.lower()=='.csv':
            try:
                with p.open(encoding='utf-8-sig',newline='') as f:header=next(csv.reader(f),[])
                if 'task_id' in header and set(header)-{'task_id','collection'}:
                    errors.append(f'{p.relative_to(root)}: unsupported CSV columns')
                if 'candidate_id' in header:
                    errors.append(f'{p.relative_to(root)}: unsupported CSV schema')
            except (OSError,ValueError,UnicodeError) as exc:errors.append(str(exc))
    expected=set(MAIN+ABLATION)
    actual={p.name for p in (root/'runs').iterdir() if p.is_dir()} if (root/'runs').exists() else set()
    require(actual==expected,'expected exactly six complete and three ablation experiment directories')
    tasksets={}
    for name,n in [('simuverity-101-v1',101),('simuverity-mcp-ablation-10-v1',10)]:
        rr=table(root/'tasksets'/f'{name}.csv')
        require(len(rr)==n and len({r.get('task_id') for r in rr})==n,f'{name}: invalid task membership')
        tasksets[name]={r.get('task_id') for r in rr}
    require(tasksets['simuverity-mcp-ablation-10-v1']<=tasksets['simuverity-101-v1'],'ablation tasks must be in complete task set')

    for parent in MAIN+ABLATION:
        summaries=[]
        for repeat in [None]+REPEATS:
            folder=root/'runs'/parent
            if repeat:folder/=repeat
            meta=load(folder/'run.json');summary=load(folder/'summary.json')
            if meta is None or summary is None:continue
            label=str(folder.relative_to(root))
            meta_keys=set(IDENTITY+['summary_file']+(['parent_run_id','repeat_id'] if repeat else ['aggregation','repeat_count','repeat_ids']))
            summary_keys=set(IDENTITY+COUNT_KEYS+['score_sum','score_mean']+(['parent_run_id','repeat_id'] if repeat else ['repeat_count','result_count']))
            require(set(meta)==meta_keys,f'{label}: metadata fields mismatch')
            require(set(summary)==summary_keys,f'{label}: summary fields mismatch')
            require(meta.get('summary_file')=='summary.json',f'{label}: summary filename mismatch')
            require(all(meta.get(k)==summary.get(k) for k in IDENTITY),f'{label}: identity differs between metadata and summary')
            n=101 if parent in MAIN else 10
            require(summary.get('task_count')==n,f'{label}: wrong task count')
            require(summary.get('run_id')==parent+('-'+repeat if repeat else ''),f'{label}: wrong run identity')
            require(summary.get('schema_version')=='1.0',f'{label}: unsupported summary version')
            require(summary.get('benchmark_release')=='simuverity-101-v1',f'{label}: wrong benchmark release')
            ts='simuverity-101-v1' if parent in MAIN else 'simuverity-mcp-ablation-10-v1'
            require(summary.get('taskset_id')==ts,f'{label}: wrong task set')
            if repeat:
                require(all(o.get('parent_run_id')==parent and o.get('repeat_id')==repeat for o in [meta,summary]),f'{label}: repeat identity mismatch')
            else:
                require(meta.get('repeat_ids')==REPEATS and meta.get('repeat_count')==3 and meta.get('aggregation')=='arithmetic_mean',f'{label}: invalid aggregate metadata')
                require(summary.get('repeat_count')==3 and summary.get('result_count')==3*n,f'{label}: invalid result count')
            limit=n if repeat else 3*n
            counts=[summary.get(k) for k in COUNT_KEYS]
            valid_counts=all(integer(x) and x<=limit for x in counts)
            require(valid_counts,f'{label}: count outside permitted range')
            if valid_counts:
                require(summary['g_pass_count']<=summary['native_executable_count']<=summary['delivered_count'],f'{label}: prerequisite counts are inconsistent')
            total=decimal(summary.get('score_sum'),label+'/score_sum')
            mean=decimal(summary.get('score_mean'),label+'/score_mean')
            if total is not None and mean is not None:
                require(0<=mean<=100 and 0<=total<=100*n,f'{label}: score range invalid')
                require((total/n).quantize(Q,rounding=ROUND_HALF_UP)==mean,f'{label}: sum and mean differ')
            if repeat:summaries.append(summary)
            else:parents[parent]=summary
        if parent in parents and len(summaries)==3:
            p=parents[parent]
            for key in COUNT_KEYS:
                if all(integer(s.get(key)) for s in summaries+[p]):
                    require(sum(s[key] for s in summaries)==p[key],f'{parent}: {key} does not sum across repeats')
            sums=[decimal(s.get('score_sum'),parent+'/repeat_sum') for s in summaries]
            ps=decimal(p.get('score_sum'),parent+'/parent_sum')
            if ps is not None and all(x is not None for x in sums):
                # Parent totals sum rounded per-task means, whereas repeat
                # totals are rounded first. This is the exact rounding budget.
                tolerance=Decimal(p['task_count'])*Decimal('.0000005')+Decimal('.0000005')
                require(abs(sum(sums)/3-ps)<=tolerance,f'{parent}: aggregate score differs from repeats')
    for filename,order in [('leaderboard.csv',MAIN),('ablations/mcp-10/summary.csv',ABLATION)]:
        rr=table(root/filename)
        fields=LEADERBOARD_FIELDS if filename=='leaderboard.csv' else ABLATION_FIELDS
        try:
            with (root/filename).open(encoding='utf-8-sig',newline='') as f:header=next(csv.reader(f),[])
            require(header==fields,f'{filename}: expected complete aggregate header')
        except (OSError,ValueError) as exc:errors.append(str(exc))
        require([r.get('run_id') for r in rr]==order,f'{filename}: row order or experiment set differs')
        for r in rr:
            s=parents.get(r.get('run_id'))
            if not s:continue
            for key,value in r.items():
                if key=='delta_vs_full_mean':continue
                require(key in s and str(s.get(key))==value,f'{filename}/{r.get("run_id")}: {key} differs from summary')
            if 'delta_vs_full_mean' in r and ABLATION[0] in parents:
                cur=decimal(r.get('score_mean'),filename);full=decimal(parents[ABLATION[0]]['score_mean'],filename)
                try:delta=Decimal(r['delta_vs_full_mean'])
                except InvalidOperation:errors.append(filename+': invalid ablation delta');continue
                if cur is not None and full is not None:
                    require(delta==cur-full,f'{filename}: ablation difference mismatch')
    return errors


if __name__=='__main__':
    failures=validate_repository(ROOT)
    if failures:
        print('\n'.join(failures),file=sys.stderr);raise SystemExit(1)
    print('Validated 9 experiments, 27 repeats, leaderboard and ablation results.')
