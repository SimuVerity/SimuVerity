function report=sat_check_D026_split_dc_balance(modelName,spec,scenarioId,simOut,signals,baseReports,state) %#ok<INUSD>
%SAT_CHECK_D026_SPLIT_DC_BALANCE D026-owned active split-source check.
% The two sources are selected from the physical source->switch->load path;
% unrelated Vdc_half bindings elsewhere cannot satisfy this report.

report=base_report(scenarioId);cfg=find_check(spec,report.id);
if ~task_identity_ok(spec,scenarioId)
    report.detail="TASK_OR_SCENARIO_IDENTITY_MISMATCH";return;
end
if isempty(cfg),report.detail="TASK_CHECK_SPEC_MISSING";return;end
report.evaluated=true;
fixture=semantic_fixture(modelName);
if ~isempty(fixture)
    report=evaluate_fixture(report,fixture,cfg);return;
end
try,G=sat_model_graph(modelName);catch ex
    report.detail="GRAPH_BUILD_ERROR:"+string(ex.identifier);return;
end
[sources,pathEvidence]=active_sources(G);
if numel(sources)~=2
    report.valid=false;report.detail="ACTIVE_SPLIT_SOURCE_CARDINALITY";
    report.evidence=struct('active_source_count',numel(sources), ...
        'active_sources',sources,'path_evidence',{pathEvidence});return;
end

defaultValue=input_default(spec,"Vdc_half",100);
rows=struct('block',{},'parameter',{},'expression',{},'value',{}, ...
    'depends_on_Vdc_half',{},'proportional_binding',{},'detail',{});
for i=1:numel(sources)
    rows(end+1)=resolve_source(sources(i),defaultValue); %#ok<AGROW>
end
owned=all([rows.depends_on_Vdc_half])&&all([rows.proportional_binding]);
values=abs(double([rows.value]));
den=max(mean(values),eps);mismatch=abs(values(1)-values(2))/den;
limit=getnum(cfg,'max_relative_mismatch',1e-6);
report.valid=all(isfinite(values))&&isfinite(mismatch)&&limit>=0;
report.ok=logical(report.valid&&owned&&mismatch<=limit+64*eps(max(1,limit)));
report.score=double(report.ok);
report.evidence=struct('active_source_count',2,'active_sources',sources, ...
    'source_paths',{pathEvidence},'bindings',rows,'resolved_magnitudes',values, ...
    'relative_mismatch',mismatch,'max_relative_mismatch',limit, ...
    'ownership_ok',logical(owned));
if ~report.valid,report.detail="ACTIVE_SOURCE_PARAMETER_UNRESOLVED";
elseif ~owned,report.detail="ACTIVE_SOURCE_NOT_OWNED_BY_VDC_HALF";
elseif ~report.ok,report.detail="SPLIT_DC_RELATIVE_MISMATCH";
else,report.detail="OK";end
end

function report=evaluate_fixture(report,fixture,cfg)
% The fixture contains scorer-extracted semantic facts, never candidate
% model data. Keeping this branch behind an exact schema leaves production
% graph extraction and public-binding resolution unchanged.
if ~isfield(fixture,'split_dc')||~isstruct(fixture.split_dc) ...
        ||~isscalar(fixture.split_dc)
    report.detail="SEMANTIC_FIXTURE_SCHEMA_INVALID";return;
end
x=fixture.split_dc;
required={'source_blocks','on_active_power_path','resolved_values', ...
    'depends_on_Vdc_half','proportional_binding'};
if ~all(isfield(x,required))
    report.detail="SEMANTIC_FIXTURE_SCHEMA_INVALID";return;
end
try
    blocks=string(x.source_blocks(:));active=logical(x.on_active_power_path(:));
    values=double(x.resolved_values(:));depends=logical(x.depends_on_Vdc_half(:));
    proportional=logical(x.proportional_binding(:));
catch
    report.detail="SEMANTIC_FIXTURE_SCHEMA_INVALID";return;
end
n=numel(blocks);
if n==0||numel(active)~=n||numel(values)~=n||numel(depends)~=n ...
        ||numel(proportional)~=n||any(strlength(blocks)==0) ...
        ||~islogical(x.on_active_power_path)||~islogical(x.depends_on_Vdc_half) ...
        ||~islogical(x.proportional_binding)
    report.detail="SEMANTIC_FIXTURE_SCHEMA_INVALID";return;
end
ix=find(active);sources=blocks(ix);
if numel(sources)~=2
    report.valid=false;report.detail="ACTIVE_SPLIT_SOURCE_CARDINALITY";
    report.evidence=struct('active_source_count',numel(sources), ...
        'active_sources',sources,'fixture_schema',string(fixture.schema));return;
end
activeValues=abs(values(ix));owned=all(depends(ix))&&all(proportional(ix));
den=max(mean(activeValues),eps);mismatch=abs(activeValues(1)-activeValues(2))/den;
limit=getnum(cfg,'max_relative_mismatch',1e-6);
rows=struct('block',{},'value',{},'depends_on_Vdc_half',{}, ...
    'proportional_binding',{});
for i=1:numel(ix)
    k=ix(i);rows(end+1)=struct('block',blocks(k),'value',values(k), ... %#ok<AGROW>
        'depends_on_Vdc_half',depends(k), ...
        'proportional_binding',proportional(k));
end
report.valid=all(isfinite(activeValues))&&isfinite(mismatch)&&limit>=0;
report.ok=logical(report.valid&&owned&&mismatch<=limit+64*eps(max(1,limit)));
report.score=double(report.ok);
report.evidence=struct('active_source_count',2,'active_sources',sources, ...
    'bindings',rows,'resolved_magnitudes',activeValues, ...
    'relative_mismatch',mismatch,'max_relative_mismatch',limit, ...
    'ownership_ok',logical(owned),'fixture_schema',string(fixture.schema));
if ~report.valid,report.detail="ACTIVE_SOURCE_PARAMETER_UNRESOLVED";
elseif ~owned,report.detail="ACTIVE_SOURCE_NOT_OWNED_BY_VDC_HALF";
elseif ~report.ok,report.detail="SPLIT_DC_RELATIVE_MISMATCH";
else,report.detail="OK";end
end

function fixture=semantic_fixture(modelName)
fixture=[];
if isstruct(modelName)&&isscalar(modelName)&&isfield(modelName,'schema') ...
        &&isscalar(string(modelName.schema)) ...
        &&string(modelName.schema)=="D026.semantic-fixture"
    fixture=modelName;
end
end

function ok=task_identity_ok(spec,scenarioId)
ok=isstruct(spec)&&isscalar(spec)&&isfield(spec,'id') ...
    &&isscalar(string(spec.id))&&string(spec.id)=="D026" ...
    &&isscalar(string(scenarioId))&&string(scenarioId)=="nominal";
end

function [blocks,evidence]=active_sources(G)
% Graph descriptors on masked Specialized Power Systems sources also name
% their internal +/- PMIO children.  Those children are connectivity ports,
% not independent DC sources, so collapse the descriptor candidates back to
% the actual source mask blocks before enforcing the two-source cardinality.
candidates=unique_blocks(G,"physical",'dc voltage source|[/\\]100v[12](?:[/\\]|$)');
blocks=strings(0,1);
for i=1:numel(candidates)
    if is_dc_source_block(candidates(i)),blocks(end+1,1)=candidates(i);end %#ok<AGROW>
end
blocks=unique(blocks,'stable');
active=strings(0,1);evidence=struct([]);
for i=1:numel(blocks)
    q=struct('network',"physical",'direction',"undirected", ...
        'source',struct('block',blocks(i)), ...
        'target',struct('descriptor_regex','series rlc branch|three[- ]?phase.*load'));
    q.via={struct('descriptor_regex','igbt/diode|[/\\]ga(?:[1-9]|1[0-2])(?:[/\\]|$)')};
    [ok,e]=sat_graph_query(G,q);
    if ok,active(end+1,1)=blocks(i);evidence=append_struct(evidence,e);end %#ok<AGROW>
end
blocks=active;
end

function tf=is_dc_source_block(block)
tf=false;b=char(block);
leaf=regexprep(b,'.*[/\\]','');
if any(strcmp(leaf,{'+','-'})),return;end
try
    mask=lower(string(get_param(b,'MaskType')));
catch
    mask="";
end
if contains(mask,"dc voltage source")
    tf=true;return;
end
% D026's two public source masks have these stable names.  Requiring the
% path to end here deliberately rejects their masked internal descendants.
tf=~isempty(regexpi(b,'[/\\]100v[12]$','once'));
end

function row=resolve_source(block,defaultValue)
row=struct('block',string(block),'parameter',"",'expression',"",'value',NaN, ...
    'depends_on_Vdc_half',false,'proportional_binding',false,'detail',"PARAMETER_NOT_FOUND");
try,dp=get_param(char(block),'DialogParameters');catch,dp=struct();end
if ~isstruct(dp),return;end
names=fieldnames(dp);candidates=strings(0,1);
for i=1:numel(names)
    if ~isempty(regexpi(names{i},'amplitude|voltage','once'))
        try,v=string(get_param(char(block),names{i}));catch,continue;end
        if isscalar(v)&&strlength(strtrim(v))>0,candidates(end+1)=string(names{i});end %#ok<AGROW>
    end
end
for i=1:numel(candidates)
    p=candidates(i);expr=string(get_param(char(block),char(p)));
    [v0,v1,v2,ok]=probe_expression(expr,block,defaultValue);
    if ~ok,continue;end
    scale1=v1/defaultValue;probe=defaultValue*1.137+0.731;scale2=v2/probe;
    depends=abs(v2-v1)>1e-10*max(1,max(abs([v1 v2])));
    proportional=depends&&abs(scale1-scale2)<=1e-8*max(1,max(abs([scale1 scale2])));
    row.parameter=p;row.expression=expr;row.value=v0;
    row.depends_on_Vdc_half=logical(depends);row.proportional_binding=logical(proportional);
    row.detail=tern(proportional,"OK","NOT_PROPORTIONAL_TO_PUBLIC_BINDING");return;
end
end

function [v0,v1,v2,ok]=probe_expression(expr,block,defaultValue)
v0=NaN;v1=NaN;v2=NaN;ok=false;name='Vdc_half';
had=evalin('base',sprintf("exist('%s','var')",name))==1;
if had,old=evalin('base',name);else,old=[];end
cleanup=onCleanup(@()restore_base(name,had,old)); %#ok<NASGU>
try
    assignin('base',name,defaultValue);v1=scalar_resolve(expr,block);
    assignin('base',name,defaultValue*1.137+0.731);v2=scalar_resolve(expr,block);
    assignin('base',name,defaultValue);v0=scalar_resolve(expr,block);
    ok=all(isfinite([v0 v1 v2]));
catch,ok=false;end
end
function v=scalar_resolve(expr,block)
v=slResolve(char(expr),char(block));assert(isnumeric(v)&&isscalar(v)&&isreal(v));v=double(v);
end
function restore_base(name,had,old)
try,if had,assignin('base',name,old);else,evalin('base',"clear "+name);end,catch,end
end
function blocks=unique_blocks(G,network,pattern)
ix=find([G.nodes.network]==string(network));blocks=strings(0,1);
for i=ix(:)',if ~isempty(regexpi(char(G.nodes(i).descriptor),pattern,'once')),blocks(end+1,1)=G.nodes(i).block;end,end %#ok<AGROW>
blocks=unique(blocks,'stable');
end
function out=append_struct(out,row),if isempty(out),out=row;else,out(end+1)=row;end,end
function cfg=find_check(spec,id)
cfg=[];if ~isfield(spec,'task_specific_checks'),return;end;x=spec.task_specific_checks;
if ~iscell(x),x=num2cell(x);end
for i=1:numel(x),if isfield(x{i},'id')&&string(x{i}.id)==string(id),cfg=x{i};return;end,end
end
function v=input_default(spec,name,d)
v=d;if isfield(spec,'input_contract')&&isfield(spec.input_contract,name)
    x=spec.input_contract.(name);if isstruct(x)&&isfield(x,'default')&&isnumeric(x.default)&&isscalar(x.default),v=double(x.default);end
end
end
function r=base_report(scenario)
r=struct('task',"D026",'id',"D026.split_dc_balance",'kind',"task_specific", ...
    'semantic_kind',"band",'scenario',string(scenario),'layer',"nominal", ...
    'evaluated',false,'mandatory',true,'ok',false,'valid',false,'score',0, ...
    'detail',"UNINITIALIZED",'evidence',struct());
end
function v=getnum(s,f,d),v=d;if isstruct(s)&&isfield(s,f)&&isnumeric(s.(f))&&isscalar(s.(f))&&isfinite(s.(f)),v=double(s.(f));end,end
function s=tern(c,a,b),if c,s=string(a);else,s=string(b);end,end
