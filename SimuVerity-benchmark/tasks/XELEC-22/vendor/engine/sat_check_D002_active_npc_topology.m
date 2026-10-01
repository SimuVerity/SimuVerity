function report=sat_check_D002_active_npc_topology( ...
    modelName,spec,scenarioId,simOut,signals,baseReports,state) %#ok<INUSD>
%SAT_CHECK_D002_ACTIVE_NPC_TOPOLOGY Relationship-based five-level NPC proof.
% The verdict is deliberately count-neutral: it proves a measured four-edge
% DC-link chain, three rail-spanning controllable phase legs, and clamping
% semiconductor paths from every internal DC tap to every phase leg.  It
% does not require the reference model's exact 24 switches or 18 diodes.

if ~identity_ok(spec,scenarioId)
    report=make_report(false,false,false,"TASK_OR_SCENARIO_IDENTITY_MISMATCH",struct());return;
end
if has_fixture(state)
    facts=state.evidence.unit_test_facts;valid=true;reason="OK";
else
    try,[facts,valid,reason]=extract_facts(modelName,baseReports,state);
    catch ex
        where="";if ~isempty(ex.stack),where=string(ex.stack(1).name)+":"+string(ex.stack(1).line);end
        evidence=struct('identifier',string(ex.identifier),'message',string(ex.message),'where',where);
        report=make_report(false,false,false,"EXTRACTION_ERROR:"+string(ex.identifier),evidence);return;
    end
end
if ~valid,report=make_report(false,false,false,reason,facts);return;end
[schemaOk,ok,detail]=verdict(facts);report=make_report(true,schemaOk,ok,detail,facts);
end

function [f,valid,reason]=extract_facts(model,base,state)
f=empty_facts();valid=false;reason="";G=task_graph(model,state);roots=wire_roots(G);
[powerPath,ok,reason]=path_report(base,"dc_source_through_switches_to_load");if ~ok,return;end

capSensors=strings(4,1);capEdges=zeros(4,2);capBlocks=strings(4,1);
allCaps=trusted_blocks(G,@is_capacitor);[allCapEdges,allCaps]=two_terminal_edges(G,roots,allCaps);
if isempty(allCaps),reason="PHYSICAL_CAPACITOR_SET_MISSING";return;end
for i=1:4
    [sensors,ok,why]=output_sensors(base,"Vcap"+i,"cap_voltage");
    if ~ok,reason=why;return;end
    capSensors(i)=sensors(1);pair=block_pair(G,roots,sensors(1));
    if numel(pair)~=2,reason="VCAP"+i+"_SENSOR_TERMINALS_INVALID";return;end
    match=find(edge_equal(allCapEdges,pair));
    if numel(match)~=1,reason="VCAP"+i+"_DOES_NOT_IDENTIFY_ONE_CAPACITOR";return;end
    capEdges(i,:)=sort(pair);capBlocks(i)=allCaps(match);
end
f.four_measured_capacitor_sections=numel(unique(capBlocks))==4;
f.capacitor_blocks=capBlocks;f.capacitor_sensor_blocks=capSensors;f.capacitor_edges=capEdges;
[chainOk,rails,taps]=four_edge_chain(capEdges);f.dc_link_simple_chain=chainOk;
if chainOk,taps=ordered_chain_taps(capEdges,rails);end
f.dc_rail_nets=rails;f.dc_tap_nets=taps;
if ~chainOk,reason="MEASURED_CAPACITORS_DO_NOT_FORM_ONE_FOUR_SECTION_CHAIN";valid=true;return;end

feedAdj=passive_net_adjacency(G,roots,"source_feed");sources=trusted_blocks(G,@is_dc_source);
[sourceOk,sourceBlock,sourcePaths]=source_feeds_rails(G,roots,feedAdj,sources,rails);
f.dc_source_feeds_chain_rails=sourceOk;f.dc_source_block=sourceBlock;
f.dc_source_rail_paths=sourcePaths;

switches=trusted_blocks(G,@is_switch);[switchEdges,switches]=two_terminal_edges(G,roots,switches);
[legs,legSwitches,spanOk]=phase_legs(switchEdges,switches,rails);
f.switch_blocks=switches;f.switch_edges=switchEdges;f.phase_leg_nets=legs;
f.phase_leg_switches=legSwitches;f.three_active_phase_legs=numel(legs)==3;
f.all_legs_span_rails=spanOk&&f.three_active_phase_legs;

diodes=trusted_blocks(G,@is_diode);diodes=exclude_descendants(diodes,switches);
[diodeEdges,diodes]=directed_diode_edges(G,roots,diodes);
keep=~edge_member(sort(diodeEdges,2),switchEdges);diodeEdges=diodeEdges(keep,:);diodes=diodes(keep);
clamp=sat_npc_clamp_coverage(taps,legs,diodeEdges,rails,switchEdges);
coverage=false(numel(taps),numel(legs));
for t=1:numel(taps),for l=1:numel(legs)
    coverage(t,l)=~isempty(clamp.forward_hits{t,l})&&~isempty(clamp.reverse_hits{t,l});
end,end
f.clamp_diode_blocks=diodes;f.clamp_diode_directed_edges=diodeEdges;
f.clamp_coverage_matrix=coverage;f.clamp_directional_complete=clamp.directional_complete;
f.clamp_no_shared_tap_star=clamp.no_shared_tap_star;f.clamp_attachments=clamp.attachments;
f.clamp_potential_order_consistent=clamp.potential_order_consistent;
f.clamp_forward_paths=clamp.forward_paths;f.clamp_reverse_paths=clamp.reverse_paths;
f.clamp_coverage_complete=isequal(size(coverage),[3 3])&&all(coverage(:)) ...
    &&f.clamp_directional_complete&&f.clamp_no_shared_tap_star ...
    &&f.clamp_potential_order_consistent;

legStageSwitches=strings(0,1);for i=1:numel(legSwitches)
    legStageSwitches=[legStageSwitches;string(legSwitches{i}(:))]; %#ok<AGROW>
end
legStageSwitches=unique(legStageSwitches,'stable');
[gatesOwned,gateEvidence]=active_gate_ownership(G,legStageSwitches);
f.active_gate_ownership_complete=gatesOwned;f.gate_ownership=gateEvidence;

[iSensors,iOk,~]=output_sensors(base,"Iabc","phase_current");
[vSensors,vOk,~]=output_sensors(base,"Vph","phase_voltage");
outAdj=passive_net_adjacency(G,roots,"output_branch");
[iOwned,iSets]=legs_reach_sensors(G,roots,outAdj,legs,iSensors,true);
[vOwned,vSets]=legs_reach_sensors(G,roots,outAdj,legs,vSensors,false);
f.iabc_sensor_blocks=iSensors;f.vph_sensor_blocks=vSensors;
f.iabc_leg_sensor_nets=iSets;f.vph_leg_sensor_nets=vSets;
f.iabc_on_npc_output=iOk&&iOwned;f.vph_on_npc_output=vOk&&vOwned;
f.vph_reference_valid=vOk&&vph_reference_valid(G,roots,outAdj,legs,vSensors);

targetBlocks=strings(0,1);if isfield(powerPath.evidence,'target_matches')
    targetBlocks=string_values(powerPath.evidence.target_matches);
end
[loadOwned,loadSets]=sensor_branches_reach_load(G,roots,outAdj,iSets,targetBlocks);
f.load_blocks=targetBlocks;f.iabc_leg_load_nets=loadSets;f.iabc_sensor_to_load=loadOwned;

pathBlocks=string(powerPath.evidence.path(:));
f.power_path_uses_npc_switch=any_related(pathBlocks,switches);
f.power_path_uses_measured_dc_chain=any_related(pathBlocks,capBlocks);
f.power_path_uses_iabc_sensor=any_related(pathBlocks,iSensors);
% The generic physical-path primitive returns one arbitrary shortest path;
% membership of that one witness is not a stable ownership criterion.  The
% dedicated proof instead composes source->measured DC chain, rail-spanning
% NPC legs, NPC output sensors, and sensor->declared load reachability.
f.power_path_uses_npc_stage=sourceOk&&iOwned&&loadOwned;
f.diagnostic_switch_count=numel(switches);f.diagnostic_diode_count=numel(diodes);
valid=true;reason="OK";
end

function [schemaOk,ok,detail]=verdict(f)
required={'four_measured_capacitor_sections','dc_link_simple_chain', ...
    'dc_source_feeds_chain_rails','three_active_phase_legs','all_legs_span_rails', ...
    'clamp_coverage_complete','clamp_directional_complete','clamp_no_shared_tap_star', ...
    'clamp_potential_order_consistent', ...
    'active_gate_ownership_complete','iabc_on_npc_output','vph_on_npc_output', ...
    'vph_reference_valid','iabc_sensor_to_load', ...
    'power_path_uses_npc_stage'};
schemaOk=isstruct(f)&&isscalar(f)&&all(isfield(f,required));
if ~schemaOk,ok=false;detail="FACT_SCHEMA_INVALID";return;end
ok=true;for i=1:numel(required),ok=ok&&logical(f.(required{i}));end
if ok,detail="OK";
elseif ~logical(f.four_measured_capacitor_sections),detail="VCAP_MEASUREMENTS_NOT_BOUND_TO_FOUR_DISTINCT_CAPACITORS";
elseif ~logical(f.dc_link_simple_chain),detail="FOUR_MEASURED_CAPACITORS_NOT_ONE_SERIES_DC_LINK";
elseif ~logical(f.dc_source_feeds_chain_rails),detail="DC_SOURCE_NOT_BOUND_TO_BOTH_DC_LINK_RAILS";
elseif ~logical(f.three_active_phase_legs),detail="THREE_ACTIVE_PHASE_LEGS_NOT_PROVEN";
elseif ~logical(f.all_legs_span_rails),detail="ACTIVE_PHASE_LEG_DOES_NOT_SPAN_BOTH_DC_RAILS";
elseif ~logical(f.clamp_directional_complete),detail="NPC_BIDIRECTIONAL_TAP_TO_LEG_DIODE_PATHS_INCOMPLETE";
elseif ~logical(f.clamp_no_shared_tap_star),detail="NPC_TAPS_SHARE_AN_INVALID_COMMON_LEG_ATTACHMENT";
elseif ~logical(f.clamp_potential_order_consistent),detail="NPC_TAP_TO_LEG_POTENTIAL_ORDER_INCONSISTENT";
elseif ~logical(f.clamp_coverage_complete),detail="NPC_TAP_TO_PHASE_LEG_CLAMP_COVERAGE_INCOMPLETE";
elseif ~logical(f.active_gate_ownership_complete),detail="NPC_ACTIVE_LEG_GATE_OWNERSHIP_INCOMPLETE";
elseif ~logical(f.iabc_on_npc_output),detail="IABC_NOT_MEASURED_ON_THREE_NPC_OUTPUT_BRANCHES";
elseif ~logical(f.vph_on_npc_output),detail="VPH_NOT_MEASURED_ON_AN_NPC_OUTPUT_BRANCH";
elseif ~logical(f.vph_reference_valid),detail="VPH_REFERENCE_TERMINAL_NOT_PROVEN";
elseif ~logical(f.iabc_sensor_to_load),detail="IABC_OUTPUT_BRANCHES_DO_NOT_REACH_DECLARED_LOAD";
else,detail="MEASURED_SOURCE_TO_LOAD_PATH_DOES_NOT_USE_PROVEN_NPC_STAGE";end
end

function [r,ok,reason]=path_report(base,id)
r=[];ok=false;reason=upper(id)+"_REPORT_MISSING";items=field_items(base,'struct_reports');hits={};
for i=1:numel(items),x=items{i};if isstruct(x)&&isfield(x,'id')&&string(x.id)==id,hits{end+1}=x;end,end %#ok<AGROW>
if numel(hits)~=1,if numel(hits)>1,reason=upper(id)+"_REPORT_AMBIGUOUS";end;return;end
r=hits{1};if ~logical_field(r,'ok')||~isfield(r,'evidence')||~isfield(r.evidence,'path'),reason=upper(id)+"_FAILED";return;end
ok=true;reason="OK";
end

function [blocks,ok,reason]=output_sensors(base,name,kind)
blocks=strings(0,1);ok=false;reason=name+"_PHYSICAL_SENSOR_TRACE_MISSING";
items=field_items(base,'output_reports');traces={};
for i=1:numel(items)
    r=items{i};if isstruct(r)&&isfield(r,'name')&&string(r.name)==name ...
            &&logical_field(r,'ok')&&logical_field(r,'provenance_ok')&&isfield(r,'trace')
        traces{end+1}=r.trace; %#ok<AGROW>
    end
end
if numel(traces)~=1,if numel(traces)>1,reason=name+"_OUTPUT_REPORT_AMBIGUOUS";end;return;end
candidates=strings(0,1);trace=traces{1};
for i=1:numel(trace)
    if ~isfield(trace(i),'path'),continue;end;p=string(trace(i).path);
    while strlength(p)>0
        if sensor_kind(p,kind),candidates(end+1,1)=p;end %#ok<AGROW>
        parent=string(getp(p,'Parent'));if strlength(parent)==0||parent==p,break;end;p=parent;
    end
end
blocks=topmost(unique(candidates,'stable'));
if kind=="cap_voltage",ok=numel(blocks)==1;
elseif kind=="phase_voltage",ok=~isempty(blocks);
else,ok=~isempty(blocks);end
if ~ok,blocks=strings(0,1);return;end;reason="OK";
end

function tf=sensor_kind(block,kind)
d=meta(block);ids=physical_port_count(block);
if kind=="cap_voltage"
    tf=(contains(d,"voltage measurement")||contains(d,"voltage sensor")) ...
        &&~contains(d,"three-phase")&&ids==2;
elseif kind=="phase_voltage"
    tf=contains(d,"three-phase vi measurement")||contains(d,"current and voltage sensor (three-phase)") ...
        ||((contains(d,"voltage measurement")||contains(d,"voltage sensor"))&&ids==2);
else
    tf=contains(d,"three-phase vi measurement")||contains(d,"current and voltage sensor (three-phase)") ...
        ||contains(d,"current measurement")||contains(d,"current sensor");
end
end

function n=physical_port_count(block)
n=0;try,ph=get_param(char(block),'PortHandles');catch,return;end
for f={'LConn','RConn'},if isfield(ph,f{1}),n=n+numel(ph.(f{1}));end,end
end

function roots=wire_roots(G)
n=numel(G.nodes);p=1:n;
for x=1:n
    for j=1:numel(G.physical_undirected{x})
        y=G.physical_undirected{x}(j);k=string(G.physical_edge_kinds{x}{j});
        if k=="physical_net"||k=="subsystem_boundary",p=uf_union(p,x,y);end
    end
end
roots=zeros(1,n);for i=1:n,roots(i)=uf_find(p,i);end
end
function p=uf_union(p,a,b),a=uf_find(p,a);b=uf_find(p,b);if a~=b,p(b)=a;end,end
function r=uf_find(p,a),r=a;while p(r)~=r,r=p(r);end,end

function blocks=trusted_blocks(G,predicate)
blocks=unique(string({G.nodes.block}),'stable');keep=false(size(blocks));
for i=1:numel(blocks),keep(i)=predicate(blocks(i));end
blocks=topmost(blocks(keep));
end
function tf=is_capacitor(b)
branch=upper(strtrim(string(getp(b,'BranchType'))));d=meta(b);
tf=branch=="C"||contains(d,"capacitor");
end
function tf=is_switch(b)
d=meta(b);dev=lower(string(getp(b,'Device')));
tf=contains(d,"igbt")||contains(d,"mosfet")||contains(d,"gto") ...
    ||contains(d,"ideal switch")||contains(dev,"igbt")||contains(dev,"mosfet")||contains(dev,"gto");
end
function tf=is_diode(b),d=meta(b);tf=contains(d,"diode")&&~contains(d,"diode bridge");end
function tf=is_dc_source(b)
d=meta(b);tf=contains(d,"dc voltage source")||contains(d,"battery")||contains(d,"pv array");
end
function d=meta(b)
d=lower(strjoin(string({getp(b,'BlockType'),getp(b,'MaskType'),getp(b,'ReferenceBlock'), ...
    getp(b,'ComponentPath'),getp(b,'Device')}),'|'));
end
function blocks=topmost(blocks)
blocks=string(blocks(:));keep=true(size(blocks));
for i=1:numel(blocks),for j=1:numel(blocks)
    if i~=j&&startsWith(blocks(i),blocks(j)+"/"),keep(i)=false;break;end
end,end;blocks=blocks(keep);
end
function out=exclude_descendants(blocks,parents)
out=strings(0,1);for b=string(blocks(:))'
    inside=false;for p=string(parents(:))',inside=inside||startsWith(b,p+"/");end
    if ~inside,out(end+1,1)=b;end %#ok<AGROW>
end
end

function pair=block_pair(G,roots,block)
ids=find(string({G.nodes.block})==string(block)&string({G.nodes.network})=="physical");
pair=unique(roots(ids),'stable');
pair=pair(:)';
end
function [edges,blocks]=two_terminal_edges(G,roots,blocks)
edges=zeros(0,2);out=strings(0,1);
for b=string(blocks(:))'
    p=block_pair(G,roots,b);if numel(p)~=2||p(1)==p(2),continue;end
    edges(end+1,:)=sort(p);out(end+1,1)=b; %#ok<AGROW>
end
blocks=out;
end
function [edges,blocks]=directed_diode_edges(G,roots,blocks)
edges=zeros(0,2);out=strings(0,1);
for b=string(blocks(:))'
    ids=find(string({G.nodes.block})==b&string({G.nodes.network})=="physical");
    fields=string({G.nodes(ids).port_field});
    a=ids(strcmpi(fields,"LConn"));k=ids(strcmpi(fields,"RConn"));
    % Trusted SPS/Simscape diode convention: the outer LConn terminal is
    % anode and the outer RConn terminal is cathode. Ambiguous packaged
    % port schemas fail closed instead of inventing a direction.
    if numel(a)~=1||numel(k)~=1,continue;end;anode=roots(a);cathode=roots(k);
    if anode==cathode,continue;end;edges(end+1,:)=[anode cathode];out(end+1,1)=b; %#ok<AGROW>
end
blocks=out;
end
function tf=edge_equal(edges,pair),tf=all(edges==sort(pair),2);end
function tf=edge_member(edges,candidates)
tf=false(size(edges,1),1);for i=1:size(edges,1),tf(i)=any(edge_equal(candidates,edges(i,:)));end
end

function [ok,rails,taps]=four_edge_chain(edges)
ok=false;rails=[];taps=[];if ~isequal(size(edges),[4 2]),return;end
nets=unique(edges(:));if numel(nets)~=5,return;end;degree=zeros(size(nets));
for i=1:numel(nets),degree(i)=sum(edges(:)==nets(i));end
if ~isequal(sort(degree(:))',[1 1 2 2 2]),return;end
adj=net_adj(edges,max(nets));seen=reachable(adj,nets(1));if ~all(ismember(nets,seen)),return;end
rails=nets(degree==1)';taps=nets(degree==2)';ok=numel(rails)==2&&numel(taps)==3;
end
function taps=ordered_chain_taps(edges,rails)
taps=[];current=rails(1);previous=NaN;
for step=1:4
    rows=find(any(edges==current,2));next=[];
    for r=rows(:)'
        candidate=edges(r,edges(r,:)~=current);
        if isempty(candidate)||candidate==previous,continue;end;next=candidate;break;
    end
    if isempty(next),taps=[];return;end
    previous=current;current=next;if current~=rails(2),taps(end+1)=current;end %#ok<AGROW>
end
if numel(taps)~=3,taps=[];end
end

function [legs,legSwitches,allSpan]=phase_legs(edges,blocks,rails)
legs={};legSwitches={};allSpan=false;if isempty(edges)||numel(rails)~=2,return;end
internal=setdiff(unique(edges(:)),rails);adj=net_adj(edges,max([edges(:);rails(:)]));seen=[];
for seed=internal(:)'
    if any(seen==seed),continue;end;component=intersect(reachable_without(adj,seed,rails),internal,'stable');component=component(:)';
    seen=unique([seen component],'stable');touch1=false;touch2=false;owned=strings(0,1);
    for i=1:size(edges,1)
        inComp=any(component==edges(i,1))||any(component==edges(i,2));
        if ~inComp,continue;end;owned(end+1,1)=blocks(i); %#ok<AGROW>
        touch1=touch1||any(edges(i,:)==rails(1));touch2=touch2||any(edges(i,:)==rails(2));
    end
    if touch1&&touch2,legs{end+1}=component;legSwitches{end+1}=unique(owned,'stable');end %#ok<AGROW>
end
allSpan=~isempty(legs);
end

function [ok,evidence]=active_gate_ownership(G,switches)
switches=string(switches(:));owned=false(size(switches));gateNodes=cell(size(switches));origins=cell(size(switches));
for i=1:numel(switches)
    ids=find(string({G.nodes.block})==switches(i)&string({G.nodes.network})=="signal");
    fields=lower(string({G.nodes(ids).port_field}));gates=ids(contains(fields,"inport")|fields=="enable");
    gateNodes{i}=gates;hits=strings(0,1);
    for g=gates(:)',hits=[hits;dynamic_upstream_origins(G,g)];end %#ok<AGROW>
    origins{i}=unique(hits,'stable');owned(i)=~isempty(gates)&&~isempty(origins{i});
end
evidence=struct('switch_blocks',switches,'gate_node_ids',{gateNodes}, ...
    'dynamic_origin_blocks',{origins},'owned_mask',owned,'coverage',sum(owned)/max(numel(owned),1));
ok=~isempty(switches)&&all(owned);
end
function hits=dynamic_upstream_origins(G,start)
n=numel(G.nodes);seen=false(1,n);seen(start)=true;queue=start;hits=strings(0,1);
while ~isempty(queue)
    x=queue(1);queue(1)=[];b=string(G.nodes(x).block);
    if x~=start&&is_dynamic_signal_origin(b),hits(end+1,1)=b;end %#ok<AGROW>
    upstream=G.signal_reverse{x};
    % Simulink may omit a Goto input from DstPortHandle even though the line
    % is connected. Recover source port handles mechanically from the block
    % input lines; this adds connectivity, not controller semantics.
    upstream=unique([upstream(:);direct_input_source_nodes(G,b)],'stable');
    for y=upstream(:)'
        if ~seen(y),seen(y)=true;queue(end+1)=y;end %#ok<AGROW>
    end
end
hits=topmost(unique(hits,'stable'));
end
function nodes=direct_input_source_nodes(G,block)
nodes=[];try,ph=get_param(char(block),'PortHandles');catch,return;end
fields={'Inport','Enable','Trigger','Ifaction','Reset','Event'};
for f=1:numel(fields)
    if ~isfield(ph,fields{f}),continue;end
    for h=double(ph.(fields{f})(:))'
        lh=-1;try,lh=double(get_param(h,'Line'));catch,end;if lh<=0,continue;end
        src=[];try,src=double(get_param(lh,'SrcPortHandle'));catch,end
        for sh=src(:)'
            ix=find([G.nodes.port_handle]==sh&string({G.nodes.network})=="signal",1);
            if ~isempty(ix),nodes(end+1,1)=ix;end %#ok<AGROW>
        end
    end
end
nodes=unique(nodes,'stable');
end
function tf=is_dynamic_signal_origin(block)
bt=lower(string(getp(block,'BlockType')));d=meta(block);
patterns=["pulse","pwm","carrier","repeating sequence","signal generator", ...
    "sine wave","clock","timer","counter","step","ramp","from workspace", ...
    "modulat","matlab function","stateflow"];
tf=bt=="inport"||any(contains(d,patterns));
tf=tf&&bt~="constant"&&bt~="ground"&&bt~="from"&&bt~="goto";
end

function ok=vph_reference_valid(G,roots,adj,legs,sensors)
ok=false;for b=string(sensors(:))'
    d=meta(b);
    if contains(d,"three-phase vi measurement")||contains(d,"current and voltage sensor (three-phase)")
        mode=lower(string(getp(b,'VoltageMeasurement')));
        if contains(mode,"phase-to-ground")||contains(mode,"phase-to-neutral"),ok=true;return;end
        continue;
    end
    pair=block_pair(G,roots,b);if numel(pair)~=2,continue;end
    onPhase=false(1,2);
    for q=1:2,for l=1:numel(legs),onPhase(q)=onPhase(q)||ismember(pair(q),reachable(adj,legs{l}));end,end
    if sum(onPhase)~=1,continue;end;reference=pair(~onPhase);
    grounds=trusted_blocks(G,@is_ground);groundNets=[];
    for g=string(grounds(:))',groundNets=unique([groundNets block_pair(G,roots,g)],'stable');end
    if any(ismember(groundNets,reachable(adj,reference))),ok=true;return;end
end
end
function tf=is_ground(b)
d=meta(b);tf=contains(d,"electrical reference")||contains(d,"ground");
end

function adj=passive_net_adjacency(G,roots,mode)
n=numel(G.nodes);adj=cell(1,n);
for x=1:n
    for j=1:numel(G.physical_undirected{x})
        y=G.physical_undirected{x}(j);if y<=x,continue;end
        if string(G.physical_edge_kinds{x}{j})~="component_internal",continue;end
        block=string(G.nodes(x).block);if block~=string(G.nodes(y).block),continue;end
        if ~passive_allowed(block,mode),continue;end;a=roots(x);b=roots(y);
        if a==b,continue;end;adj{a}(end+1)=b;adj{b}(end+1)=a; %#ok<AGROW>
    end
end
for i=1:numel(adj),adj{i}=unique(adj{i},'stable');end
end
function tf=passive_allowed(block,mode)
d=meta(block);branch=upper(strtrim(string(getp(block,'BranchType'))));
sensor=contains(d,"current measurement")||contains(d,"current sensor") ...
    ||contains(d,"three-phase vi measurement")||contains(d,"current and voltage sensor (three-phase)");
series=contains(d,"series rlc branch")&&branch~="C";
tf=sensor||series||contains(d,"resistor")||contains(d,"inductor")||contains(d,"transformer");
if mode=="source_feed",tf=tf||contains(d,"breaker");end
end

function [ok,block,paths]=source_feeds_rails(G,roots,adj,sources,rails)
ok=false;block="";paths={};if numel(rails)~=2,return;end
for s=string(sources(:))'
    terminals=block_pair(G,roots,s);if numel(terminals)~=2,continue;end
    r1=reachable(adj,rails(1));r2=reachable(adj,rails(2));
    if ismember(terminals(1),r1)&&ismember(terminals(2),r2)
        ok=true;block=s;paths={shortest_net_path(adj,rails(1),terminals(1)),shortest_net_path(adj,rails(2),terminals(2))};return;
    elseif ismember(terminals(2),r1)&&ismember(terminals(1),r2)
        ok=true;block=s;paths={shortest_net_path(adj,rails(1),terminals(2)),shortest_net_path(adj,rails(2),terminals(1))};return;
    end
end
end

function [ok,sets]=legs_reach_sensors(G,roots,adj,legs,sensors,requireAll)
sets=cell(1,numel(legs));ok=false;if isempty(legs)||isempty(sensors),return;end
sensorNets=[];for b=string(sensors(:))',sensorNets=unique([sensorNets block_pair(G,roots,b)],'stable');end
for i=1:numel(legs),sets{i}=intersect(reachable(adj,legs{i}),sensorNets,'stable');end
if requireAll
    if numel(legs)~=3||~all(cellfun(@(x)~isempty(x),sets)),return;end
    disjoint=true;for i=1:3,for j=i+1:3,disjoint=disjoint&&isempty(intersect(sets{i},sets{j}));end,end
    ok=disjoint;
else,ok=any(cellfun(@(x)~isempty(x),sets));end
end

function [ok,sets]=sensor_branches_reach_load(G,roots,adj,sensorSets,loads)
sets=cell(1,numel(sensorSets));ok=false;if numel(sensorSets)~=3||isempty(loads),return;end
loadNets=[];for b=string(loads(:))',loadNets=unique([loadNets block_pair(G,roots,b)],'stable');end
for i=1:numel(sensorSets),sets{i}=intersect(reachable(adj,sensorSets{i}),loadNets,'stable');end
if ~all(cellfun(@(x)~isempty(x),sets)),return;end
disjoint=true;for i=1:3,for j=i+1:3,disjoint=disjoint&&isempty(intersect(sets{i},sets{j}));end,end
ok=disjoint;
end

function adj=net_adj(edges,n)
adj=cell(1,n);for i=1:size(edges,1),a=edges(i,1);b=edges(i,2);adj{a}(end+1)=b;adj{b}(end+1)=a;end
end
function nodes=reachable(adj,starts)
starts=unique(double(starts(:)'));nodes=starts;queue=starts;
while ~isempty(queue),x=queue(1);queue(1)=[];if x>numel(adj),continue;end
    for y=adj{x}(:)',if ~any(nodes==y),nodes(end+1)=y;queue(end+1)=y;end,end %#ok<AGROW>
end
end
function nodes=reachable_without(adj,start,barriers)
nodes=start;queue=start;
while ~isempty(queue),x=queue(1);queue(1)=[];if x>numel(adj),continue;end
    for y=adj{x}(:)',if any(barriers==y)||any(nodes==y),continue;end;nodes(end+1)=y;queue(end+1)=y;end %#ok<AGROW>
end
end
function path=shortest_net_path(adj,start,target)
path=[];if start==target,path=start;return;end;n=numel(adj);prev=zeros(1,n);seen=false(1,n);seen(start)=true;q=start;
while ~isempty(q),x=q(1);q(1)=[];for y=adj{x}(:)',if seen(y),continue;end;seen(y)=true;prev(y)=x;if y==target,q=[];break;end;q(end+1)=y;end,end %#ok<AGROW>
if target>n||~seen(target),return;end;path=target;while path(1)~=start,path=[prev(path(1)) path];end %#ok<AGROW>
end
function tf=any_related(a,b)
tf=false;for x=string(a(:))',for y=string(b(:))'
    if x==y||startsWith(x,y+"/")||startsWith(y,x+"/"),tf=true;return;end
end,end
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
function values=string_values(raw)
if ischar(raw),values=string(raw);elseif iscell(raw),values=string(raw(:));else,values=string(raw(:));end
values=values(strlength(values)>0);
end
function value=logical_field(s,name),value=isstruct(s)&&isfield(s,name)&&isscalar(s.(name))&&logical(s.(name));end
function v=getp(block,param),v='';try,v=get_param(char(block),param);catch,end;if isnumeric(v),v=num2str(v);end,end
function tf=identity_ok(spec,scenario),tf=isstruct(spec)&&isscalar(spec)&&isfield(spec,'id')&&string(spec.id)=="D002"&&string(scenario)=="nominal";end
function tf=has_fixture(state),tf=isstruct(state)&&isscalar(state)&&isfield(state,'evidence')&&isstruct(state.evidence)&&isfield(state.evidence,'unit_test_facts');end
function f=empty_facts()
f=struct('four_measured_capacitor_sections',false,'capacitor_blocks',strings(0,1), ...
    'capacitor_sensor_blocks',strings(0,1),'capacitor_edges',zeros(0,2), ...
    'dc_link_simple_chain',false,'dc_rail_nets',[],'dc_tap_nets',[], ...
    'dc_source_feeds_chain_rails',false,'dc_source_block',"",'dc_source_rail_paths',{{}}, ...
    'switch_blocks',strings(0,1),'switch_edges',zeros(0,2),'phase_leg_nets',{{}}, ...
    'phase_leg_switches',{{}},'three_active_phase_legs',false,'all_legs_span_rails',false, ...
    'clamp_diode_blocks',strings(0,1),'clamp_diode_directed_edges',zeros(0,2), ...
    'clamp_coverage_matrix',zeros(0,0),'clamp_directional_complete',false, ...
    'clamp_no_shared_tap_star',false,'clamp_potential_order_consistent',false, ...
    'clamp_potential_depths',struct(),'clamp_attachments',{{}}, ...
    'clamp_forward_paths',{{}},'clamp_reverse_paths',{{}}, ...
    'clamp_coverage_complete',false,'active_gate_ownership_complete',false, ...
    'gate_ownership',struct(), ...
    'iabc_sensor_blocks',strings(0,1),'vph_sensor_blocks',strings(0,1), ...
    'iabc_leg_sensor_nets',{{}},'vph_leg_sensor_nets',{{}}, ...
    'iabc_on_npc_output',false,'vph_on_npc_output',false,'vph_reference_valid',false, ...
    'load_blocks',strings(0,1), ...
    'iabc_leg_load_nets',{{}},'iabc_sensor_to_load',false, ...
    'power_path_uses_npc_switch',false,'power_path_uses_measured_dc_chain',false, ...
    'power_path_uses_iabc_sensor',false,'power_path_uses_npc_stage',false, ...
    'diagnostic_switch_count',0,'diagnostic_diode_count',0);
end
function r=make_report(evaluated,valid,ok,detail,evidence)
r=struct('task',"D002",'id',"D002.active_npc_topology",'kind',"task_specific", ...
    'semantic_kind',"structure",'scenario',"nominal",'layer',"qualification", ...
    'evaluated',logical(evaluated),'mandatory',true,'ok',logical(ok), ...
    'valid',logical(valid),'score',double(ok),'detail',string(detail),'evidence',evidence);
end
