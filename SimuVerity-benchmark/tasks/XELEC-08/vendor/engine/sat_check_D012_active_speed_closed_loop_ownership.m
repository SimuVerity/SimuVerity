function report=sat_check_D012_active_speed_closed_loop_ownership( ...
    modelName,spec,scenarioId,simOut,signals,baseReports,state) %#ok<INUSD>
%SAT_CHECK_D012_ACTIVE_SPEED_CLOSED_LOOP_OWNERSHIP D012 loop ownership.
% The public contract requires physical rotor-speed feedback, but does not
% prescribe PI, SVPWM, an error Sum block, or a coordinate system.  This
% checker therefore proves only that Wref_cmd and the provenance-qualified
% Wm endpoint both causally reach a gate source of the real inverter stage.

if ~identity_ok(spec,scenarioId)
    report=make_report(false,false,false,"TASK_OR_SCENARIO_IDENTITY_MISMATCH",struct());return;
end
if has_test_facts(state)
    facts=state.evidence.unit_test_facts;valid=true;reason="OK";
else
    try,[facts,valid,reason]=extract_facts(modelName,baseReports,state);
    catch ex
        report=make_report(false,false,false,"EXTRACTION_ERROR:"+string(ex.identifier),struct());return;
    end
end
if ~valid,report=make_report(false,false,false,reason,facts);return;end
[schemaOk,ok,detail]=verdict(facts);
report=make_report(true,schemaOk,ok,detail,facts);
end

function [facts,valid,reason]=extract_facts(modelName,base,state)
facts=empty_facts();valid=false;reason="";
[stages,machines,ok,why]=active_stage_machine(base);
if ~ok,reason=why;return;end
[references,ok,why]=input_bindings(base,"Wref_cmd");if ~ok,reason=why;return;end
[speedSource,ok,why]=speed_endpoint(base);if ~ok,reason=why;return;end
gateSources=strings(0,1);
for b=stages(:)',gateSources=[gateSources;gate_source_blocks(b)];end %#ok<AGROW>
gateSources=unique(gateSources,'stable');
if isempty(gateSources),reason="ACTIVE_STAGE_GATE_SOURCE_MISSING";return;end

G=task_graph(modelName,state);joint=false(size(gateSources));
refPaths=cell(numel(references),numel(gateSources));speedPaths=cell(size(gateSources));
for i=1:numel(gateSources)
    refOk=false;
    for q=1:numel(references)
        [hit,refPaths{q,i}]=signal_reaches(G,references(q),gateSources(i));
        refOk=refOk||hit;
    end
    [speedOk,speedPaths{i}]=signal_reaches(G,speedSource,gateSources(i));
    joint(i)=refOk&&speedOk;
end
facts.active_stage_blocks=stages;facts.machine_blocks=machines;
facts.reference_source=references;facts.speed_measurement_source=speedSource;
facts.gate_source_blocks=gateSources;facts.reference_gate_paths=refPaths;
facts.speed_gate_paths=speedPaths;facts.active_power_path=true;
facts.reference_reaches_active_stage=any(cellfun(@(x)~isempty(x),refPaths));
facts.speed_feedback_reaches_active_stage=any(cellfun(@(x)~isempty(x),speedPaths));
facts.reference_and_feedback_share_active_stage=any(joint);
facts.active_stage_has_gate_input=~isempty(gateSources);
valid=true;reason="OK";
end

function [schemaOk,ok,detail]=verdict(f)
required={'active_stage_blocks','machine_blocks','reference_source', ...
    'speed_measurement_source','gate_source_blocks','active_power_path', ...
    'reference_reaches_active_stage','speed_feedback_reaches_active_stage', ...
    'reference_and_feedback_share_active_stage','active_stage_has_gate_input'};
schemaOk=isstruct(f)&&isscalar(f)&&all(isfield(f,required));
if ~schemaOk,ok=false;detail="FACT_SCHEMA_INVALID";return;end
ok=logical(f.active_power_path)&&logical(f.active_stage_has_gate_input) ...
    &&logical(f.reference_reaches_active_stage) ...
    &&logical(f.speed_feedback_reaches_active_stage) ...
    &&logical(f.reference_and_feedback_share_active_stage) ...
    &&~isempty(f.active_stage_blocks)&&~isempty(f.machine_blocks);
if ok,detail="OK";
elseif ~logical(f.active_power_path),detail="ACTIVE_INVERTER_TO_MOTOR_PATH_MISSING";
elseif ~logical(f.reference_reaches_active_stage),detail="WREF_CMD_DOES_NOT_REACH_ACTIVE_POWER_STAGE";
elseif ~logical(f.speed_feedback_reaches_active_stage),detail="PHYSICAL_SPEED_FEEDBACK_DOES_NOT_REACH_ACTIVE_POWER_STAGE";
elseif ~logical(f.reference_and_feedback_share_active_stage),detail="REFERENCE_AND_FEEDBACK_DO_NOT_OWN_THE_SAME_ACTIVE_STAGE";
else,detail="ACTIVE_STAGE_GATE_SOURCE_MISSING";end
end

function [stages,machines,ok,reason]=active_stage_machine(base)
stages=strings(0,1);machines=strings(0,1);ok=false;
reason="DC_LINK_INVERTER_MOTOR_PATH_MISSING";
r=one_report(base,'struct_reports',"dc_link_inverter_motor");
if isempty(r)||~logical_field(r,'ok')||~isfield(r,'evidence')||~isfield(r.evidence,'path'),return;end
path=string(r.evidence.path(:));
for p=path(:)'
    if is_controllable_stage(p),stages(end+1,1)=p;end %#ok<AGROW>
    d=descriptor(p);
    if contains(d,"asynchronous machine")||contains(d,"induction motor"),machines(end+1,1)=p;end %#ok<AGROW>
end
stages=unique(stages,'stable');machines=unique(machines,'stable');
if isempty(stages)||isempty(machines),reason="ACTIVE_STAGE_OR_INDUCTION_MOTOR_UNRESOLVED";return;end
ok=true;reason="OK";
end

function [source,ok,reason]=speed_endpoint(base)
source="";ok=false;reason="WM_PHYSICAL_TRACE_MISSING";reports=field_items(base,'output_reports');matches={};
for i=1:numel(reports)
    r=reports{i};
    if isstruct(r)&&isfield(r,'name')&&string(r.name)=="Wm" ...
            &&logical_field(r,'ok')&&logical_field(r,'provenance_ok')&&isfield(r,'trace')
        matches{end+1}=r; %#ok<AGROW>
    end
end
if numel(matches)~=1,if numel(matches)>1,reason="WM_OUTPUT_TRACE_AMBIGUOUS";end;return;end
trace=matches{1}.trace;if ~isstruct(trace)||isempty(trace),return;end
depth=inf(1,numel(trace));paths=strings(1,numel(trace));
for i=1:numel(trace)
    if isfield(trace(i),'depth'),depth(i)=double(trace(i).depth);end
    if isfield(trace(i),'path'),paths(i)=string(trace(i).path);end
end
candidates=unique(paths(depth==min(depth)&strlength(paths)>0),'stable');
if numel(candidates)~=1,reason="WM_MEASUREMENT_ENDPOINT_NOT_UNIQUE";return;end
source=candidates;ok=true;reason="OK";
end

function tf=is_controllable_stage(block)
d=descriptor(block);dev=lower(string(getp(block,'Device')));
tf=contains(d,"igbt")||contains(d,"mosfet")||contains(d,"gto") ...
    ||contains(d,"ideal switch")||contains(d,"three-level bridge") ...
    ||(contains(d,"universal bridge")&&~contains(dev,"diode")) ...
    ||contains(dev,"igbt")||contains(dev,"mosfet")||contains(dev,"gto");
end
function blocks=gate_source_blocks(stage)
blocks=strings(0,1);try,pc=get_param(char(stage),'PortConnectivity');catch,return;end
for i=1:numel(pc)
    if contains(lower(string(pc(i).Type)),"conn"),continue;end
    for h=double(pc(i).SrcBlock(:))',if h>0,blocks(end+1,1)=string(getfullname(h));end,end %#ok<AGROW>
end
blocks=unique(blocks,'stable');
end
function [ok,path]=signal_reaches(G,source,target)
if source==target,ok=true;path={char(source)};return;end
q=struct('network',"signal",'direction',"forward", ...
    'source',struct('block',source),'target',struct('block',target));
[ok,e]=sat_graph_query(G,q);path={};
if ~ok,G=close_signal_subsystems(G);[ok,e]=sat_graph_query(G,q);end
if ok&&isstruct(e)&&isfield(e,'block_path'),path=cellstr(string(e.block_path));end
end
function G=close_signal_subsystems(G)
blocks=unique(string({G.nodes.block}),'stable');
for b=blocks(:)'
    ids=find([G.nodes.block]==b);sig=ids([G.nodes(ids).network]=="signal");
    phy=ids([G.nodes(ids).network]=="physical");
    if ~isempty(phy)||isempty(sig),continue;end
    try,bt=string(get_param(char(b),'BlockType'));catch,continue;end
    if bt~="SubSystem",continue;end
    fields=lower(string({G.nodes(sig).port_field}));
    ins=sig(contains(fields,"in"));outs=sig(contains(fields,"out"));
    for x=ins(:)',for y=outs(:)'
        if any(G.signal_forward{x}==y),continue;end
        G.signal_forward{x}(end+1)=y;
        G.signal_forward_edge_kinds{x}{end+1}='signal_subsystem_potential';
    end,end
end
end
function G=task_graph(modelName,state)
if isstruct(state)&&isfield(state,'model_graph')&&isstruct(state.model_graph) ...
        &&isfield(state.model_graph,'schema')&&string(state.model_graph.schema)=="simuverity.sat-model-graph.v1"
    G=state.model_graph;
else,G=sat_model_graph(char(string(modelName)));end
end
function [blocks,ok,reason]=input_bindings(base,name)
blocks=strings(0,1);ok=false;reason=name+"_BINDING_MISSING";reports=field_items(base,'input_reports');bindings=strings(0,1);
for i=1:numel(reports)
    r=reports{i};if isstruct(r)&&isfield(r,'name')&&string(r.name)==name ...
            &&logical_field(r,'ok')&&isfield(r,'bindings'),bindings=[bindings;binding_strings(r.bindings)];end %#ok<AGROW>
end
bindings=unique(bindings(strlength(bindings)>0),'stable');
if isempty(bindings),return;end
for i=1:numel(bindings)
    parts=split(bindings(i),"::");
    if numel(parts)~=2||strlength(parts(1))==0
        blocks=strings(0,1);reason=name+"_BINDING_SCHEMA_INVALID";return;
    end
    blocks(end+1,1)=parts(1); %#ok<AGROW>
end
blocks=unique(blocks,'stable');ok=~isempty(blocks);reason="OK";
end
function values=binding_strings(raw)
if ischar(raw),values=string(raw);
elseif iscell(raw),values=string(raw(:));
else,values=string(raw(:));end
values=values(strlength(values)>0);
end
function r=one_report(base,collection,id)
r=[];items=field_items(base,collection);m={};
for i=1:numel(items),if isstruct(items{i})&&isfield(items{i},'id')&&string(items{i}.id)==id,m{end+1}=items{i};end,end %#ok<AGROW>
if numel(m)==1,r=m{1};end
end
function d=descriptor(block)
parts=strings(0,1);for p={'Name','BlockType','MaskType','ReferenceBlock'},try,parts(end+1)=string(get_param(char(block),p{1}));catch,end,end %#ok<AGROW>
d=lower(strjoin(parts,"|"));
end
function v=getp(block,param),v='';try,v=get_param(char(block),param);catch,end,end
function value=logical_field(s,name),value=isstruct(s)&&isfield(s,name)&&isscalar(s.(name))&&logical(s.(name));end
function items=field_items(s,name)
if ~isstruct(s)||~isscalar(s)||~isfield(s,name)||isempty(s.(name)),items={};
elseif iscell(s.(name)),items=s.(name)(:).';
else,items=arrayfun(@(x)x,s.(name),'UniformOutput',false);end
end
function tf=identity_ok(spec,scenario),tf=isstruct(spec)&&isfield(spec,'id')&&string(spec.id)=="D012"&&string(scenario)=="nominal";end
function tf=has_test_facts(state),tf=isstruct(state)&&isfield(state,'evidence')&&isstruct(state.evidence)&&isfield(state.evidence,'unit_test_facts');end
function f=empty_facts()
f=struct('active_stage_blocks',strings(0,1),'machine_blocks',strings(0,1), ...
    'reference_source',"",'speed_measurement_source',"", ...
    'gate_source_blocks',strings(0,1),'reference_gate_paths',{{}}, ...
    'speed_gate_paths',{{}},'active_power_path',false, ...
    'reference_reaches_active_stage',false,'speed_feedback_reaches_active_stage',false, ...
    'reference_and_feedback_share_active_stage',false,'active_stage_has_gate_input',false);
end
function r=make_report(evaluated,valid,ok,detail,evidence)
r=struct('task',"D012",'id',"D012.active_speed_closed_loop_ownership", ...
    'kind',"task_specific",'semantic_kind',"structure",'scenario',"nominal", ...
    'layer',"qualification",'evaluated',logical(evaluated),'mandatory',true, ...
    'ok',logical(ok),'valid',logical(valid),'score',double(ok),'detail',string(detail), ...
    'evidence',evidence);
end
