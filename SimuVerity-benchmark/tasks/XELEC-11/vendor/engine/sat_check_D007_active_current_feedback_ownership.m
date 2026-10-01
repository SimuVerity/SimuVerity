function report=sat_check_D007_active_current_feedback_ownership( ...
    modelName,spec,scenarioId,simOut,signals,baseReports,state) %#ok<INUSD>
%SAT_CHECK_D007_ACTIVE_CURRENT_FEEDBACK_OWNERSHIP D007 loop ownership.
% Algorithm-neutral contract: both public current commands and at least one
% physical current sensor on the real converter/reactor/grid branch must
% have potential causal paths to the same active gate.  The feedback sensor
% may be equivalent to, rather than literally the same block as, the three
% logged Igrid sensors.  No dq/PI/PWM form is required.

if ~identity_ok(spec,scenarioId)
    report=make_report(false,false,false,"TASK_OR_SCENARIO_IDENTITY_MISMATCH",struct());return;
end
if has_fixture(state)
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

function [facts,valid,reason]=extract_facts(model,base,state)
facts=empty_facts();valid=false;reason="";
[dcPath,ok,why]=path_report(base,"dc_converter_to_grid");if ~ok,reason=why;return;end
[reactorPath,ok,why]=path_report(base,"bridge_to_grid_through_reactor");if ~ok,reason=why;return;end
[idSources,ok,why]=input_bindings(base,"Id_ref_cmd");if ~ok,reason=why;return;end
[iqSources,ok,why]=input_bindings(base,"Iq_ref_cmd");if ~ok,reason=why;return;end
[loggedCurrentSources,ok,why]=current_outputs(base);if ~ok,reason=why;return;end

dcCandidates=unique([string(dcPath.evidence.path(:)); ...
    evidence_blocks(dcPath.evidence,'via_matches')],'stable');
reactorCandidates=unique([string(reactorPath.evidence.path(:)); ...
    evidence_blocks(reactorPath.evidence,'source_matches')],'stable');
dcActive=controllable_subset(dcCandidates);reactorActive=controllable_subset(reactorCandidates);
active=intersect(dcActive,reactorActive,'stable');
if isempty(active),reason="ACTIVE_CONVERTER_STAGE_UNRESOLVED";return;end

gateSources=strings(0,1);gateStages=strings(0,1);
for b=active(:)'
    src=gate_source_blocks(b);
    gateSources=[gateSources;src(:)];gateStages=[gateStages;repmat(b,numel(src),1)]; %#ok<AGROW>
end
if isempty(gateSources),reason="ACTIVE_STAGE_GATE_SOURCE_MISSING";return;end
[gateSources,ix]=unique(gateSources,'stable');gateStages=gateStages(ix);

G=task_graph(model,state);
reactors=reactor_subset(evidence_blocks(reactorPath.evidence,'via_matches'));
[igridOwned,igridPhysicalPaths]=physical_branch_ownership_many( ...
    G,active,reactors,loggedCurrentSources);
igridOnBranch=all(igridOwned)&&numel(loggedCurrentSources)>=3;
feedbackCandidates=current_measurement_blocks(G);
[feedbackOwned,feedbackPhysicalPaths]=physical_branch_ownership_many( ...
    G,active,reactors,feedbackCandidates);
feedbackSources=feedbackCandidates(feedbackOwned);
G=close_signal_subsystems(G);
joint=false(size(gateSources));idPaths=cell(size(gateSources));
iqPaths=cell(size(gateSources));currentPaths=cell(size(gateSources));
for i=1:numel(gateSources)
    [idOk,idPaths{i}]=any_signal_reaches(G,idSources,gateSources(i));
    [iqOk,iqPaths{i}]=any_signal_reaches(G,iqSources,gateSources(i));
    [curOk,currentPaths{i}]=any_signal_reaches(G,feedbackSources,gateSources(i));
    joint(i)=idOk&&iqOk&&curOk;
end
facts.active_stage_blocks=active;facts.gate_source_blocks=gateSources;
facts.gate_owned_stage_blocks=gateStages;facts.id_command_source=idSources;
facts.iq_command_source=iqSources;facts.current_measurement_source=feedbackSources;
facts.id_gate_paths=idPaths;facts.iq_gate_paths=iqPaths;
facts.current_feedback_gate_paths=currentPaths;facts.joint_gate_mask=joint;
stageOwned=false(size(active));
for i=1:numel(active),stageOwned(i)=any(joint(gateStages==active(i)));end
facts.active_stage_joint_ownership=stageOwned;
facts.active_stage_coverage=sum(stageOwned)/max(numel(stageOwned),1);
facts.dc_to_grid_path=true;facts.reactor_path=true;
facts.igrid_physical_current=true;
facts.igrid_on_active_power_path=igridOnBranch;
facts.igrid_physical_path=igridPhysicalPaths;
facts.feedback_physical_paths=feedbackPhysicalPaths;
facts.id_reaches_active_stage=any(cellfun(@(x)~isempty(x),idPaths));
facts.iq_reaches_active_stage=any(cellfun(@(x)~isempty(x),iqPaths));
facts.current_feedback_reaches_active_stage=any(cellfun(@(x)~isempty(x),currentPaths));
facts.commands_and_feedback_share_active_gate=any(joint);
facts.all_active_stages_owned=all(stageOwned);
valid=true;reason="OK";
end

function [schemaOk,ok,detail]=verdict(f)
required={'active_stage_blocks','gate_source_blocks','id_command_source', ...
    'iq_command_source','current_measurement_source','dc_to_grid_path','reactor_path', ...
    'igrid_physical_current','igrid_on_active_power_path', ...
    'id_reaches_active_stage','iq_reaches_active_stage', ...
    'current_feedback_reaches_active_stage','commands_and_feedback_share_active_gate', ...
    'all_active_stages_owned'};
schemaOk=isstruct(f)&&isscalar(f)&&all(isfield(f,required));
if ~schemaOk,ok=false;detail="FACT_SCHEMA_INVALID";return;end
ok=logical(f.dc_to_grid_path)&&logical(f.reactor_path)&&logical(f.igrid_physical_current) ...
    &&logical(f.igrid_on_active_power_path) ...
    &&logical(f.id_reaches_active_stage)&&logical(f.iq_reaches_active_stage) ...
    &&logical(f.current_feedback_reaches_active_stage) ...
    &&logical(f.commands_and_feedback_share_active_gate) ...
    &&logical(f.all_active_stages_owned) ...
    &&~isempty(f.active_stage_blocks)&&~isempty(f.gate_source_blocks);
if ok,detail="OK";
elseif ~logical(f.igrid_physical_current),detail="IGRID_PHYSICAL_CURRENT_PROVENANCE_FAILED";
elseif ~logical(f.igrid_on_active_power_path),detail="IGRID_MEASUREMENT_NOT_ON_ACTIVE_REACTOR_BRANCH";
elseif ~logical(f.id_reaches_active_stage),detail="ID_REF_CMD_DOES_NOT_REACH_ACTIVE_STAGE";
elseif ~logical(f.iq_reaches_active_stage),detail="IQ_REF_CMD_DOES_NOT_REACH_ACTIVE_STAGE";
elseif ~logical(f.current_feedback_reaches_active_stage),detail="MEASURED_CURRENT_FEEDBACK_DOES_NOT_REACH_ACTIVE_STAGE";
elseif ~logical(f.commands_and_feedback_share_active_gate),detail="COMMANDS_AND_FEEDBACK_DO_NOT_OWN_SAME_ACTIVE_GATE";
elseif ~logical(f.all_active_stages_owned),detail="ACTIVE_STAGE_GATE_OWNERSHIP_INCOMPLETE";
else,detail="ACTIVE_POWER_PATH_OR_GATE_MISSING";end
end

function [r,ok,reason]=path_report(base,id)
r=[];ok=false;reason=upper(id)+"_REPORT_MISSING";items=field_items(base,'struct_reports');matches={};
for i=1:numel(items)
    x=items{i};if isstruct(x)&&isfield(x,'id')&&string(x.id)==id,matches{end+1}=x;end %#ok<AGROW>
end
if numel(matches)~=1,if numel(matches)>1,reason=upper(id)+"_REPORT_AMBIGUOUS";end;return;end
r=matches{1};
if ~logical_field(r,'ok')||~isfield(r,'evidence')||~isfield(r.evidence,'path')
    reason=upper(id)+"_FAILED";return;
end
ok=true;reason="OK";
end
function blocks=evidence_blocks(e,name)
blocks=strings(0,1);if isstruct(e)&&isfield(e,name),blocks=string(e.(name)(:));end
blocks=blocks(strlength(blocks)>0);
end
function [blocks,ok,reason]=current_outputs(base)
blocks=strings(0,1);ok=false;reason="IGRID_PHYSICAL_CURRENT_TRACE_MISSING";
items=field_items(base,'output_reports');matches={};
for i=1:numel(items)
    r=items{i};if ~isstruct(r)||~isfield(r,'name')||string(r.name)~="Igrid" ...
            ||~logical_field(r,'ok')||~logical_field(r,'provenance_ok') ...
            ||~isfield(r,'trace')||~isstruct(r.trace)||isempty(r.trace),continue;end
    hasCurrent=false;
    for q=1:numel(r.trace)
        if ~isempty(regexpi(char(trace_descriptor(r.trace(q))), ...
                'current (measurement|sensor)','once')),hasCurrent=true;break;end
    end
    if ~hasCurrent,continue;end
    matches{end+1}=r.trace; %#ok<AGROW>
end
if numel(matches)~=1,if numel(matches)>1,reason="IGRID_PHYSICAL_CURRENT_TRACE_AMBIGUOUS";end;return;end
trace=matches{1};
for i=1:numel(trace)
    d=trace_descriptor(trace(i));
    if ~isempty(regexpi(char(d),'current (measurement|sensor)','once'))
        blocks(end+1,1)=string(trace(i).path); %#ok<AGROW>
    end
end
blocks=unique(blocks,'stable');
if numel(blocks)<3,reason="IGRID_THREE_PHASE_CURRENT_ENDPOINTS_MISSING";return;end
ok=true;reason="OK";
end
function d=trace_descriptor(trace)
parts=strings(0,1);for f={'name','block_type','mask_type','reference_block','descriptor'}
    if isfield(trace,f{1}),parts(end+1)=string(trace.(f{1}));end %#ok<AGROW>
end;d=lower(strjoin(parts,"|"));
end
function [blocks,ok,reason]=input_bindings(base,name)
blocks=strings(0,1);ok=false;reason=name+"_BINDING_MISSING";items=field_items(base,'input_reports');values=strings(0,1);
for i=1:numel(items)
    r=items{i};if ~isstruct(r)||~isfield(r,'name')||string(r.name)~=name ...
            ||~logical_field(r,'ok')||~isfield(r,'bindings'),continue;end
    values=[values;binding_strings(r.bindings)]; %#ok<AGROW>
end
values=unique(values(strlength(values)>0),'stable');
for i=1:numel(values)
    parts=split(values(i),"::");
    if numel(parts)==2,blocks(end+1,1)=parts(1);end %#ok<AGROW>
end
blocks=unique(blocks,'stable');
if isempty(blocks),reason=name+"_BINDING_SCHEMA_INVALID";return;end
ok=true;reason="OK";
end
function values=binding_strings(raw)
if ischar(raw),values=string(raw);elseif iscell(raw),values=string(raw(:));else,values=string(raw(:));end
end
function tf=is_controllable_stage(block)
d=trusted_descriptor(block);device=lower(string(getp(block,'Device')));
tf=contains(d,"igbt")||contains(d,"mosfet")||contains(d,"gto") ...
    ||contains(d,"ideal switch")||contains(d,"three-level bridge") ...
    ||contains(device,"igbt")||contains(device,"mosfet")||contains(device,"gto");
end
function blocks=controllable_subset(candidates)
blocks=strings(0,1);for b=string(candidates(:))'
    if is_controllable_stage(b),blocks(end+1,1)=b;end %#ok<AGROW>
end
% A linked semiconductor exposes many inherited implementation blocks whose
% trusted ReferenceBlock still contains the device name.  Treat only the
% outermost matching block as the physical stage; otherwise one MOSFET is
% incorrectly counted once for every internal helper block.
blocks=topmost_blocks(unique(blocks,'stable'));
end
function out=topmost_blocks(blocks)
out=strings(0,1);blocks=string(blocks(:));
for i=1:numel(blocks)
    b=blocks(i);ancestor=false;
    for j=1:numel(blocks)
        if i==j,continue;end
        p=blocks(j)+"/";
        if startsWith(b,p),ancestor=true;break;end
    end
    if ~ancestor,out(end+1,1)=b;end %#ok<AGROW>
end
end
function blocks=reactor_subset(candidates)
blocks=strings(0,1);for b=string(candidates(:))'
    d=trusted_descriptor(b);
    if contains(d,"inductor")||contains(d,"series rlc branch"),blocks(end+1,1)=b;end %#ok<AGROW>
end;blocks=unique(blocks,'stable');
end
function [ok,path]=physical_branch_ownership(G,stages,reactors,current)
ok=false;path=strings(0,1);if isempty(stages)||isempty(reactors)||strlength(current)==0,return;end
q=struct('network',"physical",'direction',"undirected", ...
    'source',{exact_selectors(stages)},'target',struct('block',current));
q.via={exact_selectors(reactors)};[ok,e]=sat_graph_query(G,q);
if ok&&isfield(e,'block_path'),path=string(e.block_path(:));end
end
function [owned,paths]=physical_branch_ownership_many(G,stages,reactors,currents)
currents=string(currents(:));owned=false(size(currents));paths=cell(size(currents));
for i=1:numel(currents)
    [owned(i),paths{i}]=physical_branch_ownership(G,stages,reactors,currents(i));
end
end
function blocks=current_measurement_blocks(G)
blocks=strings(0,1);all=unique(string({G.nodes.block}),'stable');
for b=all(:)'
    ix=find([G.nodes.block]==b);d=lower(strjoin(string({G.nodes(ix).descriptor}),"|"));
    if contains(d,"current measurement")||contains(d,"current sensor")
        if any([G.nodes(ix).network]=="physical")&&any([G.nodes(ix).network]=="signal")
            blocks(end+1,1)=b; %#ok<AGROW>
        end
    end
end
blocks=topmost_blocks(unique(blocks,'stable'));
end
function selectors=exact_selectors(blocks)
selectors=cell(1,numel(blocks));for i=1:numel(blocks),selectors{i}=struct('block',blocks(i));end
end
function d=trusted_descriptor(block)
parts=strings(0,1);for p={'BlockType','MaskType','ReferenceBlock'}
    try,parts(end+1)=string(get_param(char(block),p{1}));catch,end %#ok<AGROW>
end;d=lower(strjoin(parts,"|"));
end
function blocks=gate_source_blocks(stage)
blocks=strings(0,1);try,pc=get_param(char(stage),'PortConnectivity');catch,return;end
for i=1:numel(pc)
    if contains(lower(string(pc(i).Type)),"conn"),continue;end
    for h=double(pc(i).SrcBlock(:))',if h>0,blocks(end+1,1)=string(getfullname(h));end,end %#ok<AGROW>
end;blocks=unique(blocks,'stable');
end
function [ok,path]=signal_reaches(G,source,target)
q=struct('network',"signal",'direction',"forward", ...
    'source',struct('block',source),'target',struct('block',target));
[ok,e]=sat_graph_query(G,q);path={};
if ok&&isfield(e,'block_path'),path=cellstr(string(e.block_path));end
end
function [ok,path]=any_signal_reaches(G,sources,target)
ok=false;path={};
for source=string(sources(:))'
    [hit,p]=signal_reaches(G,source,target);
    if hit,ok=true;path=p;return;end
end
end
function G=close_signal_subsystems(G)
blocks=unique(string({G.nodes.block}),'stable');
for b=blocks(:)'
    ids=find([G.nodes.block]==b);sig=ids([G.nodes(ids).network]=="signal");
    phy=ids([G.nodes(ids).network]=="physical");if ~isempty(phy)||isempty(sig),continue;end
    try,bt=string(get_param(char(b),'BlockType'));catch,continue;end
    if bt~="SubSystem",continue;end
    fields=lower(string({G.nodes(sig).port_field}));ins=sig(contains(fields,"in"));outs=sig(contains(fields,"out"));
    for x=ins(:)',for y=outs(:)'
        if any(G.signal_forward{x}==y),continue;end
        G.signal_forward{x}(end+1)=y;G.signal_forward_edge_kinds{x}{end+1}='signal_subsystem_potential';
    end,end
end
end
function G=task_graph(model,state)
if isstruct(state)&&isfield(state,'model_graph')&&isstruct(state.model_graph) ...
        &&isfield(state.model_graph,'schema')&&string(state.model_graph.schema)=="simuverity.sat-model-graph.v1"
    G=state.model_graph;else,G=sat_model_graph(char(string(model)));end
end
function items=field_items(s,name)
if ~isstruct(s)||~isscalar(s)||~isfield(s,name)||isempty(s.(name)),items={};
elseif iscell(s.(name)),items=s.(name)(:).';else,items=arrayfun(@(x)x,s.(name),'UniformOutput',false);end
end
function value=logical_field(s,name),value=isstruct(s)&&isfield(s,name)&&isscalar(s.(name))&&logical(s.(name));end
function v=getp(block,param),v='';try,v=get_param(char(block),param);catch,end,end
function tf=identity_ok(spec,scenario),tf=isstruct(spec)&&isscalar(spec)&&isfield(spec,'id')&&string(spec.id)=="D007"&&string(scenario)=="nominal";end
function tf=has_fixture(state),tf=isstruct(state)&&isscalar(state)&&isfield(state,'evidence')&&isstruct(state.evidence)&&isfield(state.evidence,'unit_test_facts');end
function f=empty_facts()
f=struct('active_stage_blocks',strings(0,1),'gate_source_blocks',strings(0,1), ...
    'gate_owned_stage_blocks',strings(0,1),'id_command_source',"", ...
    'iq_command_source',"",'current_measurement_source',"", ...
    'id_gate_paths',{{}},'iq_gate_paths',{{}},'current_feedback_gate_paths',{{}}, ...
    'joint_gate_mask',false(0,1),'active_stage_joint_ownership',false(0,1), ...
    'active_stage_coverage',0,'dc_to_grid_path',false,'reactor_path',false, ...
    'igrid_physical_current',false,'igrid_on_active_power_path',false, ...
    'igrid_physical_path',{{}},'feedback_physical_paths',{{}}, ...
    'id_reaches_active_stage',false, ...
    'iq_reaches_active_stage',false,'current_feedback_reaches_active_stage',false, ...
    'commands_and_feedback_share_active_gate',false,'all_active_stages_owned',false);
end
function r=make_report(evaluated,valid,ok,detail,evidence)
r=struct('task',"D007",'id',"D007.active_current_feedback_ownership", ...
    'kind',"task_specific",'semantic_kind',"structure",'scenario',"nominal", ...
    'layer',"qualification",'evaluated',logical(evaluated),'mandatory',true, ...
    'ok',logical(ok),'valid',logical(valid),'score',double(ok), ...
    'detail',string(detail),'evidence',evidence);
end
