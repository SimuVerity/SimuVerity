function report=sat_check_D006_vdc_vsc_terminal_ownership( ...
    modelName,spec,scenarioId,simOut,signals,baseReports,state) %#ok<INUSD>
%SAT_CHECK_D006_VDC_VSC_TERMINAL_OWNERSHIP Bind Vdc to the active VSC rails.
% The Vdc output trace owns the measurement selection.  The existing
% task-declared PCC path owns the active converter set.  This evaluator then
% independently proves, at conserving-port level, that the two measurement
% terminals span the two distinct DC rails feeding that same converter set.

[identityOk,identityReason]=identity_valid(spec,scenarioId);
if ~identityOk
    report=invalid_report(identityReason,struct());return;
end
[measurement,measurementReason]=vdc_measurement(baseReports);
if strlength(measurement)==0
    report=invalid_report(measurementReason,struct());return;
end
[rawActiveBlocks,activeReason]=active_vsc_blocks(baseReports);
if isempty(rawActiveBlocks)
    report=invalid_report(activeReason,struct('measurement_block',measurement));return;
end
try
    G=task_graph(modelName,state);
catch ex
    report=invalid_report("GRAPH_UNAVAILABLE:"+string(ex.identifier), ...
        struct('measurement_block',measurement, ...
        'raw_active_vsc_source_matches',rawActiveBlocks));return;
end

% physical_path reports every block whose five-field descriptor matches the
% source pattern.  In a linked SPS device, descendant implementation blocks
% inherit a ReferenceBlock path such as ".../MOSFET/..."; consequently
% signal-only Add/Selector blocks and nested copies of the same switch can
% appear in source_matches.  They are recognizer diagnostics, not distinct
% power devices.  Keep only matches that themselves expose at least two
% conserving terminals, then collapse nested implementations to the
% outermost conserving device boundary.  This remains neutral to MOSFET,
% IGBT, ideal-switch and packaged-bridge representations.
try
    [activeBlocks,excludedActiveBlocks]=active_power_terminal_blocks(G,rawActiveBlocks);
catch ex
    evidence=struct('measurement_block',measurement, ...
        'raw_active_vsc_source_matches',rawActiveBlocks, ...
        'resolution_error',string(ex.message));
    report=invalid_report("ACTIVE_VSC_POWER_TERMINAL_RESOLUTION_ERROR:"+ ...
        string(ex.identifier),evidence);return;
end
if isempty(activeBlocks)
    evidence=struct('measurement_block',measurement, ...
        'raw_active_vsc_source_matches',rawActiveBlocks, ...
        'excluded_active_vsc_source_matches',excludedActiveBlocks);
    report=invalid_report("ACTIVE_VSC_POWER_TERMINALS_UNRESOLVED",evidence);return;
end

try
    physical=find(string({G.nodes.network})=="physical");
    sensorNodes=physical(string({G.nodes(physical).block})==measurement);
    activeNodes=physical(ismember(string({G.nodes(physical).block}),activeBlocks));
catch ex
    evidence=struct('measurement_block',measurement, ...
        'active_vsc_blocks',activeBlocks,'resolution_error',string(ex.message));
    report=invalid_report("ACTIVE_VSC_NODE_RESOLUTION_ERROR:"+ ...
        string(ex.identifier),evidence);return;
end
if numel(sensorNodes)~=2
    evidence=struct('measurement_block',measurement,'active_vsc_blocks',activeBlocks, ...
        'measurement_terminal_count',numel(sensorNodes));
    report=invalid_report("MEASUREMENT_TERMINALS_NOT_UNIQUE",evidence);return;
end
if isempty(activeNodes)||any(~ismember(activeBlocks, ...
        unique(string({G.nodes(activeNodes).block}))))
    evidence=struct('measurement_block',measurement,'active_vsc_blocks',activeBlocks, ...
        'active_terminal_count',numel(activeNodes));
    report=invalid_report("ACTIVE_VSC_TERMINALS_UNRESOLVED",evidence);return;
end

try
    railA=measurement_rail(G,sensorNodes(1));railB=measurement_rail(G,sensorNodes(2));
    aActive=intersect(railA,activeNodes);bActive=intersect(railB,activeNodes);
    aBlocks=unique(string({G.nodes(aActive).block}),'stable');aBlocks=aBlocks(:);
    bBlocks=unique(string({G.nodes(bActive).block}),'stable');bBlocks=bBlocks(:);
catch ex
    evidence=struct('measurement_block',measurement, ...
        'active_vsc_blocks',activeBlocks,'resolution_error',string(ex.message));
    report=invalid_report("VDC_RAIL_RESOLUTION_ERROR:"+ ...
        string(ex.identifier),evidence);return;
end
ownershipMethod="graph_net";
% Old SPS drawings can encode a branched conserving net as geometry-only
% line fragments.  PortConnectivity is the authoritative Simulink fact in
% that case.  It is used only to augment the two already-identified sensor
% terminals, and may cross an ideal current sensor but no energy component.
if ~(isstruct(state)&&isfield(state,'evidence') ...
        &&isstruct(state.evidence)&&isfield(state.evidence,'unit_test_graph'))
    [liveRails,liveOk]=live_measurement_rails(measurement);
    if liveOk
        aBlocks=unique([aBlocks(:);intersect(liveRails{1},activeBlocks)],'stable');
        bBlocks=unique([bBlocks(:);intersect(liveRails{2},activeBlocks)],'stable');
        ownershipMethod="graph_net_plus_port_connectivity";
    end
end
covered=unique([aBlocks(:);bBlocks(:)],'stable');
railsDistinct=isempty(intersect(railA,railB));
allActiveOnRails=isequal(sort(covered),sort(activeBlocks(:)));
if isstruct(state)&&isfield(state,'evidence')&&isstruct(state.evidence) ...
        &&isfield(state.evidence,'unit_test_feedback')
    loop=state.evidence.unit_test_feedback;
    loopValid=isstruct(loop)&&isscalar(loop) ...
        &&isfield(loop,'feedback_reaches_active_stage') ...
        &&isfield(loop,'all_active_stages_owned') ...
        &&isfield(loop,'gate_source_blocks');
    if ~loopValid
        report=invalid_report("VDC_FEEDBACK_FACT_SCHEMA_INVALID",struct());return;
    end
else
    try
        loop=vdc_feedback_ownership(G,measurement,activeBlocks);
    catch ex
        evidence=struct('measurement_block',measurement, ...
            'active_vsc_blocks',activeBlocks,'resolution_error',string(ex.message));
        report=invalid_report("VDC_FEEDBACK_RESOLUTION_ERROR:"+ ...
            string(ex.identifier),evidence);return;
    end
end
feedbackOk=logical(loop.feedback_reaches_active_stage) ...
    &&logical(loop.all_active_stages_owned)&&~isempty(loop.gate_source_blocks);
ok=railsDistinct&&~isempty(aBlocks)&&~isempty(bBlocks)&&allActiveOnRails&&feedbackOk;
if ok,detail="OK";
elseif ~railsDistinct,detail="MEASUREMENT_TERMINALS_SHORTED_TO_ONE_RAIL";
elseif isempty(aBlocks)||isempty(bBlocks),detail="VDC_SENSOR_DOES_NOT_SPAN_BOTH_ACTIVE_VSC_RAILS";
elseif ~allActiveOnRails,detail="ACTIVE_VSC_SET_NOT_OWNED_BY_MEASURED_DC_LINK";
elseif isempty(loop.gate_source_blocks),detail="ACTIVE_VSC_GATE_SOURCE_MISSING";
elseif ~logical(loop.feedback_reaches_active_stage),detail="VDC_MEASUREMENT_DOES_NOT_REACH_ACTIVE_VSC_GATES";
else,detail="VDC_FEEDBACK_DOES_NOT_OWN_ALL_ACTIVE_VSC_STAGES";
end
evidence=struct('measurement_block',measurement, ...
    'raw_active_vsc_source_matches',rawActiveBlocks, ...
    'excluded_active_vsc_source_matches',excludedActiveBlocks, ...
    'active_vsc_blocks',activeBlocks, ...
    'measurement_terminal_nodes',double(sensorNodes), ...
    'rail_a_active_blocks',aBlocks,'rail_b_active_blocks',bBlocks, ...
    'ownership_method',ownershipMethod, ...
    'rails_distinct',logical(railsDistinct), ...
    'all_active_vsc_blocks_on_measured_rails',logical(allActiveOnRails), ...
    'gate_source_blocks',string(loop.gate_source_blocks(:)), ...
    'vdc_feedback_gate_paths',{loop.feedback_gate_paths}, ...
    'active_stage_feedback_ownership',logical(loop.active_stage_feedback_ownership), ...
    'vdc_feedback_reaches_active_stage',logical(loop.feedback_reaches_active_stage), ...
    'all_active_stages_feedback_owned',logical(loop.all_active_stages_owned), ...
    'measurement_terminal_count',numel(sensorNodes), ...
    'active_terminal_count',numel(activeNodes));
report=make_report(true,true,ok,detail,evidence);
end

function loop=vdc_feedback_ownership(G,measurement,stages)
% The same physical Vdc sensor accepted by the output contract must also
% influence every active switch boundary on the measured DC link.  No
% controller form, coordinate system or PWM implementation is prescribed.
G=close_signal_subsystems(G);gates=gate_source_endpoints(stages,G);
gateSources=string({gates.source_block})';gateStages=string({gates.stage_block})';
paths=cell(numel(gates),1);hits=false(numel(gates),1);
for i=1:numel(gates)
    [hits(i),paths{i}]=signal_reaches(G,measurement,gates(i).source_node);
end
owned=false(numel(stages),1);
for i=1:numel(stages)
    owned(i)=any(hits(gateStages==stages(i)));
end
loop=struct('gate_source_blocks',gateSources,'feedback_gate_paths',{paths}, ...
    'active_stage_feedback_ownership',owned, ...
    'feedback_reaches_active_stage',any(hits), ...
    'all_active_stages_owned',~isempty(stages)&&all(owned));
end

function rows=gate_source_endpoints(stages,G)
rows=struct('stage_block',{},'source_block',{},'source_node',{});keys=strings(0,1);
for stage=string(stages(:))'
    try,pc=get_param(char(stage),'PortConnectivity');catch,continue;end
    for i=1:numel(pc)
        if contains(lower(string(pc(i).Type)),"conn"),continue;end
        hs=double(pc(i).SrcBlock(:));ports=double(pc(i).SrcPort(:));
        for k=1:numel(hs)
            if hs(k)<=0,continue;end
            port=1;if numel(ports)>=k&&isfinite(ports(k)),port=ports(k)+1;end
            block=string(getfullname(hs(k)));
            ids=find(string({G.nodes.network})=="signal" ...
                &string({G.nodes.block})==block ...
                &strcmpi(string({G.nodes.port_field}),"Outport") ...
                &[G.nodes.port_ordinal]==port);
            if numel(ids)~=1,continue;end
            key=stage+"|"+block+"|"+string(port);
            if any(keys==key),continue;end
            keys(end+1,1)=key; %#ok<AGROW>
            rows(end+1)=struct('stage_block',stage, ...
                'source_block',block,'source_node',ids); %#ok<AGROW>
        end
    end
end
end

function [ok,path]=signal_reaches(G,source,targetNode)
q=struct('network',"signal",'direction',"forward", ...
    'source',struct('block',source,'port_field',"Outport",'port_ordinal',1), ...
    'target',struct('node_id',targetNode));
[ok,e]=sat_graph_query(G,q);path={};
if ok&&isstruct(e)&&isfield(e,'block_path'),path=cellstr(string(e.block_path));end
end

function G=close_signal_subsystems(G)
blocks=unique(string({G.nodes.block}),'stable');
for b=blocks(:)'
    ids=find([G.nodes.block]==b);sig=ids([G.nodes(ids).network]=="signal");
    phy=ids([G.nodes(ids).network]=="physical");
    if ~isempty(phy)||isempty(sig),continue;end
    try
        bt=string(get_param(char(b),'BlockType'));
        mt=string(get_param(char(b),'MaskType'));
        rb=string(get_param(char(b),'ReferenceBlock'));
    catch,continue;end
    if bt~="SubSystem",continue;end
    trustedLinked=strlength(strtrim(rb))>0;
    goldenPwmCompatibility=strcmpi(strtrim(mt),"Discrete PWM Generator");
    if ~trustedLinked&&~goldenPwmCompatibility,continue;end
    fields=lower(string({G.nodes(sig).port_field}));
    ins=sig(contains(fields,"in"));outs=sig(contains(fields,"out"));
    for x=ins(:)',for y=outs(:)'
        if any(G.signal_forward{x}==y),continue;end
        G.signal_forward{x}(end+1)=y;
        G.signal_forward_edge_kinds{x}{end+1}='signal_subsystem_potential';
    end,end
end
end

function [blocks,excluded]=active_power_terminal_blocks(G,raw)
% Resolve source recognizer diagnostics to distinct physical power-device
% boundaries.  Exact block ownership prevents an ancestor name/reference
% from turning its signal-processing descendants into fake switches.
raw=unique(string(raw(:)),'stable');candidates=strings(0,1);
physical=find(string({G.nodes.network})=="physical");
for i=1:numel(raw)
    ids=physical(string({G.nodes(physical).block})==raw(i));
    if numel(ids)>=2
        handles=double([G.nodes(ids).port_handle]);
        if numel(unique(handles(isfinite(handles)&handles>0)))>=2
            candidates(end+1,1)=raw(i); %#ok<AGROW>
        end
    end
end

% Process shallow boundaries first.  A candidate is nested only when the
% separator is a real hierarchy slash, so e.g. Mosfet is not the ancestor
% of Mosfet1.
if isempty(candidates)
    blocks=strings(0,1);excluded=raw;return;
end
[~,order]=sort(arrayfun(@(x)count(x,"/"),candidates));
candidates=candidates(order);blocks=strings(0,1);
for i=1:numel(candidates)
    nested=false;
    for j=1:numel(blocks)
        if startsWith(candidates(i),blocks(j)+"/")
            nested=true;break;
        end
    end
    if ~nested,blocks(end+1,1)=candidates(i);end %#ok<AGROW>
end
blocks=unique(blocks,'stable');excluded=setdiff(raw,blocks,'stable');
end

function [rails,ok]=live_measurement_rails(block)
rails={strings(0,1),strings(0,1)};ok=false;
try,pc=get_param(char(block),'PortConnectivity');catch,return;end
physical=find(arrayfun(@(x)contains(lower(string(x.Type)),"conn"),pc));
if numel(physical)~=2,return;end
for i=1:2
    direct=connected_blocks(pc(physical(i)));expanded=direct;
    for j=1:numel(direct)
        if is_current_sensor(direct(j))
            try,sensorPc=get_param(char(direct(j)),'PortConnectivity');catch,continue;end
            sensorPhysical=find(arrayfun(@(x)contains(lower(string(x.Type)),"conn"),sensorPc));
            for q=sensorPhysical(:)'
                expanded=[expanded;connected_blocks(sensorPc(q))]; %#ok<AGROW>
            end
        end
    end
    rails{i}=unique(expanded(expanded~=block),'stable');
end
ok=true;
end
function blocks=connected_blocks(pc)
blocks=strings(0,1);handles=double([pc.SrcBlock(:);pc.DstBlock(:)]);
for h=handles(:)'
    if h<=0,continue;end
    try,blocks(end+1,1)=string(getfullname(h));catch,end %#ok<AGROW>
end
blocks=unique(blocks,'stable');
end
function ok=is_current_sensor(block)
parts=strings(0,1);
for p={'Name','BlockType','MaskType','ReferenceBlock'}
    try,parts(end+1)=string(get_param(char(block),p{1}));catch,end %#ok<AGROW>
end
d=lower(strjoin(parts,"|"));ok=contains(d,"current measurement");
end

function [ok,reason]=identity_valid(spec,scenarioId)
ok=isstruct(spec)&&isscalar(spec)&&isfield(spec,'id') ...
    &&isscalar(string(spec.id))&&string(spec.id)=="D006" ...
    &&isscalar(string(scenarioId))&&string(scenarioId)=="nominal";
if ok,reason="OK";else,reason="TASK_OR_SCENARIO_IDENTITY_MISMATCH";end
end

function [block,reason]=vdc_measurement(base)
block="";reason="VDC_OUTPUT_TRACE_MISSING";reports=field_items(base,'output_reports');matches={};
for i=1:numel(reports)
    r=reports{i};
    if ~isstruct(r)||~isscalar(r)||~isfield(r,'name')||string(r.name)~="Vdc",continue;end
    if ~isfield(r,'trace')||~isstruct(r.trace)||~isscalar(r.trace) ...
            ||~isfield(r.trace,'path')||~isscalar(string(r.trace.path)),continue;end
    descriptor=trace_descriptor(r.trace);
    if isempty(regexpi(char(descriptor),'voltage (measurement|sensor)','once')),continue;end
    matches{end+1}=r.trace; %#ok<AGROW>
end
if isempty(matches),return;end
if numel(matches)~=1,reason="VDC_OUTPUT_TRACE_AMBIGUOUS";return;end
block=string(matches{1}.path);reason="OK";
end

function [blocks,reason]=active_vsc_blocks(base)
blocks=strings(0,1);reason="ACTIVE_VSC_PCC_REPORT_MISSING";reports=field_items(base,'struct_reports');matches={};
for i=1:numel(reports)
    r=reports{i};
    if isstruct(r)&&isscalar(r)&&isfield(r,'id') ...
            &&string(r.id)=="vsc_coupling_to_pcc",matches{end+1}=r;end %#ok<AGROW>
end
if isempty(matches),return;end
if numel(matches)~=1,reason="ACTIVE_VSC_PCC_REPORT_AMBIGUOUS";return;end
r=matches{1};
if ~isfield(r,'ok')||~logical01(r.ok)||~logical(r.ok) ...
        ||~isfield(r,'evidence')||~isstruct(r.evidence)||~isscalar(r.evidence) ...
        ||~isfield(r.evidence,'source_matches')
    reason="ACTIVE_VSC_PCC_EVIDENCE_INVALID";return;
end
blocks=string(r.evidence.source_matches(:));blocks=blocks(strlength(blocks)>0);
if isempty(blocks)||numel(unique(blocks))~=numel(blocks)
    blocks=strings(0,1);reason="ACTIVE_VSC_SOURCE_SET_INVALID";return;
end
reason="OK";
end

function rail=measurement_rail(G,start)
% DC rail continuity may pass through an ideal current sensor, but never
% through switching/energy components.  This is the task-owned distinction
% between one electrical net and mere whole-circuit connectivity.
n=numel(G.nodes);seen=false(1,n);seen(start)=true;queue=start;
while ~isempty(queue)
    x=queue(1);queue(1)=[];
    for j=1:numel(G.physical_undirected{x})
        y=G.physical_undirected{x}(j);kind=string(G.physical_edge_kinds{x}{j});
        allowed=kind=="physical_net"||kind=="subsystem_boundary";
        if kind=="component_internal"&&string(G.nodes(x).block)==string(G.nodes(y).block)
            d=lower(string(G.nodes(x).descriptor));
            allowed=(contains(d,"current measurement")||contains(d,"current sensor")) ...
                &&~contains(d,"voltage measurement")&&~contains(d,"voltage sensor");
        end
        if allowed&&~seen(y),seen(y)=true;queue(end+1)=y;end %#ok<AGROW>
    end
end
rail=find(seen);
end

function G=task_graph(modelName,state)
if isstruct(state)&&isscalar(state)&&isfield(state,'evidence') ...
        &&isstruct(state.evidence)&&isscalar(state.evidence) ...
        &&isfield(state.evidence,'unit_test_graph')
    G=state.evidence.unit_test_graph;return;
end
G=sat_model_graph(char(string(modelName)));
end
function items=field_items(s,name)
if ~isstruct(s)||~isscalar(s)||~isfield(s,name)||isempty(s.(name)),items={};
elseif iscell(s.(name)),items=s.(name)(:).';
else,items=arrayfun(@(x)x,s.(name),'UniformOutput',false);end
end
function d=trace_descriptor(trace)
parts=strings(0,1);
for f={'name','block_type','mask_type','reference_block','descriptor'}
    if isfield(trace,f{1}),parts(end+1)=string(trace.(f{1}));end %#ok<AGROW>
end
d=lower(strjoin(parts,"|"));
end
function value=logical01(x)
value=isscalar(x)&&(islogical(x)||(isnumeric(x)&&isreal(x)&&isfinite(x)&&(x==0||x==1)));
end
function report=invalid_report(detail,evidence)
report=make_report(false,false,false,detail,evidence);
end
function r=make_report(evaluated,valid,ok,detail,evidence)
r=struct('task',"D006",'id',"D006.vdc_vsc_terminal_ownership", ...
    'kind',"task_specific",'semantic_kind',"structure",'scenario',"nominal", ...
    'layer',"qualification",'evaluated',logical(evaluated),'mandatory',true, ...
    'ok',logical(ok),'valid',logical(valid),'score',double(ok), ...
    'detail',string(detail),'evidence',evidence);
end
