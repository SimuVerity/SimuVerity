function report=sat_check_D011_active_svpwm_gate_ownership( ...
    modelName,spec,scenarioId,simOut,signals,baseReports,state) %#ok<INUSD>
%SAT_CHECK_D011_ACTIVE_SVPWM_GATE_OWNERSHIP D011 command ownership.
% The public task does not require SVPWM or any particular controller
% decomposition.  The source function/report id is retained for public reports
% compatibility, but the verdict is now representation-neutral: F_cmd must
% causally reach a gate input of the real controllable stage feeding the PMSM.

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
[commands,ok,why]=input_bindings(base,"F_cmd");if ~ok,reason=why;return;end
gateSources=strings(0,1);ownedStages=strings(0,1);
for b=stages(:)'
    src=gate_source_blocks(b);
    if ~isempty(src),gateSources=[gateSources;src(:)];ownedStages(end+1,1)=b;end %#ok<AGROW>
end
gateSources=unique(gateSources,'stable');ownedStages=unique(ownedStages,'stable');
if isempty(gateSources),reason="ACTIVE_STAGE_GATE_SOURCE_MISSING";return;end
G=task_graph(modelName,state);reaches=false(numel(commands),numel(gateSources));
paths=cell(numel(commands),numel(gateSources));
for c=1:numel(commands)
for i=1:numel(gateSources)
    [reaches(c,i),paths{c,i}]=signal_reaches(G,commands(c),gateSources(i));
end
end
facts.active_stage_blocks=stages;facts.machine_blocks=machines;
facts.command_source=commands;facts.gate_source_blocks=gateSources;
facts.gate_owned_stage_blocks=ownedStages;facts.command_gate_paths=paths;
facts.active_power_path=true;facts.command_reaches_active_stage=any(reaches);
facts.active_stage_has_gate_input=~isempty(gateSources);
valid=true;reason="OK";
end

function [schemaOk,ok,detail]=verdict(f)
required={'active_stage_blocks','machine_blocks','command_source', ...
    'gate_source_blocks','active_power_path','command_reaches_active_stage', ...
    'active_stage_has_gate_input'};
schemaOk=isstruct(f)&&isscalar(f)&&all(isfield(f,required));
if ~schemaOk,ok=false;detail="FACT_SCHEMA_INVALID";return;end
ok=logical(f.active_power_path)&&logical(f.active_stage_has_gate_input) ...
    &&logical(f.command_reaches_active_stage) ...
    &&~isempty(f.active_stage_blocks)&&~isempty(f.machine_blocks);
if ok,detail="OK";
elseif ~logical(f.active_power_path),detail="ACTIVE_INVERTER_TO_PMSM_PATH_MISSING";
elseif ~logical(f.active_stage_has_gate_input),detail="ACTIVE_STAGE_GATE_SOURCE_MISSING";
else,detail="F_CMD_DOES_NOT_REACH_ACTIVE_POWER_STAGE";end
end

function [stages,machines,ok,reason]=active_stage_machine(base)
stages=strings(0,1);machines=strings(0,1);ok=false;
reason="ACTIVE_MACHINE_POWER_PATH_MISSING";
r=one_report(base,'struct_reports',"inverter_to_pmsm");
if isempty(r)||~logical_field(r,'ok')||~isfield(r,'evidence') ...
        ||~isfield(r.evidence,'path'),return;end
path=string(r.evidence.path(:));
for p=path(:)'
    if is_controllable_stage(p),stages(end+1,1)=p;end %#ok<AGROW>
    d=descriptor(p);
    if contains(d,"permanent magnet")&&contains(d,"machine"),machines(end+1,1)=p;end %#ok<AGROW>
end
stages=unique(stages,'stable');machines=unique(machines,'stable');
if isempty(stages)||isempty(machines),reason="ACTIVE_STAGE_OR_PMSM_UNRESOLVED";return;end
ok=true;reason="OK";
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
    for h=double(pc(i).SrcBlock(:))'
        if h>0,blocks(end+1,1)=string(getfullname(h));end %#ok<AGROW>
    end
end
blocks=unique(blocks,'stable');
end

function [ok,path]=signal_reaches(G,source,target)
if source==target,ok=true;path={source};return;end
q=struct('network',"signal",'direction',"forward", ...
    'source',struct('block',source),'target',struct('block',target));
[ok,e]=sat_graph_query(G,q);path={};
if ~ok
    % MATLAB Function and controller subsystems are opaque to the shared
    % wiring graph.  Closing only signal-only subsystem interiors proves
    % potential command ownership without crossing a physical power stage.
    G=close_signal_subsystems(G);[ok,e]=sat_graph_query(G,q);
end
if isstruct(e)&&isfield(e,'block_path'),path=cellstr(string(e.block_path));end
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
    r=reports{i};
    if isstruct(r)&&isfield(r,'name')&&string(r.name)==name&&logical_field(r,'ok')&&isfield(r,'bindings')
        bindings=[bindings;binding_strings(r.bindings)]; %#ok<AGROW>
    end
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
for i=1:numel(items)
    if isstruct(items{i})&&isfield(items{i},'id')&&string(items{i}.id)==id,m{end+1}=items{i};end %#ok<AGROW>
end
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
function tf=identity_ok(spec,scenario),tf=isstruct(spec)&&isscalar(spec)&&isfield(spec,'id')&&string(spec.id)=="D011"&&string(scenario)=="nominal";end
function tf=has_test_facts(state),tf=isstruct(state)&&isscalar(state)&&isfield(state,'evidence')&&isstruct(state.evidence)&&isfield(state.evidence,'unit_test_facts');end
function f=empty_facts()
f=struct('active_stage_blocks',strings(0,1),'machine_blocks',strings(0,1), ...
    'command_source',"",'gate_source_blocks',strings(0,1), ...
    'gate_owned_stage_blocks',strings(0,1),'command_gate_paths',{{}}, ...
    'active_power_path',false,'command_reaches_active_stage',false, ...
    'active_stage_has_gate_input',false);
end
function r=make_report(evaluated,valid,ok,detail,evidence)
r=struct('task',"D011",'id',"D011.active_svpwm_gate_ownership", ...
    'kind',"task_specific",'semantic_kind',"structure",'scenario',"nominal", ...
    'layer',"qualification",'evaluated',logical(evaluated),'mandatory',true, ...
    'ok',logical(ok),'valid',logical(valid),'score',double(ok),'detail',string(detail), ...
    'evidence',evidence);
end
