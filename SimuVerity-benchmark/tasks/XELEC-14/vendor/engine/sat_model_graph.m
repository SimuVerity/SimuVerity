function G = sat_model_graph(modelName)
%SAT_MODEL_GRAPH Build deterministic mechanical signal/physical graph facts.
% This function deliberately owns no engineering verdict.  It records
% blocks, ports, line/boundary/routing edges, and unsupported boundaries.

modelName=char(string(modelName));
assert(bdIsLoaded(modelName),'SimuVerity:Graph:ModelNotLoaded', ...
    'Model must be loaded before graph construction: %s',modelName);
blocks=find_system(modelName,'LookUnderMasks','all','FollowLinks','on','Type','Block');
blocks=sort(blocks(:));

blockRows=struct('block',{},'descriptor',{});
nodes=struct('node_id',{},'block',{},'port_handle',{},'port_field',{}, ...
    'port_ordinal',{},'descriptor',{},'network',{});
handleToNode=containers.Map('KeyType','char','ValueType','double');
blockToNodes=containers.Map('KeyType','char','ValueType','any');
for i=1:numel(blocks)
    block=blocks{i}; descriptor=descriptor_for(modelName,block);
    blockRows(end+1)=struct('block',string(block),'descriptor',descriptor); %#ok<AGROW>
    ph=[];try,ph=get_param(block,'PortHandles');catch,end
    if isempty(ph),continue;end
    fields=fieldnames(ph);
    for f=1:numel(fields)
        hs=ph.(fields{f});
        for q=1:numel(hs)
            h=double(hs(q));if ~isfinite(h)||h<=0,continue;end
            portType="";try,portType=string(get_param(h,'PortType'));catch,end
            network="signal";if strcmpi(portType,"connection"),network="physical";end
            nodeId=numel(nodes)+1;
            nodes(nodeId)=struct('node_id',nodeId,'block',string(block), ...
                'port_handle',h,'port_field',string(fields{f}), ...
                'port_ordinal',double(q),'descriptor',descriptor, ...
                'network',network); %#ok<AGROW>
            handleToNode(handle_key(h))=nodeId;
            if isKey(blockToNodes,block),ids=blockToNodes(block);else,ids=[];end
            blockToNodes(block)=[ids nodeId];
        end
    end
end

n=numel(nodes);signalForward=cell(1,n);signalForwardKinds=cell(1,n);
physical=cell(1,n);physicalKinds=cell(1,n);
unsupported=struct('block',{},'reason',{},'node_ids',{});

% Ordinary Simulink signal lines.
lines=find_system(modelName,'FindAll','on','Type','line');
for i=1:numel(lines)
    sh=[];dh=[];
    try,sh=get_param(lines(i),'SrcPortHandle');dh=get_param(lines(i),'DstPortHandle');catch,continue;end
    sh=double(sh(:)');dh=double(dh(:)');
    for a=sh
        sk=handle_key(a);if a<=0||~isKey(handleToNode,sk),continue;end
        s=handleToNode(sk);if nodes(s).network~="signal",continue;end
        for b=dh
            dk=handle_key(b);if b<=0||~isKey(handleToNode,dk),continue;end
            d=handleToNode(dk);if nodes(d).network~="signal",continue;end
            [signalForward,signalForwardKinds]=add_directed( ...
                signalForward,signalForwardKinds,s,d,"signal_line");
        end
    end
end

% Goto -> From routing is a mechanical tag edge.
gotos=find_system(modelName,'LookUnderMasks','all','FollowLinks','on','BlockType','Goto');
froms=find_system(modelName,'LookUnderMasks','all','FollowLinks','on','BlockType','From');
for i=1:numel(gotos)
    tag=getp(gotos{i},'GotoTag');src=signal_ports(blockToNodes,nodes,gotos{i},"input");
    for q=1:numel(froms)
        if ~strcmp(getp(froms{q},'GotoTag'),tag),continue;end
        dst=signal_ports(blockToNodes,nodes,froms{q},"output");
        [signalForward,signalForwardKinds]=connect_directed_sets( ...
            signalForward,signalForwardKinds,src,dst,"goto_from");
    end
end

% Map external subsystem ports to their internal Inport/Outport blocks.
subs=find_system(modelName,'LookUnderMasks','all','FollowLinks','on','BlockType','SubSystem');
for i=1:numel(subs)
    sub=subs{i};
    extIn=field_nodes(blockToNodes,nodes,sub,"Inport");
    extOut=field_nodes(blockToNodes,nodes,sub,"Outport");
    internalIn=find_system(sub,'SearchDepth',1,'LookUnderMasks','all', ...
        'FollowLinks','on','BlockType','Inport');
    internalOut=find_system(sub,'SearchDepth',1,'LookUnderMasks','all', ...
        'FollowLinks','on','BlockType','Outport');
    for q=1:numel(extIn)
        block=find_port_number(internalIn,q);dst=signal_ports(blockToNodes,nodes,block,"output");
        [signalForward,signalForwardKinds]=connect_directed_sets( ...
            signalForward,signalForwardKinds,extIn(q),dst,"subsystem_boundary");
    end
    for q=1:numel(extOut)
        block=find_port_number(internalOut,q);src=signal_ports(blockToNodes,nodes,block,"input");
        [signalForward,signalForwardKinds]=connect_directed_sets( ...
            signalForward,signalForwardKinds,src,extOut(q),"subsystem_boundary");
    end
end

% Ordinary signal-processing blocks mechanically propagate possible
% causality from each input-like port to each output-like port. This is not
% a semantic claim about control validity; it only closes block interiors
% so a port-aware path cannot teleport between independent line segments.
for i=1:numel(blockKeys_or_map(blockToNodes))
    keysNow=blockKeys_or_map(blockToNodes);block=keysNow{i};
    bt=getp(block,'BlockType');
    if any(strcmpi(bt,{'SubSystem','Goto','From','Inport','Outport'})),continue;end
    inputs=signal_ports(blockToNodes,nodes,block,"input");
    outputs=signal_ports(blockToNodes,nodes,block,"output");
    if isempty(inputs)||isempty(outputs),continue;end
    [signalForward,signalForwardKinds]=connect_directed_sets( ...
        signalForward,signalForwardKinds,inputs,outputs,"component_internal");
end

% Conserving-port nets.  Connectivity comes only from native line-family
% and exact PortConnectivity facts; drawing coordinates are never evidence.
physicalIds=find(string({nodes.network})=="physical");
[netByLine,nativeNetStats]=sat_native_physical_line_nets( ...
    modelName,[nodes(physicalIds).port_handle]);
physicalLineCount=nativeNetStats.physical_line_count;
netToNodes=containers.Map('KeyType','char','ValueType','any');
for i=1:n
    if nodes(i).network~="physical",continue;end
    lh=-1;try,lh=double(get_param(nodes(i).port_handle,'Line'));catch,end
    key=handle_key(lh);if lh<=0||~isKey(netByLine,key),continue;end
    nk=sprintf('%d',netByLine(key));
    if isKey(netToNodes,nk),ids=netToNodes(nk);else,ids=[];end
    netToNodes(nk)=[ids i];
end
keysNet=keys(netToNodes);
for i=1:numel(keysNet)
    [physical,physicalKinds]=connect_undirected_clique(physical,physicalKinds, ...
        netToNodes(keysNet{i}),"physical_net");
end

% Conservative component/boundary mechanics. Unknown multi-terminal blocks
% remain disconnected and are explicitly recorded instead of guessed.
blockKeys=keys(blockToNodes);
for i=1:numel(blockKeys)
    block=blockKeys{i};allIds=blockToNodes(block);
    ids=allIds(string({nodes(allIds).network})=="physical");
    if isempty(ids),continue;end
    bt=getp(block,'BlockType');mt=getp(block,'MaskType');rb=getp(block,'ReferenceBlock');
    if strcmpi(bt,'PMIOPort')
        [mapped,parentNode,reason]=pmio_parent_node(block,ids,handleToNode);
        if mapped
            [physical,physicalKinds]=add_undirected(physical,physicalKinds, ...
                ids(1),parentNode,"subsystem_boundary");
        else
            unsupported(end+1)=unsupported_row(block,reason,ids); %#ok<AGROW>
        end
        continue;
    end
    if numel(ids)<2,continue;end
    if strcmpi(bt,'SubSystem')&&isempty(strtrim(mt))&&isempty(strtrim(rb)),continue;end
    [groups,supported,reason]=component_groups(block,ids,nodes,bt,mt,rb);
    if ~supported
        unsupported(end+1)=unsupported_row(block,reason,ids); %#ok<AGROW>
        continue;
    end
    for g=1:numel(groups)
        [physical,physicalKinds]=connect_undirected_clique(physical,physicalKinds, ...
            groups{g},"component_internal");
    end
end

signalReverse=cell(1,n);signalReverseKinds=cell(1,n);
for a=1:n
    for j=1:numel(signalForward{a})
        b=signalForward{a}(j);kind=signalForwardKinds{a}{j};
        [signalReverse,signalReverseKinds]=add_directed( ...
            signalReverse,signalReverseKinds,b,a,kind);
    end
end
for i=1:n
    [signalForward{i},signalForwardKinds{i}]=sort_edges(signalForward{i},signalForwardKinds{i});
    [signalReverse{i},signalReverseKinds{i}]=sort_edges(signalReverse{i},signalReverseKinds{i});
    [physical{i},physicalKinds{i}]=sort_edges(physical{i},physicalKinds{i});
end
G=struct('schema',"simuverity.sat-model-graph.v1",'model',string(modelName), ...
    'nodes',nodes,'blocks',blockRows,'signal_forward',{signalForward}, ...
    'signal_reverse',{signalReverse},'physical_undirected',{physical}, ...
    'signal_forward_edge_kinds',{signalForwardKinds}, ...
    'signal_reverse_edge_kinds',{signalReverseKinds}, ...
    'physical_edge_kinds',{physicalKinds},'unsupported',unsupported, ...
    'stats',struct('block_count',numel(blockRows),'port_count',n, ...
    'signal_port_count',sum(string({nodes.network})=="signal"), ...
    'physical_port_count',sum(string({nodes.network})=="physical"), ...
    'line_count',numel(lines),'physical_line_count',physicalLineCount, ...
    'native_branch_unions',nativeNetStats.native_branch_unions, ...
    'port_connectivity_unions',nativeNetStats.port_connectivity_unions, ...
    'unresolved_physical_ports',nativeNetStats.unresolved_physical_ports, ...
    'signal_contaminated_components',nativeNetStats.signal_contaminated_components, ...
    'unsupported_count',numel(unsupported)));
end

function [groups,supported,reason]=component_groups(block,ids,nodes,bt,mt,rb)
groups={};supported=true;reason="";
d=lower(strjoin(string({getp(block,'Name'),bt,mt,rb}),'|'));
if contains(d,'voltage measurement')&&~contains(d,'three-phase'),groups=num2cell(ids);return;end
L=ids(strcmpi([nodes(ids).port_field],'LConn'));R=ids(strcmpi([nodes(ids).port_field],'RConn'));
paired=contains(d,'three-phase vi measurement')||contains(d,'three-phase series rlc branch') ...
    ||contains(d,'three-phase parallel rlc branch')||contains(d,'three-phase breaker') ...
    ||contains(d,'current measurement');
if paired&&~isempty(L)&&numel(L)==numel(R)
    groups=cell(1,numel(L));for i=1:numel(L),groups{i}=[L(i) R(i)];end;return;
end
if numel(ids)==2,groups={ids};return;end
isThreeLevel=strcmpi(strtrim(mt),'Three-Level Bridge') ...
    &&contains(lower(string(rb)),'spsthreelevelbridgelib/three-level bridge');
knownEnergy=contains(d,'universal bridge')||isThreeLevel||contains(d,'converter') ...
    ||contains(d,'inverter')||contains(d,'rectifier')||contains(d,'transformer') ...
    ||contains(d,'machine')||contains(d,'motor')||contains(d,'generator') ...
    ||contains(d,'voltage source')||contains(d,'current source') ...
    ||contains(d,'thyristor')||contains(d,'diode bridge');
terminal=contains(d,'three-phase series rlc load') ...
    ||contains(d,'three-phase parallel rlc load')||contains(d,'ground');
if knownEnergy,groups={ids};elseif terminal,groups=num2cell(ids); ...
else,supported=false;reason="UNSUPPORTED_MULTI_TERMINAL_SEMANTICS";end
end

function [ok,parentNode,reason]=pmio_parent_node(block,ids,index)
ok=false;parentNode=[];reason="PMIO_BOUNDARY_UNMAPPED";
if numel(ids)~=1,reason="PMIO_PORT_COUNT_NOT_ONE";return;end
parent=getp(block,'Parent');if isempty(parent),reason="PMIO_PARENT_MISSING";return;end
ph=[];try,ph=get_param(parent,'PortHandles');catch,end
if isempty(ph),reason="PMIO_PARENT_PORTS_UNREADABLE";return;end
ordered=[];for f={'LConn','RConn'},if isfield(ph,f{1}),ordered=[ordered ph.(f{1})];end,end %#ok<AGROW>
port=str2double(getp(block,'Port'));
if ~isfinite(port)||port<1||port>numel(ordered),reason="PMIO_PORT_NUMBER_OUT_OF_RANGE";return;end
key=handle_key(ordered(port));if ~isKey(index,key),reason="PMIO_PARENT_CONNECTION_PORT_NOT_INDEXED";return;end
parentNode=index(key);ok=true;reason="";
end

function ids=signal_ports(map,nodes,block,direction)
ids=[];if isempty(block)||~isKey(map,block),return;end
all=map(block);all=all(string({nodes(all).network})=="signal");if isempty(all),return;end
fields=lower(string({nodes(all).port_field}));
if direction=="input",mask=contains(fields,"in")|fields=="enable"|fields=="trigger"; ...
else,mask=contains(fields,"out")|fields=="state";end
ids=all(mask);if isempty(ids),ids=all;end
end
function ids=field_nodes(map,nodes,block,field)
ids=[];if ~isKey(map,block),return;end
all=map(block);if isempty(all),return;end
ids=all(strcmpi(string({nodes(all).port_field}),field));
[~,order]=sort([nodes(ids).port_ordinal]);ids=ids(order);
end
function value=blockKeys_or_map(map),value=sort(keys(map));end
function block=find_port_number(blocks,number)
block='';for i=1:numel(blocks),if str2double(getp(blocks{i},'Port'))==number,block=blocks{i};return;end,end
end

function [adj,kinds]=connect_directed_sets(adj,kinds,src,dst,kind)
for a=src(:)',for b=dst(:)',[adj,kinds]=add_directed(adj,kinds,a,b,kind);end,end
end
function [adj,kinds]=connect_undirected_clique(adj,kinds,ids,kind)
ids=unique(ids);for i=1:numel(ids),for j=i+1:numel(ids),[adj,kinds]=add_undirected(adj,kinds,ids(i),ids(j),kind);end,end
end
function [adj,kinds]=add_directed(adj,kinds,a,b,kind)
if isempty(a)||isempty(b)||a==b||any(adj{a}==b),return;end
adj{a}(end+1)=b;kinds{a}{end+1}=char(kind);
end
function [adj,kinds]=add_undirected(adj,kinds,a,b,kind)
[adj,kinds]=add_directed(adj,kinds,a,b,kind);[adj,kinds]=add_directed(adj,kinds,b,a,kind);
end
function [ids,kinds]=sort_edges(ids,kinds)
if isempty(ids),return;end
[ids,order]=sort(ids);kinds=kinds(order);
end
function row=unsupported_row(block,reason,ids)
row=struct('block',string(block),'reason',string(reason),'node_ids',double(ids));
end
function d=descriptor_for(model,block)
full=string(block);prefix=string(model)+"/";rel=full;if startsWith(full,prefix),rel=extractAfter(full,strlength(prefix));end
d=lower(strjoin(string({rel,getp(block,'Name'),getp(block,'BlockType'), ...
    getp(block,'MaskType'),getp(block,'ReferenceBlock')}),'|'));
end
function value=getp(block,param)
value='';try,value=get_param(block,param);catch,end;if isnumeric(value),value=num2str(value);end
end
function key=handle_key(handle),key=sprintf('%.15g',double(handle));end
