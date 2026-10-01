function report=sat_check_D025_active_power_feedback_ownership( ...
    modelName,spec,scenarioId,simOut,signals,baseReports,state) %#ok<INUSD>
%SAT_CHECK_D025_ACTIVE_POWER_FEEDBACK_OWNERSHIP D025 actuator proof.
% The stable identifier is retained, but the predicate no longer requires
% PLL, dq, PI/PID, PQ-regulator or three-level-PWM block roles.  It only
% binds the public P_ref_kW command to controllable devices on the proven
% DC-to-grid path; behavior/provenance score synchronization and Pgrid.

report=base_report(scenarioId);report.evaluated=true;
if ~isstruct(spec)||~isfield(spec,'id')||string(spec.id)~="D025" ...
        ||string(scenarioId)~="nominal"
    report.detail="TASK_OR_SCENARIO_IDENTITY_MISMATCH";return;
end
[baseOk,baseRows]=required_base_reports(baseReports,[ ...
    "discrete_three_level_cells","three_phase_power_stage", ...
    "dc_to_grid_power_path","no_universal_bridge"]);
if isstruct(modelName)&&isfield(modelName,'schema') ...
        &&string(modelName.schema)=="D025.semantic-fixture"
    report=evaluate_fixture(report,modelName,baseOk,baseRows);return;
end
try,G=sat_model_graph(modelName);catch ex
    report.detail="GRAPH_BUILD_ERROR:"+string(ex.identifier);return;
end
[prefBlocks,bindingOk,bindingReason]=input_bindings(baseReports,"P_ref_kW");
if ~bindingOk
    report.detail=bindingReason;report.evidence=struct('base_reports',baseRows);return;
end
[physicalReport,physicalOk]=one_struct_report(baseReports,"dc_to_grid_power_path");
if ~physicalOk||~isfield(physicalReport,'evidence') ...
        ||~isfield(physicalReport.evidence,'via_matches')
    report.detail="DC_TO_GRID_PATH_EVIDENCE_INVALID";return;
end
% Foundation-domain IGBTs receive their gates through physical-signal ports,
% not ordinary Simulink Inports.  The generic graph deliberately does not
% guess that mixed-domain semantics.  Use the task-owned native NPC proof;
% source SPS/golden implementations continue through the established path.
native=sat_check_D025_foundation_npc(modelName,G,prefBlocks);
if native.applicable
    report.valid=logical(baseOk&&bindingOk&&native.valid);
    report.ok=logical(report.valid&&native.ok);report.score=double(report.ok);
    report.evidence=struct('base_reports',baseRows,'P_ref_bindings',prefBlocks, ...
        'proof_mode',"foundation_native_npc",'native_npc',native, ...
        'candidate_actuators',native.switch_blocks, ...
        'active_actuators',native.switch_blocks, ...
        'active_actuator_count',numel(native.switch_blocks), ...
        'active_actuator_coverage',native.gate_coverage, ...
        'live_actuators',native.switch_blocks, ...
        'live_actuator_count',numel(native.switch_blocks), ...
        'live_gate_rows',native.gate_rows, ...
        'physical_via_matches',string(physicalReport.evidence.via_matches(:)), ...
        'command_paths',native.gate_rows,'command_coverage',native.gate_coverage, ...
        'algorithm_constraint',"none");
    if ~baseOk
        report.detail="D025_BASE_POWER_STAGE_CONTRACT_FAILED";
    elseif ~native.ok
        report.detail=native.detail;
    else
        report.detail="OK";
    end
    return;
end
candidateActive=stage_actuator_interfaces(G,physicalReport.evidence);
[live,liveRows]=live_actuator_interfaces(G,candidateActive);
[commandRows,covered]=command_ownership(G,prefBlocks,live);
active=live(logical([commandRows.command_reaches]));
report.valid=logical(baseOk&&bindingOk&&numel(live)>=3);
report.ok=logical(report.valid&&covered==numel(live));report.score=double(report.ok);
report.evidence=struct('base_reports',baseRows,'P_ref_bindings',prefBlocks, ...
    'proof_mode',"source_sps", ...
    'candidate_actuators',candidateActive, ...
    'active_actuators',active,'active_actuator_count',numel(active), ...
    'active_actuator_coverage',numel(active), ...
    'live_actuators',live,'live_actuator_count',numel(live), ...
    'live_gate_rows',liveRows, ...
    'physical_via_matches',string(physicalReport.evidence.via_matches(:)), ...
    'command_paths',commandRows, ...
    'command_coverage',covered,'algorithm_constraint',"none");
if ~baseOk,report.detail="D025_BASE_POWER_STAGE_CONTRACT_FAILED";
elseif numel(live)<3,report.detail="ACTIVE_GRID_POWER_ACTUATORS_UNRESOLVED";
elseif covered<numel(live),report.detail="PREF_TO_ACTIVE_STAGE_LINEAGE_INCOMPLETE";
else,report.detail="OK";end
end

function blocks=stage_actuator_interfaces(G,evidence)
% Enumerate trusted controllable power interfaces at any hierarchy depth.
% A candidate must be in the recognizer's via set and in the same supported
% physical component as both a reported source and target.  This avoids the
% former top-level-only assumption without accepting decorative devices.
via=normalise_report_blocks(evidence.via_matches);
src=strings(0,1);dst=strings(0,1);
if isfield(evidence,'source_matches'),src=normalise_report_blocks(evidence.source_matches);end
if isfield(evidence,'target_matches'),dst=normalise_report_blocks(evidence.target_matches);end
srcReach=physical_reach(G,blocks_to_nodes(G,src,"physical"));
dstReach=physical_reach(G,blocks_to_nodes(G,dst,"physical"));
blocks=strings(0,1);all=unique(string({G.nodes.block}),'stable');
for b=all(:)'
    ix=find([G.nodes.block]==b);d=lower(strjoin(string({G.nodes(ix).descriptor}),"|"));
    if isempty(regexpi(char(d),'igbt|mosfet|\bgto\b|ideal switch','once')),continue;end
    phys=ix([G.nodes(ix).network]=="physical");
    sigin=ix([G.nodes(ix).network]=="signal" ...
        &contains(lower(string({G.nodes(ix).port_field})),"in"));
    if isempty(phys)||isempty(sigin)||~any(via==b),continue;end
    if any(srcReach(phys))&&any(dstReach(phys)),blocks(end+1,1)=b;end %#ok<AGROW>
end
blocks=unique(blocks,'stable');
end

function [live,rows]=live_actuator_interfaces(G,candidates)
live=strings(0,1);rows=struct('actuator',{},'live',{},'upstream_blocks',{});
for i=1:numel(candidates)
    [ok,upstream]=has_live_gate_lineage(G,candidates(i));
    rows(end+1)=struct('actuator',candidates(i),'live',logical(ok), ... %#ok<AGROW>
        'upstream_blocks',upstream);
    if ok,live(end+1,1)=candidates(i);end %#ok<AGROW>
end
end

function [rows,coverage]=command_ownership(G,prefBlocks,actuators)
% Hierarchy-neutral ownership proof.  Direct graph causality is preferred.
% If an opaque controller boundary prevents an interior proof, any subsystem
% at any depth is accepted as an owner only when P_ref reaches one of its
% external inputs and one of its external outputs reaches the real gate.
prefNodes=blocks_to_nodes(G,prefBlocks,"signal");prefReach=signal_reach(G,prefNodes);
owners=unique(string({G.nodes.block}),'stable');ownerRows=struct('block',{},'reach',{});
for b=owners(:)'
    try,isSub=strcmpi(get_param(char(b),'BlockType'),'SubSystem');catch,isSub=false;end
    if ~isSub,continue;end
    in=signal_field_nodes(G,b,"in");out=signal_field_nodes(G,b,"out");
    if isempty(in)||isempty(out)||~any(prefReach(in)),continue;end
    ownerRows(end+1)=struct('block',b,'reach',signal_reach(G,out)); %#ok<AGROW>
end
rows=struct('actuator',{},'command_reaches',{},'owner',{},'direct',{});coverage=0;
for i=1:numel(actuators)
    gate=signal_field_nodes(G,actuators(i),"in");direct=any(prefReach(gate));
    hit="";
    if ~direct
        for j=1:numel(ownerRows)
            if any(ownerRows(j).reach(gate)),hit=ownerRows(j).block;break;end
        end
    end
    ok=direct||strlength(hit)>0;coverage=coverage+double(ok);
    rows(end+1)=struct('actuator',actuators(i),'command_reaches',logical(ok), ... %#ok<AGROW>
        'owner',hit,'direct',logical(direct));
end
end

function [ok,blocks]=has_live_gate_lineage(G,actuator)
gate=signal_field_nodes(G,actuator,"in");seen=signal_reverse_reach(G,gate);
ix=find(seen);blocks=unique(string({G.nodes(ix).block}),'stable');ok=false;
for i=ix(:)'
    if string(G.nodes(i).block)==actuator,continue;end
    d=lower(string(G.nodes(i).descriptor));
    if isempty(regexpi(char(d),'\|constant\||\|ground\||\|terminator\||\|from\||\|goto\||\|inport\||\|outport\||\|mux\||\|demux\|','once'))
        ok=true;break;
    end
end
end

function reach=signal_reach(G,start),reach=graph_reach(G.signal_forward,start,numel(G.nodes));end
function reach=signal_reverse_reach(G,start),reach=graph_reach(G.signal_reverse,start,numel(G.nodes));end
function reach=physical_reach(G,start),reach=graph_reach(G.physical_undirected,start,numel(G.nodes));end
function seen=graph_reach(adj,start,n)
seen=false(1,n);queue=unique(double(start(:)'));queue=queue(queue>=1&queue<=n);seen(queue)=true;
while ~isempty(queue)
    x=queue(1);queue(1)=[];
    for y=adj{x},if ~seen(y),seen(y)=true;queue(end+1)=y;end,end %#ok<AGROW>
end
end
function ids=blocks_to_nodes(G,blocks,network)
ids=[];for b=string(blocks(:))',ids=[ids find([G.nodes.block]==b ...
        &[G.nodes.network]==network)];end;ids=unique(ids); %#ok<AGROW>
end
function ids=signal_field_nodes(G,block,kind)
ids=find([G.nodes.block]==block&[G.nodes.network]=="signal");
f=lower(string({G.nodes(ids).port_field}));
if kind=="in",ids=ids(contains(f,"in")|f=="enable"|f=="trigger"); ...
else,ids=ids(contains(f,"out")|f=="state");end
end
function blocks=normalise_report_blocks(values)
blocks=string(values(:));
% sat_model_graph labels ports as block[field#n]; the source physical
% path reporter stores plain blocks.  Accept either representation.
blocks=regexprep(blocks,'\[[^\]]+#\d+\]$','');
blocks=unique(blocks(strlength(blocks)>0),'stable');
end

function report=evaluate_fixture(report,f,baseOk,baseRows)
count=numel(f.actuator_blocks);coverage=0;
for i=1:min(count,numel(f.lineage_descriptors))
    d=lower(string(f.lineage_descriptors{i}));
    coverage=coverage+double(any(contains(d,"p_ref")|contains(d,"pref")));
end
report.valid=logical(baseOk&&count>=3);
report.ok=logical(report.valid&&coverage==count);report.score=double(report.ok);
report.evidence=struct('base_reports',baseRows,'active_actuator_count',count, ...
    'active_actuator_coverage',coverage,'actuator_blocks',f.actuator_blocks, ...
    'algorithm_constraint',"none");
if ~baseOk,report.detail="D025_BASE_POWER_STAGE_CONTRACT_FAILED";
elseif count<3,report.detail="ACTIVE_GRID_POWER_ACTUATORS_UNRESOLVED";
elseif coverage<count,report.detail="PREF_TO_ACTIVE_STAGE_LINEAGE_INCOMPLETE";
else,report.detail="OK";end
end

function [blocks,ok,reason]=input_bindings(base,name)
blocks=strings(0,1);ok=false;reason=name+"_BINDING_MISSING";
items=field_items(base,'input_reports');values=strings(0,1);
for i=1:numel(items)
    r=items{i};
    if isstruct(r)&&isfield(r,'name')&&string(r.name)==name&&logical(r.ok)&&isfield(r,'bindings')
        x=r.bindings;if ischar(x)||(isstring(x)&&isscalar(x)),values(end+1)=string(x); ...
        elseif iscell(x),values=[values;string(x(:))];else,values=[values;string(x(:))];end %#ok<AGROW>
    end
end
for v=values(:)'
    p=split(v,"::");if numel(p)==2,blocks(end+1,1)=p(1);end %#ok<AGROW>
end
blocks=unique(blocks,'stable');ok=~isempty(blocks);
if ok,reason="OK";end
end
function [ok,rows]=required_base_reports(base,ids)
ok=true;rows=struct('id',{},'found',{},'passed',{});items=field_items(base,'struct_reports');
for i=1:numel(ids)
    hit=find(cellfun(@(x)isfield(x,'id')&&string(x.id)==ids(i),items));
    passed=numel(hit)==1&&logical(items{hit}.ok);
    rows(end+1)=struct('id',ids(i),'found',numel(hit)==1,'passed',logical(passed)); %#ok<AGROW>
    ok=ok&&passed;
end
end
function [r,ok]=one_struct_report(base,id)
r=[];ok=false;items=field_items(base,'struct_reports');hit={};
for i=1:numel(items)
    if isfield(items{i},'id')&&string(items{i}.id)==id,hit{end+1}=items{i};end %#ok<AGROW>
end
if numel(hit)==1,r=hit{1};ok=true;end
end
function items=field_items(s,name)
if ~isstruct(s)||~isfield(s,name)||isempty(s.(name)),items={};
elseif iscell(s.(name)),items=s.(name)(:).';
else,items=arrayfun(@(x)x,s.(name),'UniformOutput',false);end
end
function r=base_report(scenario)
r=struct('task',"D025",'id',"D025.active_power_feedback_ownership", ...
    'kind',"task_specific",'semantic_kind',"structure",'scenario',string(scenario), ...
    'layer',"qualification",'evaluated',false,'mandatory',true,'ok',false, ...
    'valid',false,'score',0,'detail',"UNINITIALIZED",'evidence',struct());
end
