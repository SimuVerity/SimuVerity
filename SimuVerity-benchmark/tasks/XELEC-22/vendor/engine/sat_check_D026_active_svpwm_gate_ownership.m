function report=sat_check_D026_active_svpwm_gate_ownership(modelName,spec,scenarioId,simOut,signals,baseReports,state) %#ok<INUSD>
%SAT_CHECK_D026_ACTIVE_SVPWM_GATE_OWNERSHIP
% The check is modulation-independent and accepts any live command logic that reaches
% the twelve controllable devices on the actual NPC power path.

report=base_report(scenarioId);report.evaluated=true;
if ~task_identity_ok(spec,scenarioId)
    report.detail="TASK_OR_SCENARIO_IDENTITY_MISMATCH";return;
end
[baseOk,baseRows]=required_base_reports(baseReports,[ ...
    "three_level_switch_population","npc_clamping_diodes", ...
    "three_phase_power_stage","source_switch_load_route"]);
fixture=semantic_fixture(modelName);
if ~isempty(fixture)
    report=evaluate_fixture(report,fixture,baseOk,baseRows);return;
end
try,G=sat_model_graph(modelName);catch ex
    report.detail="GRAPH_BUILD_ERROR:"+string(ex.identifier);return;
end
candidates=controllable_blocks(G);[active,physicalEvidence]=active_switches(G,candidates);
gateRows=struct('switch_block',{},'covered',{},'upstream_blocks',{});
for i=1:numel(active)
    [covered,upstream]=has_live_gate_lineage(G,active(i));
    gateRows(end+1)=struct('switch_block',active(i),'covered',logical(covered), ... %#ok<AGROW>
        'upstream_blocks',upstream);
end
countOk=numel(active)==12;coverage=sum([gateRows.covered]);
report.valid=logical(baseOk&&countOk);
report.ok=logical(report.valid&&coverage==12);report.score=double(report.ok);
report.evidence=struct('base_reports',baseRows,'switch_candidates',candidates, ...
    'active_switches',active,'active_switch_count',numel(active), ...
    'physical_paths',{physicalEvidence},'gate_paths',gateRows, ...
    'gate_trace_coverage',coverage,'required_gate_count',12, ...
    'algorithm_constraint',"none");
if ~baseOk,report.detail="D026_BASE_NPC_CONTRACT_FAILED";
elseif ~countOk,report.detail="ACTIVE_CONTROLLABLE_SWITCH_COUNT_NOT_12";
elseif coverage~=12,report.detail="LIVE_GATE_TRACE_INCOMPLETE";
else,report.detail="OK";end
end

function report=evaluate_fixture(report,fixture,baseOk,baseRows)
if ~isfield(fixture,'svpwm')||~isstruct(fixture.svpwm) ...
        ||~isfield(fixture.svpwm,'gate_paths')
    report.detail="SEMANTIC_FIXTURE_SCHEMA_INVALID";return;
end
rows=fixture.svpwm.gate_paths;
required={'switch_block','on_active_power_path','gate_reaches_switch'};
if ~isstruct(rows)||isempty(rows)||~all(isfield(rows,required))
    report.detail="SEMANTIC_FIXTURE_SCHEMA_INVALID";return;
end
active=logical([rows.on_active_power_path]);ix=find(active);
covered=logical([rows(ix).gate_reaches_switch]);countOk=numel(ix)==12;
report.valid=logical(baseOk&&countOk);
report.ok=logical(report.valid&&all(covered));report.score=double(report.ok);
report.evidence=struct('base_reports',baseRows, ...
    'active_switches',string({rows(ix).switch_block}), ...
    'active_switch_count',numel(ix),'gate_trace_coverage',sum(covered), ...
    'required_gate_count',12,'algorithm_constraint',"none", ...
    'fixture_schema',string(fixture.schema));
if ~baseOk,report.detail="D026_BASE_NPC_CONTRACT_FAILED";
elseif ~countOk,report.detail="ACTIVE_CONTROLLABLE_SWITCH_COUNT_NOT_12";
elseif ~all(covered),report.detail="LIVE_GATE_TRACE_INCOMPLETE";
else,report.detail="OK";end
end

function blocks=controllable_blocks(G)
blocks=strings(0,1);all=unique(string({G.nodes.block}),'stable');
for b=all(:)'
    ix=find([G.nodes.block]==b);d=lower(strjoin(string({G.nodes(ix).descriptor}),"|"));
    if isempty(regexpi(char(d),'igbt|mosfet|\bgto\b|ideal switch','once')),continue;end
    if any([G.nodes(ix).network]=="physical") ...
            &&any([G.nodes(ix).network]=="signal"&contains(lower(string({G.nodes(ix).port_field})),"in"))
        blocks(end+1,1)=b; %#ok<AGROW>
    end
end
end
function [active,evidence]=active_switches(G,candidates)
active=strings(0,1);evidence=struct([]);
for i=1:numel(candidates)
    q=struct('network',"physical",'direction',"undirected", ...
        'source',struct('descriptor_regex','dc voltage source|split dc|dc source'), ...
        'target',struct('descriptor_regex','three[- ]phase.*load|series rlc branch|parallel rlc load'));
    q.via={struct('block',candidates(i))};[ok,e]=sat_graph_query(G,q);
    if ok,active(end+1,1)=candidates(i);evidence=append_struct(evidence,e);end %#ok<AGROW>
end
end
function [ok,blocks]=has_live_gate_lineage(G,switchBlock)
start=find([G.nodes.network]=="signal"&[G.nodes.block]==switchBlock ...
    &contains(lower(string({G.nodes.port_field})),"in"));
seen=false(1,numel(G.nodes));queue=start(:)';seen(queue)=true;blocks=strings(0,1);ok=false;
while ~isempty(queue)
    x=queue(1);queue(1)=[];
    for y=G.signal_reverse{x}
        if seen(y),continue;end;seen(y)=true;queue(end+1)=y; %#ok<AGROW>
        b=string(G.nodes(y).block);if b==switchBlock,continue;end
        blocks(end+1,1)=b;d=lower(string(G.nodes(y).descriptor)); %#ok<AGROW>
        if isempty(regexpi(char(d),'\|constant\||\|ground\||\|terminator\||\|from\||\|goto\||\|inport\||\|outport\||\|mux\||\|demux\|','once'))
            ok=true;
        end
    end
end
blocks=unique(blocks,'stable');
end
function fixture=semantic_fixture(modelName)
fixture=[];if isstruct(modelName)&&isscalar(modelName)&&isfield(modelName,'schema') ...
        &&string(modelName.schema)=="D026.semantic-fixture",fixture=modelName;end
end
function ok=task_identity_ok(spec,scenarioId)
ok=isstruct(spec)&&isscalar(spec)&&isfield(spec,'id')&&string(spec.id)=="D026" ...
    &&string(scenarioId)=="nominal";
end
function [ok,rows]=required_base_reports(base,ids)
ok=true;rows=struct('id',{},'found',{},'passed',{});source=struct([]);
if isstruct(base)&&isfield(base,'struct_reports'),source=base.struct_reports;end
for i=1:numel(ids)
    hit=[];if isstruct(source)&&isfield(source,'id'),hit=find(string({source.id})==ids(i));end
    passed=numel(hit)==1&&logical(source(hit).ok);
    rows(end+1)=struct('id',ids(i),'found',numel(hit)==1,'passed',logical(passed)); %#ok<AGROW>
    ok=ok&&passed;
end
end
function out=append_struct(out,row),if isempty(out),out=row;else,out(end+1)=row;end,end
function r=base_report(scenario)
r=struct('task',"D026",'id',"D026.active_svpwm_gate_ownership", ...
    'kind',"task_specific",'semantic_kind',"structure",'scenario',string(scenario), ...
    'layer',"qualification",'evaluated',false,'mandatory',true,'ok',false, ...
    'valid',false,'score',0,'detail',"UNINITIALIZED",'evidence',struct());
end
