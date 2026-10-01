function report=sat_check_D014_measured_power_path_ownership_core( ...
    modelName,spec,scenarioId,simOut,signals,baseReports,state) %#ok<INUSD>
%SAT_CHECK_D014_MEASURED_POWER_PATH_OWNERSHIP_CORE D014 power-path ownership.
% The public contract fixes the physical conversion sequence, measured
% three-phase terminal, and closed-loop output-voltage regulation.  It does
% not prescribe a bridge library block, modulation method, controller form,
% coordinate system, sensor packaging, hierarchy, or load implementation.

if string(scenarioId)~="nominal",report=struct([]);return;end
if ~isstruct(spec)||~isscalar(spec)||~isfield(spec,'id')||string(spec.id)~="D014"
    report=make_report(false,false,false,"TASK_IDENTITY_MISMATCH",struct());return;
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

function [facts,valid,reason]=extract_facts(modelName,base,state)
facts=empty_facts();valid=false;reason="";
[pathReport,ok,why]=unique_report(base,'struct_reports',"source_through_conversion_to_measured_output");
if ~ok,reason=why;return;end
if ~logical_field(pathReport,'ok')||~isfield(pathReport,'evidence') ...
        ||~isstruct(pathReport.evidence)||~isfield(pathReport.evidence,'path')
    reason="SOURCE_TO_LOAD_POWER_PATH_FAILED";return;
end
path=string(pathReport.evidence.path(:));path=path(strlength(path)>0);
if isempty(path),reason="SOURCE_TO_LOAD_POWER_PATH_EMPTY";return;end

[dcReport,ok,why]=unique_report(base,'struct_reports',"dc_link_storage");
if ~ok,reason=why;return;end
[vdc,ok,why]=output_facts(base,"Vdc",1);if ~ok,reason=why;return;end
[vabc,ok,why]=output_facts(base,"Vabc",3);if ~ok,reason=why;return;end
[iabc,ok,why]=output_facts(base,"Iabc",3);if ~ok,reason=why;return;end

% Assign the two conversion roles from the actual DC-link ownership, not
% from block counts or names.  The Vdc sensor defines the candidate pair of
% DC rails.  A valid pair must be reached from both terminals of a physical
% single-phase source through a front conversion network, must feed three
% output phases through an active conversion network, and must have real
% capacitive storage connected across it.  Packaged bridges and networks of
% discrete devices are treated identically.
[power,ok,why]=shared_dc_link_ownership(modelName,state,pathReport, ...
    vdc.trace_blocks,vabc.trace_blocks);
if ~ok,reason=why;return;end

facts.energy_path_blocks=path;
facts.rectifier_blocks=power.rectifier_blocks;
facts.controllable_inverter_blocks=power.inverter_blocks;
facts.rectifier_precedes_inverter=power.rectifier_source_to_dc_bus ...
    &&power.dc_bus_feeds_active_inverter;
facts.shared_dc_bus_pair=power.shared_dc_bus_pair;
facts.rectifier_source_to_dc_bus=power.rectifier_source_to_dc_bus;
facts.front_has_pure_passive_bypass=power.front_has_pure_passive_bypass;
facts.dc_bus_feeds_active_inverter=power.dc_bus_feeds_active_inverter;
facts.dc_link_storage_on_shared_bus=power.dc_link_storage_on_shared_bus;
facts.dc_bus_net_ids=power.dc_bus_net_ids;
facts.dc_link_storage_blocks=power.dc_link_storage_blocks;
facts.rectifier_source_paths=power.rectifier_source_paths;
facts.dc_bus_inverter_paths=power.dc_bus_inverter_paths;
facts.dc_link_storage_present=logical_field(dcReport,'ok') ...
    &&power.dc_link_storage_on_shared_bus;
facts.vdc_physical_measurement=vdc.physical;
facts.vabc_physical_measurement=vabc.physical;
facts.iabc_physical_measurement=iabc.physical;
facts.vabc_channels=vabc.channels;facts.iabc_channels=iabc.channels;
facts.vabc_distinct_origins=vabc.distinct;facts.iabc_distinct_origins=iabc.distinct;
facts.iabc_measurement_on_energy_path=any(ismember(path,iabc.trace_blocks));
if ~(power.shared_dc_bus_pair&&power.rectifier_source_to_dc_bus ...
        &&power.dc_bus_feeds_active_inverter&&power.dc_link_storage_on_shared_bus)
    facts.path_evidence=pathReport.evidence;
    facts.model=string(modelName);
    valid=true;reason="OK";return;
end
[facts.vabc_same_output_stage,facts.vabc_output_path]=same_output_stage( ...
    modelName,power.inverter_blocks,vabc.trace_blocks,power.rectifier_blocks);
[loop,ok,why]=output_voltage_feedback_ownership(modelName,state, ...
    power.inverter_blocks,vabc.trace_blocks,power.rectifier_blocks);
if ~ok,reason=why;return;end
facts.gate_source_blocks=loop.gate_source_blocks;
facts.gate_source_ports=loop.gate_source_ports;
facts.gate_owned_stage_blocks=loop.gate_owned_stage_blocks;
facts.output_voltage_sensor_blocks=loop.output_voltage_sensor_blocks;
facts.output_side_voltage_sensor_blocks=loop.output_side_voltage_sensor_blocks;
facts.output_side_physical_paths=loop.output_side_physical_paths;
facts.output_feedback_gate_paths=loop.output_feedback_gate_paths;
facts.active_stage_feedback_ownership=loop.active_stage_feedback_ownership;
facts.active_stage_coverage=loop.active_stage_coverage;
facts.output_voltage_feedback_reaches_active_stage= ...
    loop.output_voltage_feedback_reaches_active_stage;
facts.all_active_stages_owned=loop.all_active_stages_owned;
facts.path_evidence=pathReport.evidence;
facts.model=string(modelName);
valid=true;reason="OK";
end

function [schemaOk,ok,detail]=verdict(f)
required={'energy_path_blocks','rectifier_blocks','controllable_inverter_blocks', ...
    'rectifier_precedes_inverter','shared_dc_bus_pair', ...
    'rectifier_source_to_dc_bus','front_has_pure_passive_bypass', ...
    'dc_bus_feeds_active_inverter', ...
    'dc_link_storage_on_shared_bus','dc_link_storage_present', ...
    'vdc_physical_measurement','vabc_physical_measurement','iabc_physical_measurement', ...
    'vabc_channels','iabc_channels','vabc_distinct_origins','iabc_distinct_origins', ...
    'iabc_measurement_on_energy_path','vabc_same_output_stage', ...
    'gate_source_blocks','output_voltage_sensor_blocks', ...
    'output_side_voltage_sensor_blocks','output_voltage_feedback_reaches_active_stage', ...
    'all_active_stages_owned'};
schemaOk=isstruct(f)&&isscalar(f)&&all(isfield(f,required));
if ~schemaOk,ok=false;detail="FACT_SCHEMA_INVALID";return;end
pathOk=~isempty(f.energy_path_blocks)&&~isempty(f.rectifier_blocks) ...
    &&~isempty(f.controllable_inverter_blocks)&&logical(f.rectifier_precedes_inverter) ...
    &&logical(f.shared_dc_bus_pair)&&logical(f.rectifier_source_to_dc_bus) ...
    &&~logical(f.front_has_pure_passive_bypass) ...
    &&logical(f.dc_bus_feeds_active_inverter) ...
    &&logical(f.dc_link_storage_on_shared_bus);
measureOk=logical(f.vdc_physical_measurement)&&logical(f.vabc_physical_measurement) ...
    &&logical(f.iabc_physical_measurement)&&f.vabc_channels==3&&f.iabc_channels==3 ...
    &&logical(f.vabc_distinct_origins)&&logical(f.iabc_distinct_origins) ...
    &&logical(f.iabc_measurement_on_energy_path)&&logical(f.vabc_same_output_stage);
loopOk=~isempty(f.gate_source_blocks)&&~isempty(f.output_voltage_sensor_blocks) ...
    &&~isempty(f.output_side_voltage_sensor_blocks) ...
    &&logical(f.output_voltage_feedback_reaches_active_stage) ...
    &&logical(f.all_active_stages_owned);
ok=pathOk&&logical(f.dc_link_storage_present)&&measureOk&&loopOk;
if ok,detail="OK";
elseif ~logical(f.shared_dc_bus_pair),detail="SHARED_DC_BUS_PAIR_NOT_PROVEN";
elseif ~logical(f.rectifier_source_to_dc_bus),detail="SOURCE_DOES_NOT_FEED_SHARED_DC_BUS_THROUGH_FRONT_CONVERSION";
elseif logical(f.front_has_pure_passive_bypass),detail="FRONT_CONVERSION_BYPASSED_BY_PASSIVE_SOURCE_TO_BUS_PATHS";
elseif ~logical(f.dc_bus_feeds_active_inverter),detail="SHARED_DC_BUS_DOES_NOT_FEED_THREE_PHASE_ACTIVE_INVERTER";
elseif ~logical(f.dc_link_storage_on_shared_bus),detail="DC_LINK_STORAGE_NOT_ON_SHARED_BUS";
elseif isempty(f.rectifier_blocks),detail="RECTIFIER_NOT_ON_ACTIVE_SOURCE_TO_LOAD_PATH";
elseif isempty(f.controllable_inverter_blocks),detail="CONTROLLABLE_INVERTER_NOT_ON_ACTIVE_SOURCE_TO_LOAD_PATH";
elseif ~logical(f.rectifier_precedes_inverter),detail="RECTIFIER_DOES_NOT_PRECEDE_CONTROLLABLE_INVERTER";
elseif ~logical(f.dc_link_storage_present),detail="PHYSICAL_DC_LINK_STORAGE_MISSING";
elseif ~measureOk,detail="PHYSICAL_THREE_PHASE_MEASUREMENT_INVALID";
elseif isempty(f.gate_source_blocks),detail="ACTIVE_INVERTER_GATE_SOURCE_MISSING";
elseif isempty(f.output_voltage_sensor_blocks),detail="PHYSICAL_OUTPUT_VOLTAGE_SENSOR_MISSING";
elseif isempty(f.output_side_voltage_sensor_blocks),detail="VOLTAGE_SENSOR_NOT_OWNED_BY_OUTPUT_TERMINAL";
elseif ~logical(f.output_voltage_feedback_reaches_active_stage),detail="OUTPUT_VOLTAGE_MEASUREMENT_DOES_NOT_REACH_ACTIVE_INVERTER";
else,detail="OUTPUT_VOLTAGE_FEEDBACK_OWNERSHIP_INCOMPLETE";end
end

function [facts,valid,reason]=shared_dc_link_ownership(model,state,pathReport,vdcBlocks,vabcBlocks)
facts=empty_power_facts();valid=false;reason="";
G=task_graph(model,state);
[nodeNets,ok]=native_net_ids(G);
if ~ok,reason="PHYSICAL_NET_IDENTITIES_UNAVAILABLE";return;end

sourceBlocks=strings(0,1);
if isfield(pathReport,'evidence')&&isstruct(pathReport.evidence) ...
        &&isfield(pathReport.evidence,'source_matches')
    sourceBlocks=topmost_blocks(unique(string(pathReport.evidence.source_matches(:)),'stable'));
end
vdcBlocks=topmost_blocks(unique(string(vdcBlocks(:)),'stable'));
vabcBlocks=topmost_blocks(unique(string(vabcBlocks(:)),'stable'));
if isempty(sourceBlocks),reason="SINGLE_PHASE_SOURCE_ENDPOINT_UNRESOLVED";return;end
if isempty(vdcBlocks),reason="VDC_PHYSICAL_ENDPOINT_UNRESOLVED";return;end
if isempty(vabcBlocks),reason="VABC_PHYSICAL_ENDPOINT_UNRESOLVED";return;end

physicalBlocks=unique(string({G.nodes(string({G.nodes.network})=="physical").block}),'stable');
conversionBlocks=strings(0,1);activeBlocks=strings(0,1);
for b=physicalBlocks(:)'
    if is_conversion_stage(b),conversionBlocks(end+1,1)=b;end %#ok<AGROW>
    if is_controllable_stage(b),activeBlocks(end+1,1)=b;end %#ok<AGROW>
end
conversionBlocks=topmost_blocks(unique(conversionBlocks,'stable'));
activeBlocks=topmost_blocks(unique(activeBlocks,'stable'));
if isempty(conversionBlocks),reason="PHYSICAL_FRONT_CONVERSION_STAGE_UNRESOLVED";return;end
if isempty(activeBlocks),reason="PHYSICAL_ACTIVE_INVERTER_STAGE_UNRESOLVED";return;end

passiveEdges=[component_edges(G,nodeNets,physicalBlocks,conversionBlocks,"passive") ...
    subsystem_boundary_edges(G,nodeNets,conversionBlocks)];
storageOnly=storage_component_edges(G,nodeNets,physicalBlocks,conversionBlocks);
frontEdges=[passiveEdges storageOnly ...
    component_edges(G,nodeNets,conversionBlocks,strings(0,1),"conversion")];
rearEdges=[passiveEdges component_edges(G,nodeNets,activeBlocks,strings(0,1),"active")];
storageEdges=[passiveEdges storageOnly];
outputNets=blocks_net_ids(G,nodeNets,vabcBlocks);
if numel(outputNets)<3,reason="THREE_PHASE_OUTPUT_TERMINAL_NETS_UNRESOLVED";return;end
activeTerminalNets=blocks_net_ids(G,nodeNets,activeBlocks);
if numel(activeTerminalNets)<5,reason="ACTIVE_STAGE_DC_AND_THREE_PHASE_TERMINALS_UNRESOLVED";return;end

for sensor=vdcBlocks(:)'
    bus=blocks_net_ids(G,nodeNets,sensor);
    if numel(bus)~=2,continue;end
    [frontOk,frontBlocks,frontPaths,passiveBypass]=front_owns_bus( ...
        G,nodeNets,sourceBlocks,bus,frontEdges);
    % Establish the rear stage role at its own physical terminals: the two
    % bus rails must both reach at least three other active-stage terminals
    % through controllable conversion.  The existing same_output_stage
    % check below separately proves that those terminals feed measured
    % Vabc, so an LC filter between inverter and sensor remains legal.
    [rearOk,rearBlocks,rearPaths]=bus_owns_three_phase_output( ...
        bus,activeTerminalNets,rearEdges);
    [storageOk,storageBlocks]=net_path( ...
        storageEdges,bus(1),bus(2),[],"storage");
    % Preserve the strongest partial candidate as explicit evidence.  This
    % keeps a failed front/rear/storage ownership check distinguishable
    % from an unresolved Vdc terminal pair.
    facts.dc_bus_net_ids=double(bus(:));
    facts.rectifier_blocks=frontBlocks;
    facts.inverter_blocks=rearBlocks;
    facts.dc_link_storage_blocks=storageBlocks;
    facts.rectifier_source_paths=frontPaths;
    facts.dc_bus_inverter_paths=rearPaths;
    facts.shared_dc_bus_pair=true;
    facts.rectifier_source_to_dc_bus=frontOk;
    facts.dc_bus_feeds_active_inverter=rearOk;
    facts.dc_link_storage_on_shared_bus=storageOk;
    if ~(frontOk&&rearOk&&storageOk)||passiveBypass,continue;end
    if ~isempty(intersect(frontBlocks,rearBlocks)),continue;end
    facts.source_blocks=sourceBlocks;
    facts.rectifier_blocks=frontBlocks;
    facts.inverter_blocks=rearBlocks;
    facts.dc_bus_net_ids=double(bus(:));
    facts.dc_link_storage_blocks=storageBlocks;
    facts.rectifier_source_paths=frontPaths;
    facts.dc_bus_inverter_paths=rearPaths;
    facts.shared_dc_bus_pair=true;
    facts.rectifier_source_to_dc_bus=true;
    facts.front_has_pure_passive_bypass=false;
    facts.dc_bus_feeds_active_inverter=true;
    facts.dc_link_storage_on_shared_bus=true;
    valid=true;reason="OK";return;
end

% Extraction succeeded, but no Vdc terminal pair satisfied the complete
% ownership definition.  Return valid negative facts so the task-specific
% verdict can state the failed structural condition rather than UNKNOWN.
valid=true;reason="OK";
end

function [nodeNets,ok]=native_net_ids(G)
nodeNets=nan(1,numel(G.nodes));ok=false;
physical=find(string({G.nodes.network})=="physical");
if isempty(physical),return;end
handles=[G.nodes(physical).port_handle];
try,netMap=sat_native_physical_line_nets(char(G.model),handles);catch,return;end
for ix=physical(:)'
    line=-1;try,line=double(get_param(G.nodes(ix).port_handle,'Line'));catch,end
    key=sprintf('%.15g',line);
    if line>0&&isKey(netMap,key),nodeNets(ix)=double(netMap(key));end
end
ok=any(isfinite(nodeNets));
end

function nets=blocks_net_ids(G,nodeNets,blocks)
nets=zeros(0,1);blocks=string(blocks(:));
for b=blocks'
    ids=find(string({G.nodes.network})=="physical"&string({G.nodes.block})==b);
    nets=[nets;nodeNets(ids(:))']; %#ok<AGROW>
end
nets=unique(nets(isfinite(nets)),'stable');
end

function edges=component_edges(G,nodeNets,blocks,conversionAncestors,kind)
edges=empty_edges();blocks=string(blocks(:));conversionAncestors=string(conversionAncestors(:));
for b=blocks'
    if kind=="passive"
        if is_descendant_of_any(b,conversionAncestors)||~is_passive_link(b),continue;end
    end
    nets=blocks_net_ids(G,nodeNets,b);
    if numel(nets)<2,continue;end
    if kind=="passive"&&numel(nets)~=2,continue;end
    for i=1:numel(nets),for j=i+1:numel(nets)
        edges(end+1)=struct('a',nets(i),'b',nets(j),'block',b,'kind',kind); %#ok<AGROW>
    end,end
end
end

function edges=storage_component_edges(G,nodeNets,blocks,conversionAncestors)
edges=empty_edges();
for b=string(blocks(:))'
    if is_descendant_of_any(b,conversionAncestors)||~is_capacitor_block(b),continue;end
    nets=blocks_net_ids(G,nodeNets,b);if numel(nets)~=2,continue;end
    edges(end+1)=struct('a',nets(1),'b',nets(2),'block',b,'kind',"storage"); %#ok<AGROW>
end
end

function edges=subsystem_boundary_edges(G,nodeNets,conversionAncestors)
% Native line families identify electrical nets, while PMIO ports express
% hierarchy crossings as explicit graph edges.  Preserve only those exact
% boundary mappings; never collapse a user subsystem or conversion block.
edges=empty_edges();
for a=1:numel(G.nodes)
    if string(G.nodes(a).network)~="physical"||~isfinite(nodeNets(a)),continue;end
    neighbours=G.physical_undirected{a};kinds=G.physical_edge_kinds{a};
    for k=1:numel(neighbours)
        b=neighbours(k);if b<=a||string(kinds{k})~="subsystem_boundary" ...
                ||~isfinite(nodeNets(b))||nodeNets(a)==nodeNets(b),continue;end
        blocks=[string(G.nodes(a).block);string(G.nodes(b).block)];
        if any(arrayfun(@(q)is_descendant_or_same(blocks(q),conversionAncestors), ...
                1:numel(blocks))),continue;end
        edges(end+1)=struct('a',nodeNets(a),'b',nodeNets(b), ...
            'block',blocks(1),'kind',"passive"); %#ok<AGROW>
    end
end
end

function [ok,blocks,paths,passiveBypass]=front_owns_bus(G,nodeNets,sources,bus,edges)
ok=false;blocks=strings(0,1);paths={};passiveBypass=false;
passiveEdges=edges(string({edges.kind})~="conversion");

% Fail closed if the two source terminals can already reach the two DC
% rails through storage/passive elements alone.  A decorative conversion
% branch must not rescue a fully passive source-to-bus bypass.
for source=string(sources(:))'
    sourceNets=blocks_net_ids(G,nodeNets,source);
    if numel(sourceNets)<2||~isempty(intersect(sourceNets,bus)),continue;end
    pairs=nchoosek(sourceNets,2);
    for p=1:size(pairs,1)
        s=pairs(p,:);
        for order={[1 2],[2 1]}
            o=order{1};
            a=net_path(passiveEdges,s(1),bus(o(1)),[s(2) bus(o(2))],"");
            b=net_path(passiveEdges,s(2),bus(o(2)),[s(1) bus(o(1))],"");
            if a&&b,passiveBypass=true;return;end
        end
    end
end

% A voltage-doubler front end is legal: one source-terminal path may reach
% its rail through a diode/switch and the other through the split storage
% capacitors.  Across the paired paths, however, at least one path must
% contain a real conversion element.
for source=string(sources(:))'
    sourceNets=blocks_net_ids(G,nodeNets,source);
    if numel(sourceNets)<2||~isempty(intersect(sourceNets,bus)),continue;end
    pairs=nchoosek(sourceNets,2);
    for p=1:size(pairs,1)
        s=pairs(p,:);
        for order={[1 2],[2 1]}
            o=order{1};
            [a,ba,~,pa]=net_path(edges,s(1),bus(o(1)),[s(2) bus(o(2))],"conversion");
            [b,~,~,pb]=net_path(edges,s(2),bus(o(2)),[s(1) bus(o(1))],"");
            if a&&b,blocks=ba;paths={pa,pb};ok=true;return;end
            [a,~,~,pa]=net_path(edges,s(1),bus(o(1)),[s(2) bus(o(2))],"");
            [b,bb,~,pb]=net_path(edges,s(2),bus(o(2)),[s(1) bus(o(1))],"conversion");
            if a&&b,blocks=bb;paths={pa,pb};ok=true;return;end
        end
    end
end
end

function [ok,blocks,paths]=bus_owns_three_phase_output(bus,outputs,edges)
ok=false;blocks=strings(0,1);paths={};
reach=false(2,numel(outputs));blockRows=cell(2,numel(outputs));pathRows=cell(2,numel(outputs));
for rail=1:2
    for j=1:numel(outputs)
        if any(outputs(j)==bus),continue;end
        [reach(rail,j),blockRows{rail,j},~,pathRows{rail,j}]=net_path( ...
            edges,bus(rail),outputs(j),bus(3-rail),"active");
    end
end
joint=find(all(reach,1));
if numel(joint)<3,return;end
joint=joint(1:3);
for rail=1:2,for j=joint
    blocks=[blocks;blockRows{rail,j}(:)];paths{end+1}=pathRows{rail,j}; %#ok<AGROW>
end,end
blocks=unique(blocks,'stable');ok=~isempty(blocks);
end

function [ok,blocks,kinds,path]=net_path(edges,startNet,goalNet,excluded,requiredKind)
ok=false;blocks=strings(0,1);kinds=strings(0,1);path=zeros(0,1);
if isempty(edges)||startNet==goalNet,return;end
nets=unique([[edges.a] [edges.b] startNet goalNet]);
start=find(nets==startNet,1);goal=find(nets==goalNet,1);
blocked=ismember(nets,double(excluded(:)));blocked([start goal])=false;
need=strlength(requiredKind)>0;seen=false(numel(nets),2);prevNode=zeros(numel(nets),2);
prevUsed=zeros(numel(nets),2);prevEdge=zeros(numel(nets),2);
queue=[start double(~need)];seen(start,double(~need)+1)=true;hit=[];
while ~isempty(queue)
    row=queue(1,:);queue(1,:)=[];u=row(1);used=logical(row(2));
    if u==goal&&(~need||used),hit=row;break;end
    incident=find([edges.a]==nets(u)|[edges.b]==nets(u));
    for ei=incident
        e=edges(ei);next=e.b;if next==nets(u),next=e.a;end
        v=find(nets==next,1);if blocked(v),continue;end
        usedNext=used||(~need||string(e.kind)==requiredKind);col=double(usedNext)+1;
        if seen(v,col),continue;end
        seen(v,col)=true;prevNode(v,col)=u;prevUsed(v,col)=double(used)+1;prevEdge(v,col)=ei;
        queue(end+1,:)=[v double(usedNext)]; %#ok<AGROW>
    end
end
if isempty(hit),return;end
u=hit(1);col=double(logical(hit(2)))+1;edgePath=[];nodePath=nets(u);
while u~=start||prevEdge(u,col)~=0
    ei=prevEdge(u,col);if ei==0,return;end
    edgePath=[ei edgePath]; %#ok<AGROW>
    oldU=u;u=prevNode(oldU,col);col=prevUsed(oldU,col);nodePath=[nets(u) nodePath]; %#ok<AGROW>
end
kinds=string({edges(edgePath).kind})';
requiredMask=kinds==requiredKind;
blocks=unique(string({edges(edgePath(requiredMask)).block}),'stable')';
path=double(nodePath(:));ok=true;
end

function tf=is_passive_link(block)
[d,~]=trusted_descriptor(block);bt=lower(string(getp(block,'BlockType')));
if is_conversion_stage(block)||is_capacitor_block(block),tf=false;return;end
forbidden=["voltage source","current source","controlled source","voltage measurement", ...
    "voltage sensor","load","ground","machine","motor","generator"];
tf=~any(contains(d,forbidden));
if bt=="subsystem"
    mt=string(getp(block,'MaskType'));rb=string(getp(block,'ReferenceBlock'));
    if strlength(strtrim(mt))==0&&strlength(strtrim(rb))==0,tf=false;end
end
end

function tf=is_capacitor_block(block)
[d,~]=trusted_descriptor(block);branch=upper(strtrim(string(getp(block,'BranchType'))));
tf=branch=="C"||contains(d,"capacitor");
end

function tf=is_descendant_of_any(block,ancestors)
tf=false;for a=string(ancestors(:))',if startsWith(block,a+"/"),tf=true;return;end,end
end

function tf=is_descendant_or_same(block,ancestors)
tf=false;for a=string(ancestors(:))'
    if block==a||startsWith(block,a+"/"),tf=true;return;end
end
end

function e=empty_edges()
e=struct('a',{},'b',{},'block',{},'kind',{});
end

function f=empty_power_facts()
f=struct('source_blocks',strings(0,1),'rectifier_blocks',strings(0,1), ...
    'inverter_blocks',strings(0,1),'dc_bus_net_ids',zeros(0,1), ...
    'dc_link_storage_blocks',strings(0,1),'rectifier_source_paths',{{}}, ...
    'dc_bus_inverter_paths',{{}},'shared_dc_bus_pair',false, ...
    'rectifier_source_to_dc_bus',false,'front_has_pure_passive_bypass',false, ...
    'dc_bus_feeds_active_inverter',false, ...
    'dc_link_storage_on_shared_bus',false);
end

function [loop,valid,reason]=output_voltage_feedback_ownership(model,state,stages,vabc,rectifiers)
loop=empty_loop_facts();valid=false;reason="";
stages=topmost_blocks(unique(string(stages(:)),'stable'));
vabc=topmost_blocks(unique(string(vabc(:)),'stable'));
rectifiers=topmost_blocks(unique(string(rectifiers(:)),'stable'));
if isempty(stages),reason="ACTIVE_INVERTER_STAGE_UNRESOLVED";return;end
if isempty(vabc),reason="VABC_PHYSICAL_ENDPOINT_UNRESOLVED";return;end

sensors=voltage_sensor_blocks(model);
if isempty(sensors),reason="PHYSICAL_VOLTAGE_SENSOR_MISSING";return;end
G=task_graph(model,state);G=close_signal_subsystems(G);
gates=gate_source_endpoints(stages,G);
if isempty(gates),reason="ACTIVE_INVERTER_GATE_SOURCE_MISSING";return;end
gateSources=string({gates.source_block})';
gatePorts=double([gates.source_port])';
gateStages=string({gates.stage_block})';
outputSide=false(size(sensors));physicalPaths=cell(size(sensors));
for i=1:numel(sensors)
    [outputSide(i),physicalPaths{i}]=same_physical_output_terminal( ...
        G,sensors(i),vabc,stages,rectifiers);
end
ownedSensors=sensors(outputSide);

feedbackPaths=cell(numel(ownedSensors),numel(gateSources));
joint=false(numel(ownedSensors),numel(gateSources));
for i=1:numel(ownedSensors)
    for j=1:numel(gateSources)
        [joint(i,j),feedbackPaths{i,j}]=signal_reaches( ...
            G,ownedSensors(i),gates(j).source_node);
    end
end
stageOwned=false(size(stages));
for i=1:numel(stages)
    stageOwned(i)=any(joint(:,gateStages==stages(i)),'all');
end
loop.gate_source_blocks=gateSources;
loop.gate_source_ports=gatePorts;
loop.gate_owned_stage_blocks=gateStages;
loop.output_voltage_sensor_blocks=sensors;
loop.output_side_voltage_sensor_blocks=ownedSensors;
loop.output_side_physical_paths=physicalPaths(outputSide);
loop.output_feedback_gate_paths=feedbackPaths;
loop.active_stage_feedback_ownership=stageOwned;
loop.active_stage_coverage=sum(stageOwned)/max(numel(stageOwned),1);
loop.output_voltage_feedback_reaches_active_stage=any(joint,'all');
loop.all_active_stages_owned=all(stageOwned);
valid=true;reason="OK";
end

function blocks=voltage_sensor_blocks(model)
blocks=strings(0,1);
try
    allBlocks=find_system(char(string(model)),'LookUnderMasks','all', ...
        'FollowLinks','on','Type','Block');
catch
    return;
end
for i=1:numel(allBlocks)
    b=string(allBlocks{i});[d,~]=trusted_descriptor(b);
    if contains(d,"voltage measurement")||contains(d,"voltage sensor") ...
            ||contains(d,"three-phase v-i measurement") ...
            ||contains(d,"three-phase vi measurement")
        blocks(end+1,1)=b; %#ok<AGROW>
    end
end
blocks=topmost_blocks(unique(blocks,'stable'));
end

function [ok,path]=same_physical_output_terminal(G,sensor,vabc,stages,rectifiers)
ok=false;path=strings(0,1);
q=struct('network',"physical",'direction',"undirected", ...
    'source',struct('block',sensor),'target',{exact_selectors(vabc)});
[hit,e]=sat_graph_query(G,q);
if ~hit||~isstruct(e)||~isfield(e,'block_path'),return;end
path=string(e.block_path(:));middle=path;
if numel(middle)>2,middle=middle(2:end-1);else,middle=strings(0,1);end
% A DC-link sensor can physically reach Vabc only by crossing the active
% inverter.  A genuine output-side sensor reaches the logged output
% terminal without crossing either conversion stage.
forbidden=unique([string(stages(:));string(rectifiers(:))]);
ok=isempty(intersect(middle,forbidden));
end

function rows=gate_source_endpoints(stages,G)
rows=struct('stage_block',{},'source_block',{},'source_port',{},'source_node',{});
keys=strings(0,1);
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
            rows(end+1)=struct('stage_block',stage,'source_block',block, ...
                'source_port',port,'source_node',ids); %#ok<AGROW>
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
    % Only sealed linked/masked components receive potential interior
    % closure.  Plain user subsystems already have explicit boundary and
    % internal paths; closing every input to every output would let a
    % decorative feedback input inherit an unrelated fixed gate output.
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

function G=task_graph(model,state)
if isstruct(state)&&isfield(state,'model_graph')&&isstruct(state.model_graph) ...
        &&isfield(state.model_graph,'schema')&&string(state.model_graph.schema)=="simuverity.sat-model-graph.v1"
    G=state.model_graph;
else
    G=sat_model_graph(char(string(model)));
end
end

function out=topmost_blocks(blocks)
out=strings(0,1);blocks=string(blocks(:));
for i=1:numel(blocks)
    ancestor=false;
    for j=1:numel(blocks)
        if i~=j&&startsWith(blocks(i),blocks(j)+"/"),ancestor=true;break;end
    end
    if ~ancestor,out(end+1,1)=blocks(i);end %#ok<AGROW>
end
end

function tf=is_conversion_stage(block)
[d,device]=trusted_descriptor(block);
stageWords=["rectifier","bridge","converter","inverter"];
deviceWords=["diode","thyristor","igbt","mosfet","gto","ideal switch"];
tf=any(contains(d,stageWords))||any(contains(d,deviceWords)) ...
    ||any(contains(device,deviceWords));
end
function tf=is_controllable_stage(block)
[d,device]=trusted_descriptor(block);
tf=contains(d,"three-level bridge")||contains(d,"igbt")||contains(d,"mosfet") ...
    ||contains(d,"gto")||contains(d,"ideal switch")||contains(device,"igbt") ...
    ||contains(device,"mosfet")||contains(device,"gto")||contains(device,"ideal switch");
end
function [d,device]=trusted_descriptor(block)
parts=strings(0,1);
for p={'BlockType','MaskType','ReferenceBlock'}
    try,parts(end+1)=string(get_param(char(block),p{1}));catch,end %#ok<AGROW>
end
d="|"+lower(strjoin(parts,"|"))+"|";device=lower(string(getp(block,'Device')));
end

function [ok,path]=same_output_stage(model,stages,measurements,rectifiers)
ok=false;path=strings(0,1);stages=unique(string(stages(:)),'stable');
measurements=unique(string(measurements(:)),'stable');
if isempty(stages)||isempty(measurements),return;end
G=sat_model_graph(char(string(model)));
q=struct('network',"physical",'direction',"undirected", ...
    'source',{exact_selectors(stages)},'target',{exact_selectors(measurements)});
[hit,e]=sat_graph_query(G,q);
if ~hit||~isstruct(e)||~isfield(e,'block_path'),return;end
path=string(e.block_path(:));middle=path;
if numel(middle)>2,middle=middle(2:end-1);else,middle=strings(0,1);end
ok=isempty(intersect(middle,string(rectifiers(:))));
end
function selectors=exact_selectors(blocks)
selectors=cell(1,numel(blocks));
for i=1:numel(blocks),selectors{i}=struct('block',blocks(i));end
end

function [o,ok,reason]=output_facts(base,name,expectedChannels)
o=struct('physical',false,'channels',0,'distinct',false, ...
    'trace_blocks',strings(0,1));ok=false;
[r,uniqueOk,why]=unique_report(base,'output_reports',name);
if ~uniqueOk,reason=why;return;end
if ~logical_field(r,'ok')||~logical_field(r,'provenance_ok')
    reason=name+"_PHYSICAL_PROVENANCE_FAILED";return;
end
if ~isfield(r,'channels')||~isscalar(r.channels)||~isfinite(r.channels)
    reason=name+"_CHANNEL_COUNT_MISSING";return;
end
o.physical=true;o.channels=double(r.channels);
if isfield(r,'trace')&&isstruct(r.trace)&&~isempty(r.trace)&&isfield(r.trace,'path')
    o.trace_blocks=unique(string({r.trace.path}),'stable');
end
if expectedChannels==1,o.distinct=true;
elseif isfield(r,'channel_origins')
    origins=string(r.channel_origins(:));origins=origins(strlength(origins)>0);
    o.distinct=numel(origins)==expectedChannels&&numel(unique(origins))==expectedChannels;
end
ok=true;reason="OK";
end

function [r,ok,reason]=unique_report(base,collection,id)
r=[];ok=false;reason=upper(id)+"_REPORT_MISSING";items=field_items(base,collection);matches={};
for i=1:numel(items)
    x=items{i};key="";
    if string(collection)=="output_reports"&&isstruct(x)&&isfield(x,'name'),key=string(x.name);
    elseif isstruct(x)&&isfield(x,'id'),key=string(x.id);end
    if key==id,matches{end+1}=x;end %#ok<AGROW>
end
if numel(matches)~=1,if numel(matches)>1,reason=upper(id)+"_REPORT_AMBIGUOUS";end;return;end
r=matches{1};ok=true;reason="OK";
end
function items=field_items(s,name)
if ~isstruct(s)||~isscalar(s)||~isfield(s,name)||isempty(s.(name)),items={};
elseif iscell(s.(name)),items=s.(name)(:).';
else,items=arrayfun(@(x)x,s.(name),'UniformOutput',false);end
end
function value=logical_field(s,name),value=isstruct(s)&&isfield(s,name)&&isscalar(s.(name))&&logical(s.(name));end
function v=getp(block,param),v='';try,v=get_param(char(block),param);catch,end,end
function tf=has_fixture(state),tf=isstruct(state)&&isscalar(state)&&isfield(state,'evidence')&&isstruct(state.evidence)&&isfield(state.evidence,'unit_test_facts');end
function f=empty_facts()
f=struct('energy_path_blocks',strings(0,1),'rectifier_blocks',strings(0,1), ...
    'controllable_inverter_blocks',strings(0,1),'rectifier_precedes_inverter',false, ...
    'shared_dc_bus_pair',false,'rectifier_source_to_dc_bus',false, ...
    'front_has_pure_passive_bypass',false,'dc_bus_feeds_active_inverter',false, ...
    'dc_link_storage_on_shared_bus',false, ...
    'dc_bus_net_ids',zeros(0,1),'dc_link_storage_blocks',strings(0,1), ...
    'rectifier_source_paths',{{}},'dc_bus_inverter_paths',{{}}, ...
    'dc_link_storage_present',false,'vdc_physical_measurement',false, ...
    'vabc_physical_measurement',false,'iabc_physical_measurement',false, ...
    'vabc_channels',0,'iabc_channels',0,'vabc_distinct_origins',false, ...
    'iabc_distinct_origins',false,'iabc_measurement_on_energy_path',false, ...
    'vabc_same_output_stage',false,'vabc_output_path',strings(0,1), ...
    'gate_source_blocks',strings(0,1),'gate_source_ports',zeros(0,1), ...
    'gate_owned_stage_blocks',strings(0,1), ...
    'output_voltage_sensor_blocks',strings(0,1), ...
    'output_side_voltage_sensor_blocks',strings(0,1), ...
    'output_side_physical_paths',{{}},'output_feedback_gate_paths',{{}}, ...
    'active_stage_feedback_ownership',false(0,1),'active_stage_coverage',0, ...
    'output_voltage_feedback_reaches_active_stage',false, ...
    'all_active_stages_owned',false, ...
    'path_evidence',struct(),'model',"");
end
function f=empty_loop_facts()
f=struct('gate_source_blocks',strings(0,1),'gate_source_ports',zeros(0,1), ...
    'gate_owned_stage_blocks',strings(0,1), ...
    'output_voltage_sensor_blocks',strings(0,1), ...
    'output_side_voltage_sensor_blocks',strings(0,1), ...
    'output_side_physical_paths',{{}},'output_feedback_gate_paths',{{}}, ...
    'active_stage_feedback_ownership',false(0,1),'active_stage_coverage',0, ...
    'output_voltage_feedback_reaches_active_stage',false, ...
    'all_active_stages_owned',false);
end
function r=make_report(evaluated,valid,ok,detail,evidence)
r=struct('task',"D014",'id',"D014.measured_power_path_ownership", ...
    'kind',"task_specific",'semantic_kind',"structure",'scenario',"nominal", ...
    'layer',"qualification",'evaluated',logical(evaluated),'mandatory',true, ...
    'ok',logical(ok),'valid',logical(valid),'score',double(ok), ...
    'detail',string(detail),'evidence',evidence);
end
