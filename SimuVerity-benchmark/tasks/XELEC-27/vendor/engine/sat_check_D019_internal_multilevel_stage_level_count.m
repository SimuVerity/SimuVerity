function report = sat_check_D019_internal_multilevel_stage_level_count( ...
    modelName,spec,scenarioId,simOut,signals,baseReports,state) %#ok<INUSD>
%SAT_CHECK_D019_INTERNAL_MULTILEVEL_STAGE_LEVEL_COUNT
% D019-owned behavior check at the aggregate bridge-side, pre-filter node.

if string(scenarioId)~="nominal",report=struct([]);return;end
report=base_report(scenarioId);
check=check_spec(spec);
if isempty(check)
    report.detail="TASK_CHECK_SPEC_MISSING"; return;
end
if ~isstruct(state)||~isfield(state,'prepared')||~logical(state.prepared)
    report.detail="INTERNAL_PROBE_NOT_PREPARED"; return;
end
if ~isfield(state,'valid')||~logical(state.valid)
    report.detail="PROBE_INVALID:"+getstr(state,'detail','UNKNOWN'); return;
end
report.evaluated=true;
ev=getstruct(state,'evidence');
if ~getbool(ev,'aggregate_node_valid',false)
    report.detail="AMBIGUOUS_OR_NON_AGGREGATE_PROBE"; return;
end
role=getstr(ev,'signal_role','');
if role~="aggregate_pre_filter"
    if contains(lower(role),"public")||contains(lower(role),"post_filter")
        report.detail="PUBLIC_OR_POST_FILTER_PROBE_FORBIDDEN";
    else
        report.detail="AMBIGUOUS_OR_NON_AGGREGATE_PROBE";
    end
    return;
end

[t,y,got,why]=probe_series(state,simOut);
if ~got
    report.evaluated=false; report.detail="PROBE_SIGNAL_MISSING:"+why; return;
end
report.evaluated=true;
f=getnum(check,'fundamental_hz',50);
cycles=getnum(check,'analysis_cycles',3);
duration=cycles/f;
if numel(t)<3||t(end)-t(1)+time_eps(t)<duration
    report.detail="INSUFFICIENT_COMPLETE_CYCLES"; return;
end
start=t(end)-duration;
ix=t>=start-time_eps(t); t=t(ix); y=y(ix);
if numel(t)<3||t(end)-t(1)+time_eps(t)<duration
    report.detail="INSUFFICIENT_COMPLETE_CYCLES"; return;
end

[levels,occupancies,coverage,valid,detail]=detect_levels(y,check);
report.valid=logical(valid);
minLevels=getnum(check,'min_effective_levels',3);
report.ok=logical(valid&&numel(levels)>=minLevels);
report.score=double(report.ok);
report.evidence=struct('aggregate_probe',true,'signal_role',role, ...
    'measurement_block',getstr(ev,'measurement_block',''), ...
    'probe_variable',getstr(ev,'probe_variable',''), ...
    'analysis_cycles',cycles,'fundamental_hz',f, ...
    'sample_count',numel(y),'effective_level_count',numel(levels), ...
    'level_centers',levels,'level_occupancies',occupancies, ...
    'plateau_coverage',coverage, ...
    'min_effective_levels',minLevels, ...
    'min_plateau_coverage',getnum(check,'min_plateau_coverage',0.45), ...
    'min_level_separation_frac',getnum(check,'min_level_separation_frac',0.08), ...
    'level_tolerance_frac',getnum(check,'level_tolerance_frac',0.035), ...
    'min_level_occupancy_frac',getnum(check,'min_level_occupancy_frac',0.01));
if ~valid
    report.detail=string(detail);
elseif report.ok
    report.detail="OK";
else
    report.detail="EFFECTIVE_LEVEL_COUNT_BELOW_MINIMUM";
end
end

function [levels,occupancies,coverage,valid,detail]=detect_levels(y,cfg)
levels=[]; occupancies=[]; coverage=0; valid=false; detail="INVALID_PROBE_SIGNAL";
y=double(y(:));
if numel(y)<16||any(~isfinite(y)), return; end
ys=sort(y); n=numel(ys);
lo=ys(max(1,ceil(0.002*n))); hi=ys(min(n,floor(0.998*n)));
span=hi-lo;
if ~isfinite(span)||span<=max(1,max(abs([lo hi])))*1e-12
    detail="DEGENERATE_LEVEL_RANGE"; return;
end
tol=getnum(cfg,'level_tolerance_frac',0.035)*span;
stable=abs(diff(y))<=tol;
plateau=false(n,1);
plateau(1:end-1)=plateau(1:end-1)|stable;
plateau(2:end)=plateau(2:end)|stable;
coverage=mean(plateau);
minCoverage=getnum(cfg,'min_plateau_coverage',0.45);
if coverage+64*eps(max(1,coverage))<minCoverage
    detail="INSUFFICIENT_PLATEAU_COVERAGE"; return;
end
pv=sort(y(plateau));
if isempty(pv), detail="NO_PLATEAU_SAMPLES"; return; end
minSep=getnum(cfg,'min_level_separation_frac',0.08)*span;
starts=[1;find(diff(pv)+64*eps(max(1,span))>=minSep)+1];
stops=[starts(2:end)-1;numel(pv)];
centers=zeros(1,numel(starts)); counts=zeros(1,numel(starts));
for i=1:numel(starts)
    v=pv(starts(i):stops(i)); centers(i)=median(v); counts(i)=numel(v);
end
occ=counts/n;
minOcc=getnum(cfg,'min_level_occupancy_frac',0.01);
keep=occ+64*eps(max(1,minOcc))>=minOcc;
levels=centers(keep); occupancies=occ(keep);
valid=true; detail="OK";
end

function [t,y,ok,why]=probe_series(state,simOut)
t=[];y=[];ok=false;why="EMPTY";
x=[];
if isfield(state,'probe_signals')&&~isempty(state.probe_signals)
    x=state.probe_signals;
end
if isstruct(x)&&isfield(x,'variable_name')
    x=simulation_value(simOut,string(x.variable_name));
elseif isstring(x)||ischar(x)
    x=simulation_value(simOut,string(x));
end
if isempty(x)&&isfield(state,'evidence')&&isfield(state.evidence,'probe_variable')
    x=simulation_value(simOut,string(state.evidence.probe_variable));
end
if isa(x,'timeseries')
    t=double(x.Time(:)); y=double(x.Data);
elseif isstruct(x)&&isfield(x,'t')&&isfield(x,'Y')
    t=double(x.t(:)); y=double(x.Y);
elseif isstruct(x)&&isfield(x,'time')&&isfield(x,'signals')&&isfield(x.signals,'values')
    t=double(x.time(:)); y=double(x.signals.values);
end
if isempty(t)||isempty(y), why="UNSUPPORTED_SIGNAL_FORMAT"; return; end
if size(y,1)~=numel(t)&&size(y,2)==numel(t), y=y.'; end
if size(y,1)~=numel(t)||size(y,2)~=1, why="PROBE_MUST_BE_SCALAR"; return; end
ok=all(isfinite(t))&&all(isfinite(y)); if ~ok, why="NONFINITE_PROBE"; end
end

function x=simulation_value(simOut,name)
x=[]; if isempty(simOut), return; end
try
    if isa(simOut,'Simulink.SimulationOutput'), x=simOut.get(char(name));
    elseif isstruct(simOut)&&isfield(simOut,matlab.lang.makeValidName(char(name)))
        x=simOut.(matlab.lang.makeValidName(char(name)));
    end
catch, x=[]; end
end

function c=check_spec(spec)
c=[]; if ~isstruct(spec)||~isfield(spec,'task_specific_checks'), return; end
rows=spec.task_specific_checks; if ~iscell(rows), rows=num2cell(rows); end
for i=1:numel(rows)
    if isfield(rows{i},'id')&&string(rows{i}.id)=="D019.internal_multilevel_stage_level_count"
        c=rows{i}; return;
    end
end
end

function r=base_report(scenario)
r=struct('task',"D019",'id',"D019.internal_multilevel_stage_level_count", ...
    'kind',"task_specific",'semantic_kind',"band",'scenario',string(scenario), ...
    'layer',"nominal",'evaluated',false,'mandatory',true,'ok',false, ...
    'valid',false,'score',0,'detail',"UNINITIALIZED",'evidence',struct());
end
function v=getnum(s,f,d),v=d;if isstruct(s)&&isfield(s,f)&&isnumeric(s.(f))&&isscalar(s.(f))&&isfinite(s.(f)),v=double(s.(f));end,end
function v=getbool(s,f,d),v=d;if isstruct(s)&&isfield(s,f)&&isscalar(s.(f)),v=logical(s.(f));end,end
function v=getstr(s,f,d),v=string(d);if isstruct(s)&&isfield(s,f)&&~isempty(s.(f)),v=string(s.(f));end,end
function v=getstruct(s,f),v=struct();if isstruct(s)&&isfield(s,f)&&isstruct(s.(f)),v=s.(f);end,end
function e=time_eps(t), e=max(1,abs(t(end)))*256*eps; end
