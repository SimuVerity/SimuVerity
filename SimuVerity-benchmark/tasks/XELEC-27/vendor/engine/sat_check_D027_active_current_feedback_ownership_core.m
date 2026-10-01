function report=sat_check_D027_active_current_feedback_ownership_core(modelName,spec,scenarioId,simOut,signals,baseReports,state) %#ok<INUSD>
%SAT_CHECK_D027_ACTIVE_CURRENT_FEEDBACK_OWNERSHIP_CORE
% The public contract explicitly requires measured-current closed-loop regulation,
% but does not prescribe a selector, coordinate frame, PI/PR/MPC law or
% modulation algorithm.  Reference and at least three distinct physical
% current measurements must both reach every discrete gate, or the unique
% gate-vector input of a trusted aggregate SPS Three-Level Bridge, on the
% active NPC path.

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
% Linked SPS transform/PWM subsystems expose valid external signal ports,
% but their internal library boundary is not always represented by native
% Simulink line handles.  Add input->output causality only for exact trusted
% MathWorks library identities needed by this D027 control chain.
G=add_trusted_d027_signal_edges(G);
[refs,refOk,refReason]=input_bindings(baseReports,"Iref_amp");
if ~refOk
    report.detail=refReason;report.evidence=struct('base_reports',baseRows);return;
end
[feedback,feedbackOk,feedbackReason]=current_output_sources(baseReports);
if ~feedbackOk
    report.detail=feedbackReason;report.evidence=struct('base_reports',baseRows);return;
end
candidates=controllable_blocks(G);
[discreteActive,discretePhysicalEvidence]=active_switches(G,candidates);
npc=sat_d027_npc_population_core(modelName);
aggregateActive=npc.active_aggregate_blocks;
[stageMode,stageTargets,effectiveGateCount,stageOk]=select_stage( ...
    discreteActive,aggregateActive);

paths=empty_lineage_rows();
for i=1:numel(stageTargets)
    paths(end+1)=lineage_for_stage(G,stageTargets(i),refs,feedback); %#ok<AGROW>
end
if isempty(paths)
    allReference=false;allFeedback=false;minFeedbackSources=0;
else
    allReference=all([paths.reference_reaches]);
    allFeedback=all([paths.feedback_source_count]>=3);
    minFeedbackSources=min([paths.feedback_source_count]);
end
if stageMode=="aggregate"
    refCoverage=12*double(allReference);
    feedbackCoverage=12*double(allFeedback);
else
    refCoverage=sum([paths.reference_reaches]);
    feedbackCoverage=sum([paths.feedback_source_count]>=3);
end

report.valid=logical(baseOk&&refOk&&feedbackOk&&stageOk);
report.ok=logical(report.valid&&allReference&&allFeedback);report.score=double(report.ok);
report.evidence=struct('base_reports',baseRows,'Iref_bindings',refs, ...
    'measured_current_sources',feedback, ...
    'stage_representation',stageMode,'physical_stage_blocks',stageTargets, ...
    'active_switches',discreteActive, ...
    'active_aggregate_bridges',aggregateActive, ...
    'active_switch_count',effectiveGateCount, ...
    'discrete_active_switch_count',numel(discreteActive), ...
    'aggregate_active_bridge_count',numel(aggregateActive), ...
    'npc_population',npc,'physical_paths',{discretePhysicalEvidence}, ...
    'reference_paths',paths,'reference_coverage',refCoverage, ...
    'feedback_coverage',feedbackCoverage, ...
    'physical_feedback_source_coverage',minFeedbackSources, ...
    'required_feedback_source_count',3,'required_gate_count',12, ...
    'controller_constraint',"measured-current feedback; algorithm neutral");
if ~baseOk,report.detail="D027_BASE_NPC_CONTRACT_FAILED";
elseif ~stageOk,report.detail="ACTIVE_NPC_STAGE_NOT_UNIQUE_OR_EQUIVALENT_12";
elseif ~allReference,report.detail="IREF_TO_ACTIVE_STAGE_LINEAGE_INCOMPLETE";
elseif ~allFeedback,report.detail="MEASURED_CURRENT_FEEDBACK_TO_ACTIVE_STAGE_INCOMPLETE";
else,report.detail="OK";end
end

function [mode,targets,effectiveCount,ok]=select_stage(discrete,aggregate)
mode="invalid";targets=strings(0,1);effectiveCount=0;ok=false;
if numel(discrete)==12&&isempty(aggregate)
    mode="discrete";targets=discrete;effectiveCount=12;ok=true;
elseif isempty(discrete)&&numel(aggregate)==1
    mode="aggregate";targets=aggregate;effectiveCount=12;ok=true;
end
end

function rows=empty_lineage_rows()
rows=struct('switch_block',{},'reference_reaches',{}, ...
    'reference_path',{},'feedback_reaches',{}, ...
    'feedback_source_count',{},'feedback_sources_reaching',{}, ...
    'feedback_paths',{});
end

function row=lineage_for_stage(G,target,refs,feedback)
selector=gate_input_selector(G,target);
refHit=false;refBest=struct('block_path',strings(0,1));
for source=refs(:)'
    q=struct('network',"signal",'direction',"forward", ...
        'source',struct('block',source),'target',selector);
    [ok,e]=sat_graph_query(G,q);
    if ok,refHit=true;refBest=e;break;end
end
feedbackHits=false(numel(feedback),1);feedbackEvidence=cell(numel(feedback),1);
for i=1:numel(feedback)
    q=struct('network',"signal",'direction',"forward", ...
        'source',struct('block',feedback(i)),'target',selector);
    [feedbackHits(i),feedbackEvidence{i}]=sat_graph_query(G,q);
end
row=struct('switch_block',string(target), ...
    'reference_reaches',logical(refHit),'reference_path',refBest.block_path, ...
    'feedback_reaches',logical(sum(feedbackHits)>=3), ...
    'feedback_source_count',sum(feedbackHits), ...
    'feedback_sources_reaching',feedback(feedbackHits), ...
    'feedback_paths',{feedbackEvidence});
end

function selector=gate_input_selector(G,block)
ids=find(string({G.nodes.network})=="signal" ...
    &string({G.nodes.block})==string(block) ...
    &contains(lower(string({G.nodes.port_field})),"in"));
if isempty(ids),ids=0;end
selector=struct('node_id',ids);
end

function G=add_trusted_d027_signal_edges(G)
blocks=unique(string({G.nodes.block}),'stable');
for block=blocks(:)'
    if ~trusted_d027_signal_component(block),continue;end
    ids=find(string({G.nodes.network})=="signal" ...
        &string({G.nodes.block})==block);
    fields=lower(string({G.nodes(ids).port_field}));
    inputs=ids(contains(fields,"in"));outputs=ids(contains(fields,"out"));
    for a=inputs(:)'
        for b=outputs(:)'
            [G.signal_forward,G.signal_forward_edge_kinds]= ...
                add_signal_edge(G.signal_forward,G.signal_forward_edge_kinds, ...
                a,b,"d027_trusted_library_semantics");
            [G.signal_reverse,G.signal_reverse_edge_kinds]= ...
                add_signal_edge(G.signal_reverse,G.signal_reverse_edge_kinds, ...
                b,a,"d027_trusted_library_semantics");
        end
    end
end
end

function ok=trusted_d027_signal_component(block)
mask=normalise_block_text(get_block_param(block,'MaskType'));
reference=normalise_block_text(get_block_param(block,'ReferenceBlock'));
controller=upper(string(get_block_param(block,'Controller')));
ok=(mask=="abc to dq0 transformation" ...
        &&contains(reference,"spsabctodq0lib/abc to dq0")) ...
    ||(mask=="dq0 to abc transformation" ...
        &&contains(reference,"spsdq0toabclib/dq0 to abc")) ...
    ||(mask=="pwm generator (3-level)" ...
        &&contains(reference,"spspwmgenerator3levellib/pwm generator")) ...
    ||(mask=="pid 1dof" ...
        &&contains(reference,"slpidlib/pid controller") ...
        &&contains(controller,"I"));
end

function [adj,kinds]=add_signal_edge(adj,kinds,a,b,kind)
if a==b||any(adj{a}==b),return;end
adj{a}(end+1)=b;kinds{a}{end+1}=char(kind);
[adj{a},order]=sort(adj{a});kinds{a}=kinds{a}(order);
end

function value=get_block_param(block,param)
value='';try,value=get_param(char(block),param);catch,end
if isnumeric(value),value=num2str(value);end
end

function value=normalise_block_text(value)
value=lower(regexprep(strtrim(string(value)),'\s+',' '));
value=replace(value,'\','/');
end

function report=evaluate_fixture(report,fixture,baseOk,baseRows)
if ~isfield(fixture,'current_control')||~isstruct(fixture.current_control)
    report.detail="SEMANTIC_FIXTURE_SCHEMA_INVALID";return;
end
x=fixture.current_control;
if ~all(isfield(x,{'reference_path','feedback_path','gate_paths'}))||~isstruct(x.gate_paths)
    report.detail="SEMANTIC_FIXTURE_SCHEMA_INVALID";return;
end
rows=x.gate_paths;required={'switch_block','on_active_power_path','path_complete'};
if isempty(rows)||~all(isfield(rows,required))
    report.detail="SEMANTIC_FIXTURE_SCHEMA_INVALID";return;
end
ref=x.reference_path;refOk=isfield(ref,'source_count')&&isfield(ref,'path_complete') ...
    &&double(ref.source_count)>=1&&logical(ref.path_complete);
if ~isfield(ref,'source_count')||~isfield(ref,'path_complete')
    report.detail="SEMANTIC_FIXTURE_SCHEMA_INVALID";return;
end
feedback=x.feedback_path;feedbackOk=isfield(feedback,'source_count') ...
    &&isfield(feedback,'path_complete')&&double(feedback.source_count)>=3 ...
    &&logical(feedback.path_complete);
sameOwner=true;
if isfield(ref,'selector_owner')&&isfield(feedback,'selector_owner')
    sameOwner=string(ref.selector_owner)==string(feedback.selector_owner);
end
active=logical([rows.on_active_power_path]);ix=find(active);
covered=logical([rows(ix).path_complete]);countOk=numel(ix)==12;
report.valid=logical(baseOk&&refOk&&feedbackOk&&countOk);
report.ok=logical(report.valid&&sameOwner&&all(covered));report.score=double(report.ok);
report.evidence=struct('base_reports',baseRows,'reference_path',ref,'feedback_path',feedback, ...
    'active_switches',string({rows(ix).switch_block}), ...
    'active_switch_count',numel(ix),'reference_coverage',sum(covered), ...
    'required_gate_count',12,'controller_constraint',"measured-current feedback; algorithm neutral", ...
    'fixture_schema',string(fixture.schema));
if ~baseOk,report.detail="D027_BASE_NPC_CONTRACT_FAILED";
elseif ~refOk,report.detail="IREF_BINDING_OR_PATH_MISSING";
elseif ~feedbackOk,report.detail="MEASURED_CURRENT_FEEDBACK_PATH_MISSING";
elseif ~countOk,report.detail="ACTIVE_CONTROLLABLE_SWITCH_COUNT_NOT_12";
elseif ~sameOwner,report.detail="REFERENCE_AND_FEEDBACK_DO_NOT_OWN_SAME_CONTROLLER";
elseif ~all(covered),report.detail="IREF_TO_ACTIVE_STAGE_LINEAGE_INCOMPLETE";
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
function [blocks,ok,reason]=input_bindings(base,name)
blocks=strings(0,1);ok=false;reason=name+"_BINDING_MISSING";
items=field_items(base,'input_reports');values=strings(0,1);
for i=1:numel(items)
    r=items{i};if ~isstruct(r)||~isfield(r,'name')||string(r.name)~=name ...
            ||~logical(r.ok)||~isfield(r,'bindings'),continue;end
    x=r.bindings;if ischar(x)||(isstring(x)&&isscalar(x)),values(end+1)=string(x); ...
    elseif iscell(x),values=[values;string(x(:))];else,values=[values;string(x(:))];end %#ok<AGROW>
end
for v=values(:)'
    p=split(v,"::");if numel(p)==2,blocks(end+1,1)=p(1);end %#ok<AGROW>
end
blocks=unique(blocks,'stable');ok=~isempty(blocks);if ok,reason="OK";end
end
function [blocks,ok,reason]=current_output_sources(base)
blocks=strings(0,1);ok=false;reason="IABC_PHYSICAL_CURRENT_TRACE_MISSING";
items=field_items(base,'output_reports');hits={};
for i=1:numel(items)
    r=items{i};
    if ~isstruct(r)||~isfield(r,'name')||string(r.name)~="Iabc" ...
            ||~isfield(r,'ok')||~logical(r.ok)||~isfield(r,'provenance_ok') ...
            ||~logical(r.provenance_ok)||~isfield(r,'trace'),continue;end
    hits{end+1}=r.trace; %#ok<AGROW>
end
if numel(hits)~=1,reason="IABC_PHYSICAL_CURRENT_TRACE_AMBIGUOUS";return;end
trace=hits{1};
for i=1:numel(trace)
    parts=strings(0,1);
    for f={'name','block_type','mask_type','reference_block','descriptor'}
        if isfield(trace(i),f{1}),parts(end+1)=string(trace(i).(f{1}));end %#ok<AGROW>
    end
    d=lower(strjoin(parts,"|"));
    if contains(d,"current measurement")||contains(d,"current sensor")
        blocks(end+1,1)=string(trace(i).path); %#ok<AGROW>
    end
end
blocks=unique(blocks,'stable');ok=numel(blocks)>=3;
if ok,reason="OK";else,reason="IABC_THREE_PHASE_CURRENT_ENDPOINTS_MISSING";end
end
function items=field_items(s,name)
if ~isstruct(s)||~isfield(s,name)||isempty(s.(name)),items={};
elseif iscell(s.(name)),items=s.(name)(:).';
else,items=arrayfun(@(x)x,s.(name),'UniformOutput',false);end
end
function fixture=semantic_fixture(modelName)
fixture=[];if isstruct(modelName)&&isscalar(modelName)&&isfield(modelName,'schema') ...
        &&string(modelName.schema)=="D027.semantic-fixture",fixture=modelName;end
end
function ok=task_identity_ok(spec,scenarioId)
ok=isstruct(spec)&&isscalar(spec)&&isfield(spec,'id')&&string(spec.id)=="D027" ...
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
r=struct('task',"D027",'id',"D027.active_current_feedback_ownership", ...
    'kind',"task_specific",'semantic_kind',"structure",'scenario',string(scenario), ...
    'layer',"qualification",'evaluated',false,'mandatory',true,'ok',false, ...
    'valid',false,'score',0,'detail',"UNINITIALIZED",'evidence',struct());
end
