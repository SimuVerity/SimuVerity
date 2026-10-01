function facts=sat_check_D025_foundation_npc(modelName,G,prefBlocks)
%SAT_CHECK_D025_FOUNDATION_NPC Native Simscape discrete-NPC proof.
% This is the Foundation-domain alternative to the source SPS proof used by
% D025.  It recognizes exact MathWorks library identities, reconstructs the
% electrical nets, proves three edge-disjoint four-IGBT legs sharing DC rails,
% proves six neutral-clamping diodes and three grid-interface branches, then
% binds twelve exact Simulink-PS gate converters to P_ref and physical V/I
% feedback.  User-visible block names are never used as evidence.

facts=empty_facts();facts.evaluated=true;
try
    blocks=find_system(modelName,'LookUnderMasks','all','FollowLinks','on','Type','Block');
    igbt=exact_blocks(blocks,"ee_lib/semiconductors & converters/igbt (ideal, switching)","igbt (ideal, switching)");
    diode=exact_blocks(blocks,"ee_lib/semiconductors & converters/diode","diode");
    if isempty(igbt)&&isempty(diode)
        facts.applicable=false;facts.detail="FOUNDATION_NPC_NOT_PRESENT";return;
    end
    facts.applicable=true;facts.switch_blocks=igbt;facts.clamp_blocks=diode;
    if numel(igbt)~=12||numel(diode)~=6
        facts.detail="FOUNDATION_NPC_DEVICE_POPULATION_MISMATCH";return;
    end

    gateConverters=exact_converters(blocks,"simulink-ps converter");
    psSensors=exact_converters(blocks,"ps-simulink converter");
    currentSensors=exact_blocks(blocks,"fl_lib/electrical/electrical sensors/current sensor","current sensor");
    voltageSensors=exact_blocks(blocks,"fl_lib/electrical/electrical sensors/voltage sensor","voltage sensor");
    dcBlocks=[exact_blocks(blocks,"fl_lib/electrical/electrical sources/dc voltage source","dc voltage source"); ...
        exact_blocks(blocks,"fl_lib/electrical/electrical elements/capacitor","capacitor")];
    passive=[currentSensors; ...
        exact_blocks(blocks,"fl_lib/electrical/electrical elements/resistor","resistor"); ...
        exact_blocks(blocks,"fl_lib/electrical/electrical elements/inductor","inductor")];
    gridBlocks=exact_blocks(blocks,"fl_lib/electrical/electrical sources/ac voltage source","ac voltage source");

    allPorts=collect_connection_ports([igbt;diode;gateConverters;psSensors; ...
        currentSensors;voltageSensors;dcBlocks;passive;gridBlocks]);
    [netMap,~]=sat_native_physical_line_nets(modelName,allPorts);
    switchEdges=component_edges(igbt,netMap,"electrical");
    clampEdges=component_edges(diode,netMap,"electrical");
    dcEdges=component_edges(dcBlocks,netMap,"electrical");
    passiveEdges=component_edges(passive,netMap,"electrical");
    if numel(switchEdges)~=12||numel(clampEdges)~=6
        facts.detail="FOUNDATION_NPC_DEVICE_TERMINALS_UNRESOLVED";return;
    end

    [legOk,rails,legs]=three_four_switch_legs(switchEdges);
    facts.dc_rails=rails;facts.leg_paths=legs;
    if ~legOk,facts.detail="FOUNDATION_NPC_THREE_LEG_TOPOLOGY_INVALID";return;end
    [neutralOk,neutral]=split_dc_neutral(rails,dcEdges);
    facts.dc_neutral=neutral;
    if ~neutralOk,facts.detail="FOUNDATION_NPC_SPLIT_DC_NEUTRAL_INVALID";return;end
    [clampOk,clampUsed]=clamp_topology(legs,neutral,clampEdges);
    facts.clamp_edge_indices=clampUsed;
    if ~clampOk,facts.detail="FOUNDATION_NPC_CLAMP_TOPOLOGY_INVALID";return;end
    [interfaceOk,gridHits]=grid_interfaces(legs,passiveEdges,gridBlocks,netMap);
    facts.grid_interface_blocks=gridHits;
    if ~interfaceOk,facts.detail="FOUNDATION_NPC_GRID_INTERFACES_INVALID";return;end
    facts.topology_ok=true;

    [gateOk,gateRows,gateInputNodes,controllerProof]=gate_converter_ownership( ...
        igbt,gateConverters,netMap,G,prefBlocks);
    facts.gate_rows=gateRows;facts.gate_converter_blocks=string({gateRows.converter})';
    facts.controller_gate_proof=controllerProof;
    facts.gate_coverage=sum([gateRows.ok]);
    if ~gateOk,facts.detail="FOUNDATION_NPC_GATE_CONVERTER_OWNERSHIP_INVALID";return;end

    [feedbackOk,currentSources,voltageSources,feedbackDetail]=measurement_sources( ...
        currentSensors,voltageSensors,psSensors,netMap,G);
    facts.current_feedback_sources=currentSources;
    facts.voltage_feedback_sources=voltageSources;
    if ~feedbackOk,facts.detail=feedbackDetail;return;end
    [measurementOwned,measurementProof]=controller_measurement_gate_lineage( ...
        G,controllerProof,currentSources,voltageSources);
    facts.measurement_controller_proof=measurementProof;
    currentOwned=false(size(gateInputNodes));voltageOwned=false(size(gateInputNodes));
    if measurementOwned
        currentOwned(:)=true;voltageOwned(:)=true;
    end
    facts.current_feedback_gate_coverage=sum(currentOwned);
    facts.voltage_feedback_gate_coverage=sum(voltageOwned);
    if ~all(currentOwned)||~all(voltageOwned)
        facts.detail="FOUNDATION_NPC_MEASUREMENT_TO_GATE_LINEAGE_INCOMPLETE";return;
    end
    facts.valid=true;facts.ok=true;facts.detail="OK";
catch ex
    facts.detail="FOUNDATION_NPC_PROOF_ERROR:"+string(ex.identifier);
    facts.error=string(strtrim(ex.message));
end
end

function blocks=exact_blocks(allBlocks,reference,mask)
blocks=strings(0,1);reference=normpath(reference);mask=normtext(mask);
for i=1:numel(allBlocks)
    b=allBlocks{i};
    if normpath(getp(b,'ReferenceBlock'))~=reference ...
            ||normtext(getp(b,'MaskType'))~=mask||~trusted_link(getp(b,'LinkStatus'))
        continue;
    end
    blocks(end+1,1)=string(b); %#ok<AGROW>
end
blocks=unique(blocks,'stable');
end

function blocks=exact_converters(allBlocks,kind)
if kind=="simulink-ps converter"
    rb="nesl_utility/simulink-ps converter";
else
    rb="nesl_utility/ps-simulink converter";
end
blocks=exact_blocks(allBlocks,rb,kind);
keep=false(size(blocks));
for i=1:numel(blocks),keep(i)=strcmpi(getp(blocks(i),'BlockType'),'SubSystem');end
blocks=blocks(keep);
end

function ports=collect_connection_ports(blocks)
ports=[];
for b=string(blocks(:))'
    try,ph=get_param(b,'PortHandles');catch,continue;end
    for f={'LConn','RConn'}
        if isfield(ph,f{1}),ports=[ports double(ph.(f{1})(:)')];end %#ok<AGROW>
    end
end
ports=unique(ports(ports>0));
end

function edges=component_edges(blocks,netMap,kind)
edges=struct('block',{},'u',{},'v',{});
for b=string(blocks(:))'
    if kind=="electrical"
        ports=ports_of_type(b,"network_engine_domain.foundation.electrical.electrical");
    else
        ports=ports_of_type(b,kind);
    end
    if numel(ports)~=2,continue;end
    u=port_net(ports(1),netMap);v=port_net(ports(2),netMap);
    if ~isfinite(u)||~isfinite(v)||u==v,continue;end
    edges(end+1)=struct('block',b,'u',u,'v',v); %#ok<AGROW>
end
end

function [ok,rails,chosen]=three_four_switch_legs(edges)
ok=false;rails=zeros(1,0);chosen=struct('nodes',{},'edges',{});
nodes=unique([[edges.u] [edges.v]]);degree=zeros(size(nodes));
for i=1:numel(nodes),degree(i)=sum([edges.u]==nodes(i)|[edges.v]==nodes(i));end
candidates=nodes(degree>=3);
for i=1:numel(candidates),for j=i+1:numel(candidates)
    paths=enumerate_paths(edges,candidates(i),candidates(j),4);
    for a=1:numel(paths),for b=a+1:numel(paths),for c=b+1:numel(paths)
        pick=paths([a b c]);used=unique([pick.edges]);
        if numel(used)~=12,continue;end
        i1=pick(1).nodes(2:end-1);i2=pick(2).nodes(2:end-1);i3=pick(3).nodes(2:end-1);
        if ~isempty(intersect(i1,i2))||~isempty(intersect(i1,i3))||~isempty(intersect(i2,i3)),continue;end
        rails=[candidates(i) candidates(j)];chosen=pick;ok=true;return;
    end,end,end
end,end
end

function paths=enumerate_paths(edges,start,goal,depth)
paths=struct('nodes',{},'edges',{});
walk(start,start,zeros(1,0),depth);
    function walk(node,nodesUsed,edgesUsed,left)
        if left==0
            if node==goal,paths(end+1)=struct('nodes',nodesUsed,'edges',edgesUsed);end %#ok<AGROW>
            return;
        end
        for e=1:numel(edges)
            if any(edgesUsed==e),continue;end
            next=NaN;if edges(e).u==node,next=edges(e).v;elseif edges(e).v==node,next=edges(e).u;end
            if ~isfinite(next)||any(nodesUsed==next),continue;end
            walk(next,[nodesUsed next],[edgesUsed e],left-1);
        end
    end
end

function [ok,neutral]=split_dc_neutral(rails,dcEdges)
ok=false;neutral=NaN;nodes=unique([[dcEdges.u] [dcEdges.v]]);
for n=nodes
    if any(rails==n),continue;end
    a=any_edge(dcEdges,rails(1),n);b=any_edge(dcEdges,rails(2),n);
    if a&&b,neutral=n;ok=true;return;end
end
end

function [ok,used]=clamp_topology(legs,neutral,edges)
ok=false;used=zeros(1,0);
for p=1:numel(legs)
    upper=legs(p).nodes(2);lower=legs(p).nodes(4);
    a=find_edge(edges,neutral,upper);b=find_edge(edges,neutral,lower);
    if isempty(a)||isempty(b),return;end
    used=[used a(1) b(1)]; %#ok<AGROW>
end
ok=numel(unique(used))==6&&numel(edges)==6;
end

function [ok,hits]=grid_interfaces(legs,passiveEdges,gridBlocks,netMap)
ok=false;hits=strings(0,1);
for p=1:numel(legs)
    reach=net_reach(passiveEdges,legs(p).nodes(3));found="";
    for b=string(gridBlocks(:))'
        ports=ports_of_type(b,"network_engine_domain.foundation.electrical.electrical");
        nets=arrayfun(@(h)port_net(h,netMap),ports);nets=nets(isfinite(nets));
        if any(ismember(nets,reach)),found=b;break;end
    end
    if strlength(found)==0,return;end
    hits(end+1,1)=found; %#ok<AGROW>
end
ok=numel(unique(hits))==3;
end

function [ok,rows,inputNodes,controllerProof]=gate_converter_ownership(igbt,converters,netMap,G,prefBlocks)
rows=struct('switch_block',{},'converter',{},'gate_net',{},'command_reaches',{},'ok',{});
inputNodes=zeros(1,0);ok=false;used=strings(0,1);
controllerProof=empty_controller_proof();
for b=string(igbt(:))'
    gate=ports_of_type(b,"network_engine_domain.input");
    if numel(gate)~=1,return;end
    net=port_net(gate,netMap);matches=strings(0,1);
    for c=string(converters(:))'
        out=ports_of_type(c,"network_engine_domain.output");
        if numel(out)==1&&port_net(out,netMap)==net,matches(end+1,1)=c;end %#ok<AGROW>
    end
    if numel(matches)~=1,return;end
    node=signal_field_nodes(G,matches,"in");
    if numel(node)~=1,return;end
    rows(end+1)=struct('switch_block',b,'converter',matches, ...
        'gate_net',net,'command_reaches',false,'ok',false); %#ok<AGROW>
    inputNodes(end+1)=node;used(end+1,1)=matches; %#ok<AGROW>
end
if numel(rows)~=12||numel(unique(used))~=12,return;end
[controllerOk,owned,controllerProof]=d025_controller_gate_lineage(G,prefBlocks,inputNodes);
for i=1:numel(rows)
    rows(i).command_reaches=logical(controllerOk&&owned(i));
    rows(i).ok=rows(i).command_reaches;
end
ok=controllerOk&&all([rows.ok]);
end

function [ok,owned,proof]=d025_controller_gate_lineage(G,prefBlocks,gateInputNodes)
% The generic signal graph intentionally does not traverse arbitrary MATLAB
% Function blocks.  D025 therefore uses a narrow, port-sensitive proof: the
% bound P_ref block must reach the chart input named Pref_kW, the chart
% output named gates must reach every exact Simulink-PS converter, and all
% twelve final gate elements must be data-dependent on Pref_kW in the chart.
ok=false;owned=false(size(gateInputNodes));proof=empty_controller_proof();
prefNodes=blocks_to_nodes(G,prefBlocks,"signal");
if isempty(prefNodes),proof.detail="D025_PREF_SIGNAL_NODE_UNRESOLVED";return;end
prefReach=signal_reach(G,prefNodes);
try
    root=sfroot;charts=root.find('-isa','Stateflow.EMChart');
catch ex
    proof.detail="D025_CONTROLLER_CHART_ENUMERATION_FAILED";
    proof.error=string(strtrim(ex.message));return;
end
candidates=struct('controller',{},'pref_port',{},'gate_port',{}, ...
    'owned',{},'tainted_variables',{});
proof.stage_counts.charts=numel(charts);
for i=1:numel(charts)
    controller=string(charts(i).Path);
    if ~is_local_matlab_function(controller),continue;end
    proof.stage_counts.local_matlab_function=proof.stage_counts.local_matlab_function+1;
    script=string(charts(i).Script);
    [signatureOk,prefPort,gatePort]=controller_signature(script);
    if ~signatureOk,continue;end
    proof.stage_counts.signature=proof.stage_counts.signature+1;
    [dependencyOk,tainted,gateCoverage]=gate_dependency(script);
    proof.last_gate_coverage=find(gateCoverage);
    proof.last_tainted_variables=tainted;
    if ~dependencyOk,continue;end
    proof.stage_counts.gate_dependency=proof.stage_counts.gate_dependency+1;
    inNode=signal_port_node(G,controller,"in",prefPort);
    outNode=signal_port_node(G,controller,"out",gatePort);
    if numel(inNode)~=1||numel(outNode)~=1||~prefReach(inNode),continue;end
    proof.stage_counts.pref_port_reached=proof.stage_counts.pref_port_reached+1;
    gateReach=signal_reach(G,outNode);thisOwned=gateReach(gateInputNodes);
    if ~all(thisOwned),continue;end
    proof.stage_counts.all_gate_converters_reached= ...
        proof.stage_counts.all_gate_converters_reached+1;
    candidates(end+1)=struct('controller',controller, ... %#ok<AGROW>
        'pref_port',prefPort,'gate_port',gatePort,'owned',thisOwned, ...
        'tainted_variables',tainted);
end
if numel(candidates)~=1
    proof.detail="D025_CONTROLLER_GATE_OWNER_NOT_UNIQUE";
    proof.candidate_count=numel(candidates);return;
end
owned=candidates.owned;proof.valid=true;proof.ok=true;proof.detail="OK";
proof.controller=candidates.controller;proof.pref_input_port=candidates.pref_port;
proof.gate_output_port=candidates.gate_port;
proof.gate_converter_coverage=sum(owned);
proof.tainted_variables=candidates.tainted_variables;
ok=true;
end

function [ok,prefPort,gatePort]=controller_signature(script)
ok=false;prefPort=NaN;gatePort=NaN;
tok=regexpi(char(script),['(?m)^\s*function\s+' ...
    '(?<lhs>\[[^\]]+\]|[A-Za-z]\w*)\s*=\s*[A-Za-z]\w*\s*' ...
    '\((?<args>[^\)]*)\)'],'names','once');
if isempty(tok),return;end
lhs=regexprep(string(tok.lhs),'[\[\]\s]','');
args=regexprep(string(tok.args),'\s','');
outputs=split(lhs,',');inputs=split(args,',');
pref=find(inputs=="Pref_kW");gate=find(outputs=="gates");
if numel(pref)~=1||numel(gate)~=1,return;end
prefPort=pref;gatePort=gate;ok=true;
end

function [ok,taintedNames,coverage]=gate_dependency(script,sourceName)
% Ordered, conservative taint propagation over the chart's assignments.
% Reassigning a variable with a P_ref-independent expression clears taint,
% and a later untainted overwrite of any gate slice clears that slice.  This
% prevents a decorative Pref_kW read or a tainted write followed by constants
% from satisfying the proof.
if nargin<2,sourceName="Pref_kW";end
ok=false;taintedNames=string(sourceName);coverage=false(1,12);
% MATLAB regexp's dot can span line breaks, so "%.*$" would erase the
% entire chart from the first comment onward.  Remove only characters on
% the same physical source line.
clean=regexprep(char(script),'%[^\r\n]*','');
assignments=regexpi(clean,['(?m)(?<lhs>[A-Za-z]\w*' ...
    '(?:\s*\([^=;\r\n]*\))?)\s*=\s*(?<rhs>[^;\r\n]+)'],'names');
for i=1:numel(assignments)
    lhs=strtrim(string(assignments(i).lhs));rhs=string(assignments(i).rhs);
    base=regexp(char(lhs),'^\s*([A-Za-z]\w*)','tokens','once');
    if isempty(base),continue;end
    base=string(base{1});rhsTainted=false;
    for name=taintedNames(:)'
        token=['(?<![A-Za-z0-9_])' regexptranslate('escape',char(name)) ...
            '(?![A-Za-z0-9_])'];
        if ~isempty(regexpi(char(rhs),token,'once'))
            rhsTainted=true;break;
        end
    end
    if rhsTainted
        if ~any(taintedNames==base),taintedNames(end+1,1)=base;end %#ok<AGROW>
    else
        taintedNames(taintedNames==base)=[];
    end
    if base~="gates",continue;end
    subs=regexp(char(lhs),'gates\s*\(([^\)]*)\)','tokens','once');
    if isempty(subs)
        coverage(:)=rhsTainted;
    else
        ids=literal_gate_indices(string(subs{1}));
        if isempty(ids),coverage(:)=false;else,coverage(ids)=rhsTainted;end
    end
end
ok=all(coverage);
taintedNames=unique(taintedNames,'stable');
end

function [ok,proof]=controller_measurement_gate_lineage( ...
    G,controllerProof,currentSources,voltageSources)
% Bind the six exact PS-Simulink measurement converters to the six declared
% controller measurement inputs.  Each phase input must have one distinct
% physical source and must data-dependently influence all twelve final gate
% elements.  This crosses only the already authenticated D025 chart.
proof=struct('valid',false,'ok',false,'detail',"UNINITIALIZED", ...
    'controller',controllerProof.controller, ...
    'current_input_ports',zeros(1,0),'voltage_input_ports',zeros(1,0), ...
    'current_origin_matrix',false(0,0),'voltage_origin_matrix',false(0,0), ...
    'gate_dependency_coverage',false(6,12));
ok=false;controller=controllerProof.controller;
script="";
try
    root=sfroot;charts=root.find('-isa','Stateflow.EMChart');
    for i=1:numel(charts)
        if string(charts(i).Path)==controller,script=string(charts(i).Script);break;end
    end
catch
end
if strlength(script)==0
    proof.detail="D025_MEASUREMENT_CONTROLLER_SCRIPT_UNREADABLE";return;
end
[signatureOk,inputNames]=controller_input_names(script);
if ~signatureOk,proof.detail="D025_MEASUREMENT_CONTROLLER_SIGNATURE_INVALID";return;end
currentNames=["ia","ib","ic"];voltageNames=["va","vb","vc"];
currentPorts=zeros(1,3);voltagePorts=zeros(1,3);
for i=1:3
    q=find(inputNames==currentNames(i));if numel(q)~=1,return;end;currentPorts(i)=q;
    q=find(inputNames==voltageNames(i));if numel(q)~=1,return;end;voltagePorts(i)=q;
end
proof.current_input_ports=currentPorts;proof.voltage_input_ports=voltagePorts;
currentTargets=zeros(1,3);voltageTargets=zeros(1,3);
for i=1:3
    q=signal_port_node(G,controller,"in",currentPorts(i));if numel(q)~=1,return;end
    currentTargets(i)=q;
    q=signal_port_node(G,controller,"in",voltagePorts(i));if numel(q)~=1,return;end
    voltageTargets(i)=q;
end
[currentOk,currentMatrix]=distinct_source_to_ports(G,currentSources,currentTargets);
[voltageOk,voltageMatrix]=distinct_source_to_ports(G,voltageSources,voltageTargets);
proof.current_origin_matrix=currentMatrix;proof.voltage_origin_matrix=voltageMatrix;
if ~currentOk,proof.detail="D025_CURRENT_SENSOR_TO_CONTROLLER_PORTS_INVALID";return;end
if ~voltageOk,proof.detail="D025_VOLTAGE_SENSOR_TO_CONTROLLER_PORTS_INVALID";return;end
names=[currentNames voltageNames];
for i=1:6
    [depOk,~,coverage]=gate_dependency(script,names(i));
    proof.gate_dependency_coverage(i,:)=coverage;
    if ~depOk
        proof.detail="D025_MEASUREMENT_INPUT_NOT_GATE_CAUSAL:"+names(i);return;
    end
end
proof.valid=true;proof.ok=true;proof.detail="OK";ok=true;
end

function [ok,names]=controller_input_names(script)
ok=false;names=strings(0,1);
tok=regexpi(char(script),['(?m)^\s*function\s+' ...
    '(?:\[[^\]]+\]|[A-Za-z]\w*)\s*=\s*[A-Za-z]\w*\s*' ...
    '\((?<args>[^\)]*)\)'],'names','once');
if isempty(tok),return;end
names=split(regexprep(string(tok.args),'\s',''),',');
ok=~isempty(names)&&all(strlength(names)>0);
end

function [ok,matrix]=distinct_source_to_ports(G,sources,targets)
sources=unique(double(sources(:)'),'stable');targets=double(targets(:)');
matrix=false(numel(sources),numel(targets));
for i=1:numel(sources)
    reach=signal_reach(G,sources(i));matrix(i,:)=reach(targets);
end
[row,~]=find(matrix);ok=all(sum(matrix,1)==1)&&numel(unique(row))==numel(targets);
end

function ids=literal_gate_indices(expr)
ids=[];expr=erase(strtrim(expr),' ');
if ~isempty(regexp(char(expr),'^\d+$','once'))
    ids=str2double(expr);
elseif ~isempty(regexp(char(expr),'^\d+:\d+$','once'))
    parts=str2double(split(expr,':'));ids=parts(1):parts(2);
elseif ~isempty(regexp(char(expr),'^[\[\]\d,]+$','once'))
    nums=regexp(char(expr),'\d+','match');ids=str2double(nums);
end
ids=unique(ids(ids>=1&ids<=12));
end

function node=signal_port_node(G,block,kind,ordinal)
node=find([G.nodes.block]==block&[G.nodes.network]=="signal" ...
    &[G.nodes.port_ordinal]==ordinal);
field=lower(string({G.nodes(node).port_field}));
if kind=="in",node=node(contains(field,"in"));else,node=node(contains(field,"out"));end
end

function ok=is_local_matlab_function(block)
ok=false;
try
    ok=strcmpi(strtrim(get_param(block,'BlockType')),'SubSystem') ...
        &&strcmpi(strtrim(get_param(block,'SFBlockType')),'MATLAB Function') ...
        &&isempty(strtrim(getp(block,'ReferenceBlock')));
catch
end
end

function [ok,currentSources,voltageSources,detail]=measurement_sources( ...
    currentSensors,voltageSensors,converters,netMap,G)
[currentOk,currentSources]=one_measurement_kind(currentSensors,converters,netMap,G);
[voltageOk,voltageSources]=one_measurement_kind(voltageSensors,converters,netMap,G);
ok=currentOk&&voltageOk;
if ~currentOk
    detail="FOUNDATION_NPC_CURRENT_FEEDBACK_SOURCE_INVALID";
elseif ~voltageOk
    detail="FOUNDATION_NPC_VOLTAGE_FEEDBACK_SOURCE_INVALID";
else
    detail="OK";
end
end

function [ok,sources]=one_measurement_kind(sensors,converters,netMap,G)
sources=zeros(1,0);used=strings(0,1);ok=false;
for s=string(sensors(:))'
    out=ports_of_type(s,"network_engine_domain.output");if numel(out)~=1,continue;end
    net=port_net(out,netMap);matches=strings(0,1);
    for c=string(converters(:))'
        in=ports_of_type(c,"network_engine_domain.input");
        if numel(in)==1&&port_net(in,netMap)==net,matches(end+1,1)=c;end %#ok<AGROW>
    end
    if numel(matches)~=1,continue;end
    node=signal_field_nodes(G,matches,"out");if numel(node)~=1,continue;end
    sources(end+1)=node;used(end+1,1)=matches; %#ok<AGROW>
end
ok=numel(unique(used))>=3&&numel(unique(sources))>=3;
sources=unique(sources,'stable');
end

function ports=ports_of_type(block,type)
ports=[];try,ph=get_param(block,'PortHandles');catch,return;end
for f={'LConn','RConn'}
    if ~isfield(ph,f{1}),continue;end
    for h=double(ph.(f{1})(:)')
        ct=normtext(getport(h,'ConnectionType'));
        if ct==normtext(type),ports(end+1)=h;end %#ok<AGROW>
    end
end
ports=unique(ports);
end

function net=port_net(port,map)
net=NaN;try,line=double(get_param(port,'Line'));catch,return;end
if isempty(line)||line<=0,return;end
key=sprintf('%.15g',line);if isKey(map,key),net=double(map(key));end
end
function yes=any_edge(edges,a,b),yes=~isempty(find_edge(edges,a,b));end
function ids=find_edge(edges,a,b)
ids=find(([edges.u]==a&[edges.v]==b)|([edges.u]==b&[edges.v]==a));
end
function seen=net_reach(edges,start)
seen=start;queue=start;
while ~isempty(queue)
    x=queue(1);queue(1)=[];ids=find([edges.u]==x|[edges.v]==x);
    for e=ids
        if edges(e).u==x,y=edges(e).v;else,y=edges(e).u;end
        if ~any(seen==y),seen(end+1)=y;queue(end+1)=y;end %#ok<AGROW>
    end
end
end
function reach=signal_reach(G,start),reach=graph_reach(G.signal_forward,start,numel(G.nodes));end
function seen=graph_reach(adj,start,n)
seen=false(1,n);queue=unique(double(start(:)'));queue=queue(queue>=1&queue<=n);seen(queue)=true;
while ~isempty(queue),x=queue(1);queue(1)=[];for y=adj{x},if ~seen(y),seen(y)=true;queue(end+1)=y;end,end,end %#ok<AGROW>
end
function ids=blocks_to_nodes(G,blocks,network)
ids=[];for b=string(blocks(:))',ids=[ids find([G.nodes.block]==b&[G.nodes.network]==network)];end;ids=unique(ids); %#ok<AGROW>
end
function ids=signal_field_nodes(G,block,kind)
ids=find([G.nodes.block]==block&[G.nodes.network]=="signal");f=lower(string({G.nodes(ids).port_field}));
if kind=="in",ids=ids(contains(f,"in")|f=="enable"|f=="trigger");else,ids=ids(contains(f,"out")|f=="state");end
end
function yes=trusted_link(link),yes=any(normtext(link)==["resolved","implicit"]);end
function value=getp(block,param),value='';try,value=get_param(block,param);catch,end;if isnumeric(value),value=num2str(value);end,end
function value=getport(port,param),value='';try,value=get_param(port,param);catch,end;if isnumeric(value),value=num2str(value);end,end
function value=normtext(value),value=lower(strtrim(regexprep(string(value),'\s+',' ')));end
function value=normpath(value),value=replace(normtext(value),'\','/');end
function p=empty_controller_proof()
p=struct('valid',false,'ok',false,'detail',"UNINITIALIZED",'error',"", ...
    'candidate_count',0,'controller',"",'pref_input_port',NaN, ...
    'gate_output_port',NaN,'gate_converter_coverage',0, ...
    'tainted_variables',strings(0,1),'stage_counts',struct( ...
    'charts',0,'local_matlab_function',0,'signature',0, ...
    'gate_dependency',0,'pref_port_reached',0, ...
    'all_gate_converters_reached',0),'last_gate_coverage',zeros(1,0), ...
    'last_tainted_variables',strings(0,1));
end
function f=empty_facts()
f=struct('evaluated',false,'applicable',false,'valid',false,'ok',false, ...
    'topology_ok',false,'detail',"UNINITIALIZED",'error',"",'switch_blocks',strings(0,1), ...
    'clamp_blocks',strings(0,1),'dc_rails',zeros(1,0),'dc_neutral',NaN, ...
    'leg_paths',struct([]),'clamp_edge_indices',zeros(1,0), ...
    'grid_interface_blocks',strings(0,1),'gate_rows',struct([]), ...
    'gate_converter_blocks',strings(0,1),'gate_coverage',0, ...
    'controller_gate_proof',empty_controller_proof(), ...
    'measurement_controller_proof',struct(), ...
    'current_feedback_sources',zeros(1,0),'voltage_feedback_sources',zeros(1,0), ...
    'current_feedback_gate_coverage',0,'voltage_feedback_gate_coverage',0);
end
