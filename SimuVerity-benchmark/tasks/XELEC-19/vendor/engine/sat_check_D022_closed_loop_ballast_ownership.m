function report=sat_check_D022_closed_loop_ballast_ownership( ...
    modelName,spec,scenarioId,simOut,signals,baseReports,state) %#ok<INUSD>
%SAT_CHECK_D022_CLOSED_LOOP_BALLAST_OWNERSHIP D022 loop ownership.
% Algorithm-neutral qualification predicate:
%   a physical generator/PCC/DC-bus measurement must pass through real
%   signal computation and reach every controllable power interface in the
%   converter that owns the proven ballast branch.  No feedback variable,
%   controller family, coordinate system, modulator or device is named.

if ~identity_ok(spec,scenarioId)
    report=make_report(false,false,false, ...
        "TASK_OR_SCENARIO_IDENTITY_MISMATCH",struct());return;
end
if has_fixture(state)
    facts=state.evidence.unit_test_facts;valid=true;reason="OK";
else
    try,[facts,valid,reason]=extract_facts(modelName,spec,scenarioId, ...
            simOut,signals,baseReports,state);
    catch ex
        report=make_report(false,false,false, ...
            "EXTRACTION_ERROR:"+string(ex.identifier), ...
            struct('message',string(strtrim(ex.message))));return;
    end
end
if ~valid,report=make_report(true,false,false,reason,facts);return;end
[schemaOk,ok,detail]=verdict(facts);
report=make_report(true,schemaOk,ok,detail,facts);
end

function [facts,valid,reason]=extract_facts(model,spec,scenario,simOut,signals,base,state)
facts=empty_facts();valid=false;reason="";
branch=sat_check_D022_power_branch_ownership( ...
    model,spec,scenario,simOut,signals,base,state);
facts.power_branch_report=branch;
if ~(branch.evaluated&&branch.valid&&branch.ok)
    reason="POWER_BRANCH_OWNERSHIP_FAILED:"+string(branch.detail);return;
end
if ~isfield(branch.evidence,'ballast_converter_blocks') ...
        ||~isfield(branch.evidence,'source_blocks')
    reason="BALLAST_BRANCH_ROLE_EVIDENCE_MISSING";return;
end
G=task_graph(model,state);G=close_trusted_signal_subsystems(G);
roots=topmost_blocks(string(branch.evidence.ballast_converter_blocks(:)));
actuators=ballast_actuators(G,roots);
if isempty(actuators),reason="ACTIVE_BALLAST_ACTUATOR_UNRESOLVED";return;end

measurements=physical_feedback_sources(G,base,branch.evidence);
if isempty(measurements),reason="PHYSICAL_SYSTEM_MEASUREMENT_UNRESOLVED";return;end

rows=struct('actuator',{},'gate_nodes',{},'owned',{}, ...
    'feedback_source',{},'signal_path',{},'computation_blocks',{});
owned=false(size(actuators));allPaths={};allComputations={};
for i=1:numel(actuators)
    gates=signal_field_nodes(G,actuators(i),"in");
    hitSource="";hitPath=strings(0,1);hitCompute=strings(0,1);
    for source=measurements(:)'
        for gate=gates(:)'
            [hit,path]=signal_reaches(G,source,gate);
            if ~hit,continue;end
            compute=computation_blocks(path,source,actuators(i));
            if isempty(compute),continue;end
            hitSource=source;hitPath=path;hitCompute=compute;break;
        end
        if strlength(hitSource)>0,break;end
    end
    owned(i)=strlength(hitSource)>0;
    allPaths{i}=hitPath;allComputations{i}=hitCompute;
    rows(end+1)=struct('actuator',actuators(i),'gate_nodes',double(gates), ... %#ok<AGROW>
        'owned',logical(owned(i)),'feedback_source',hitSource, ...
        'signal_path',hitPath,'computation_blocks',hitCompute);
end
facts.power_branch_ownership=true;
facts.ballast_converter_roots=roots;
facts.active_ballast_actuators=actuators;
facts.physical_measurement_sources=measurements;
facts.actuator_rows=rows;
facts.feedback_signal_paths=allPaths;
facts.control_computation_blocks=allComputations;
facts.physical_feedback_present=~isempty(measurements);
facts.measurement_reaches_active_ballast=any(owned);
facts.control_computation_on_path=any(cellfun(@(x)~isempty(x),allComputations));
facts.same_ballast_stage_owned=any(owned);
facts.all_active_ballast_actuators_owned=all(owned);
facts.active_ballast_stage_coverage=sum(owned)/max(numel(owned),1);
facts.algorithm_constraint="none";
valid=true;reason="OK";
end

function [schemaOk,ok,detail]=verdict(f)
required={'power_branch_ownership','ballast_converter_roots', ...
    'active_ballast_actuators','physical_measurement_sources', ...
    'physical_feedback_present','measurement_reaches_active_ballast', ...
    'control_computation_on_path','same_ballast_stage_owned', ...
    'all_active_ballast_actuators_owned'};
schemaOk=isstruct(f)&&isscalar(f)&&all(isfield(f,required));
if ~schemaOk,ok=false;detail="FACT_SCHEMA_INVALID";return;end
ok=logical(f.power_branch_ownership)&&~isempty(f.ballast_converter_roots) ...
    &&~isempty(f.active_ballast_actuators) ...
    &&~isempty(f.physical_measurement_sources) ...
    &&logical(f.physical_feedback_present) ...
    &&logical(f.measurement_reaches_active_ballast) ...
    &&logical(f.control_computation_on_path) ...
    &&logical(f.same_ballast_stage_owned) ...
    &&logical(f.all_active_ballast_actuators_owned);
if ok,detail="OK";
elseif ~logical(f.power_branch_ownership),detail="POWER_BRANCH_OWNERSHIP_FAILED";
elseif isempty(f.active_ballast_actuators),detail="ACTIVE_BALLAST_ACTUATOR_UNRESOLVED";
elseif isempty(f.physical_measurement_sources)||~logical(f.physical_feedback_present)
    detail="PHYSICAL_SYSTEM_FEEDBACK_MISSING_OR_FAKE";
elseif ~logical(f.measurement_reaches_active_ballast)
    detail="PHYSICAL_FEEDBACK_DOES_NOT_REACH_ACTIVE_BALLAST_STAGE";
elseif ~logical(f.control_computation_on_path)
    detail="FEEDBACK_PATH_HAS_NO_CONTROL_COMPUTATION";
elseif ~logical(f.same_ballast_stage_owned)
    detail="FEEDBACK_DRIVES_WRONG_POWER_STAGE";
else,detail="ACTIVE_BALLAST_STAGE_FEEDBACK_OWNERSHIP_INCOMPLETE";end
end

function blocks=physical_feedback_sources(G,base,branch)
% Candidate sources are evaluator-validated physical output endpoints or
% physical sensors attached to the proven source/PCC/ballast network.
blocks=strings(0,1);roleBlocks=strings(0,1);
for name={'source_blocks','user_blocks','ballast_converter_blocks'}
    if isfield(branch,name{1}),roleBlocks=[roleBlocks;string(branch.(name{1})(:))];end %#ok<AGROW>
end
roleBlocks=topmost_blocks(unique(roleBlocks(strlength(roleBlocks)>0),'stable'));

items=field_items(base,'output_reports');allowed=["Vdc","Vabc","Iabc", ...
    "Psource","Pload","Pdump","Speed"];
for i=1:numel(items)
    r=items{i};if ~isstruct(r)||~isfield(r,'name') ...
            ||~any(string(r.name)==allowed)||~logical_field(r,'ok') ...
            ||~logical_field(r,'provenance_ok')||~isfield(r,'trace'),continue;end
    trace=r.trace;if ~isstruct(trace),continue;end
    for q=1:numel(trace)
        if ~isfield(trace(q),'path'),continue;end
        b=string(trace(q).path);if strlength(b)==0||isempty(signal_field_nodes(G,b,"out")),continue;end
        d=trace_descriptor(trace(q));
        sensor=contains(d,"voltage measurement")||contains(d,"voltage sensor") ...
            ||contains(d,"current measurement")||contains(d,"current sensor") ...
            ||contains(d,"three-phase vi measurement") ...
            ||contains(d,"three-phase v-i measurement");
        ownedPower=any(string(r.name)==["Psource","Pload","Pdump"]) ...
            &&isfield(branch,'power_endpoints') ...
            &&any(block_related(b,string(branch.power_endpoints(:))));
        ownedSpeed=string(r.name)=="Speed"&&isfield(branch,'source_blocks') ...
            &&any(block_related(b,string(branch.source_blocks(:))));
        if sensor||ownedPower||ownedSpeed,blocks(end+1,1)=b;end %#ok<AGROW>
    end
end

% A legal controller may use a second physical sensor rather than the one
% selected for public logging.  Accept it only when it has conserving ports,
% a signal output, trusted measurement semantics and physical connectivity
% to the already proven system roles.
all=unique(string({G.nodes.block}),'stable');
for b=all(:)'
    ids=find([G.nodes.block]==b);if ~any([G.nodes(ids).network]=="physical") ...
            ||isempty(signal_field_nodes(G,b,"out")),continue;end
    d=lower(strjoin(string({G.nodes(ids).descriptor}),"|"));
    trusted=contains(d,"voltage measurement")||contains(d,"voltage sensor") ...
        ||contains(d,"current measurement")||contains(d,"current sensor") ...
        ||contains(d,"three-phase vi measurement") ...
        ||contains(d,"three-phase v-i measurement") ...
        ||contains(d,"synchronous generator")||contains(d,"synchronous machine");
    if trusted&&isfinite(physical_distance(G,b,roleBlocks)),blocks(end+1,1)=b;end %#ok<AGROW>
end
blocks=topmost_blocks(unique(blocks(strlength(blocks)>0),'stable'));
end

function actuators=ballast_actuators(G,roots)
actuators=strings(0,1);all=unique(string({G.nodes.block}),'stable');
for b=all(:)'
    if ~any(block_related(b,roots)),continue;end
    ids=find([G.nodes.block]==b);if ~any([G.nodes(ids).network]=="physical") ...
            ||isempty(signal_field_nodes(G,b,"in")),continue;end
    [d,device]=trusted_descriptor(b);
    controlled=contains(d,"mosfet")||contains(d,"igbt")||contains(d,"gto") ...
        ||contains(d,"thyristor")||contains(d,"ideal switch") ...
        ||contains(d,"universal bridge")||contains(d,"three-level bridge") ...
        ||contains(device,"mosfet")||contains(device,"igbt") ...
        ||contains(device,"gto")||contains(device,"thyristor") ...
        ||contains(device,"ideal switch");
    if controlled,actuators(end+1,1)=b;end %#ok<AGROW>
end
actuators=topmost_blocks(unique(actuators,'stable'));
end

function [ok,path]=signal_reaches(G,source,targetNode)
q=struct('network',"signal",'direction',"forward", ...
    'source',struct('block',source),'target',struct('node_id',targetNode));
[ok,e]=sat_graph_query(G,q);path=strings(0,1);
if ok&&isstruct(e)&&isfield(e,'block_path'),path=string(e.block_path(:));end
end

function blocks=computation_blocks(path,source,actuator)
blocks=strings(0,1);path=unique(string(path(:)),'stable');
for b=path(:)'
    if b==source||block_related(b,actuator),continue;end
    bt=lower(string(getp(b,'BlockType')));mt=lower(string(getp(b,'MaskType')));
    routing=["goto","from","inport","outport","mux","demux", ...
        "buscreator","busselector","selector","signalconversion", ...
        "ratetransition","data type conversion","datatypeconversion"];
    if any(bt==routing)||any(mt==routing),continue;end
    % A plain subsystem on a path is a hierarchy boundary, not by itself a
    % control computation. Its internal arithmetic/comparison blocks will
    % appear separately in the graph path.
    if bt=="subsystem"&&strlength(strtrim(mt))==0 ...
            &&strlength(strtrim(string(getp(b,'ReferenceBlock'))))==0,continue;end
    blocks(end+1,1)=b; %#ok<AGROW>
end
blocks=unique(blocks,'stable');
end

function G=close_trusted_signal_subsystems(G)
blocks=unique(string({G.nodes.block}),'stable');
for b=blocks(:)'
    ids=find([G.nodes.block]==b);sig=ids([G.nodes(ids).network]=="signal");
    if isempty(sig),continue;end
    bt=string(getp(b,'BlockType'));mt=string(getp(b,'MaskType'));
    rb=string(getp(b,'ReferenceBlock'));
    if bt~="SubSystem"||(strlength(strtrim(rb))==0&&strlength(strtrim(mt))==0),continue;end
    fields=lower(string({G.nodes(sig).port_field}));
    ins=sig(contains(fields,"in"));outs=sig(contains(fields,"out"));
    for x=ins(:)',for y=outs(:)'
        if any(G.signal_forward{x}==y),continue;end
        G.signal_forward{x}(end+1)=y;
        G.signal_forward_edge_kinds{x}{end+1}='trusted_subsystem_potential';
    end,end
end
end

function d=physical_distance(G,fromBlocks,toBlocks)
src=physical_nodes(G,fromBlocks);dst=physical_nodes(G,toBlocks);d=Inf;
if isempty(src)||isempty(dst),return;end
dist=Inf(1,numel(G.nodes));q=unique(src(:)');dist(q)=0;
while ~isempty(q)
    x=q(1);q(1)=[];if any(dst==x),d=dist(x);return;end
    for y=G.physical_undirected{x}
        if isinf(dist(y)),dist(y)=dist(x)+1;q(end+1)=y;end %#ok<AGROW>
    end
end
end
function ids=physical_nodes(G,blocks)
ids=[];for b=string(blocks(:))',ids=[ids find([G.nodes.block]==b ...
        &[G.nodes.network]=="physical")];end;ids=unique(ids); %#ok<AGROW>
end
function ids=signal_field_nodes(G,block,kind)
ids=find([G.nodes.block]==string(block)&[G.nodes.network]=="signal");
f=lower(string({G.nodes(ids).port_field}));
if kind=="in",ids=ids(contains(f,"in")|f=="enable"|f=="trigger"); ...
else,ids=ids(contains(f,"out")|f=="state");end
end
function tf=block_related(block,groups)
groups=string(groups(:));tf=block==groups|startsWith(block,groups+"/") ...
    |startsWith(groups,block+"/");
end
function out=topmost_blocks(blocks)
out=strings(0,1);blocks=unique(string(blocks(:)),'stable');
for i=1:numel(blocks)
    if ~any(startsWith(blocks(i),blocks((1:numel(blocks))~=i)+"/"))
        out(end+1,1)=blocks(i); %#ok<AGROW>
    end
end
end
function [d,device]=trusted_descriptor(block)
parts=strings(0,1);for p={'BlockType','MaskType','ReferenceBlock'}
    parts(end+1)=string(getp(block,p{1})); %#ok<AGROW>
end
d="|"+lower(strjoin(parts,"|"))+"|";device=lower(string(getp(block,'Device')));
end
function d=trace_descriptor(t)
parts=strings(0,1);for f={'name','block_type','mask_type','reference_block','descriptor'}
    if isfield(t,f{1}),parts(end+1)=string(t.(f{1}));end %#ok<AGROW>
end;d=lower(strjoin(parts,"|"));
end
function G=task_graph(model,state)
if isstruct(state)&&isfield(state,'model_graph')&&isstruct(state.model_graph) ...
        &&isfield(state.model_graph,'schema') ...
        &&string(state.model_graph.schema)=="simuverity.sat-model-graph.v1"
    G=state.model_graph;else,G=sat_model_graph(char(string(model)));end
end
function items=field_items(s,name)
if ~isstruct(s)||~isscalar(s)||~isfield(s,name)||isempty(s.(name)),items={};
elseif iscell(s.(name)),items=s.(name)(:).';
else,items=arrayfun(@(x)x,s.(name),'UniformOutput',false);end
end
function value=logical_field(s,name)
value=isstruct(s)&&isfield(s,name)&&isscalar(s.(name))&&logical(s.(name));
end
function v=getp(block,param),v='';try,v=get_param(char(block),param);catch,end,end
function tf=identity_ok(spec,scenario)
tf=isstruct(spec)&&isscalar(spec)&&isfield(spec,'id') ...
    &&string(spec.id)=="D022"&&string(scenario)=="nominal";
end
function tf=has_fixture(state)
tf=isstruct(state)&&isscalar(state)&&isfield(state,'evidence') ...
    &&isstruct(state.evidence)&&isfield(state.evidence,'unit_test_facts');
end
function f=empty_facts()
f=struct('power_branch_report',struct(),'power_branch_ownership',false, ...
    'ballast_converter_roots',strings(0,1), ...
    'active_ballast_actuators',strings(0,1), ...
    'physical_measurement_sources',strings(0,1),'actuator_rows',struct([]), ...
    'feedback_signal_paths',{{}},'control_computation_blocks',{{}}, ...
    'physical_feedback_present',false, ...
    'measurement_reaches_active_ballast',false, ...
    'control_computation_on_path',false,'same_ballast_stage_owned',false, ...
    'all_active_ballast_actuators_owned',false, ...
    'active_ballast_stage_coverage',0,'algorithm_constraint',"none");
end
function r=make_report(evaluated,valid,ok,detail,evidence)
r=struct('task',"D022",'id',"D022.closed_loop_ballast_ownership", ...
    'kind',"task_specific",'semantic_kind',"structure",'scenario',"nominal", ...
    'layer',"qualification",'evaluated',logical(evaluated),'mandatory',true, ...
    'ok',logical(ok),'valid',logical(valid),'score',double(ok), ...
    'detail',string(detail),'evidence',evidence);
end
