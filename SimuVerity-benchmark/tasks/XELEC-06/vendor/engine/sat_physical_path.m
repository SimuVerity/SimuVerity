function [ok, detail, evidence] = sat_physical_path(modelName, sourcePatterns, viaPatterns, targetPatterns)
%SAT_PHYSICAL_PATH Conservative physical-network reachability check.
%   [OK, DETAIL, EVIDENCE] = SAT_PHYSICAL_PATH(MODEL, SOURCE, VIA, TARGET)
%   builds an undirected graph from Simulink conserving connection ports
%   (PortType == "connection"). Ordinary Simulink signal lines are never
%   added to the graph. VIA is optional and, when supplied, must itself be
%   physically reachable from SOURCE and able to reach TARGET. EVIDENCE also
%   reports whether the matching via set is a required cut; this diagnostic
%   is not mandatory because legitimate shunt devices are not series cuts.
%
%   The implementation covers the connection-port representation used by
%   Specialized Power Systems and Simscape, including PMIO subsystem
%   boundaries. Unknown multi-terminal component semantics are not guessed:
%   a query that may depend on one returns OK=false with status UNKNOWN.

ok=false;
evidence=empty_evidence();
try
    sourcePatterns=normalise_patterns(sourcePatterns);
    viaPatterns=normalise_patterns(viaPatterns);
    targetPatterns=normalise_patterns(targetPatterns);
    if isempty(sourcePatterns) || isempty(targetPatterns)
        evidence.status="UNKNOWN";
        evidence.reason="EMPTY_SOURCE_OR_TARGET_PATTERN";
        detail=char(evidence.status+":"+evidence.reason);
        return;
    end

    G=build_physical_graph(modelName);
    evidence.stats=G.stats;
    evidence.unsupported=G.unsupported;
    if isempty(G.nodes)
        evidence.status="UNKNOWN";
        evidence.reason="NO_SUPPORTED_PHYSICAL_CONNECTION_PORTS";
        detail=char(evidence.status+":"+evidence.reason);
        return;
    end

    [src,srcBlocks]=match_ports(G,sourcePatterns);
    [via,viaBlocks]=match_ports(G,viaPatterns);
    [dst,dstBlocks]=match_ports(G,targetPatterns);
    evidence.source_matches=srcBlocks;
    evidence.via_matches=viaBlocks;
    evidence.target_matches=dstBlocks;
    [early,evidence]=validate_matches(src,srcBlocks,via,viaBlocks,dst,dstBlocks,viaPatterns,evidence);
    if early
        detail=char(evidence.status+":"+evidence.reason);
        return;
    end

    portPath=[]; edgeKinds=strings(0,1);
    if isempty(viaPatterns)
        [found,portPath,edgeKinds]=shortest_path(G,src,dst);
    else
        found=false; bestN=inf;
        for v=via(:)'
            [a,p1,k1]=shortest_path(G,src,v);
            [b,p2,k2]=shortest_path(G,v,dst);
            if a && b
                p=[p1 p2(2:end)]; k=[k1; k2];
                if numel(p)<bestN
                    found=true; bestN=numel(p); portPath=p; edgeKinds=k;
                end
            end
        end
        if found
            [bypass,~,~]=shortest_path(G,src,dst,via);
            evidence.via_is_cut=~bypass;
        end
    end

    if found
        ok=true;
        evidence.status="PASS";
        evidence.reason="PHYSICAL_PATH_FOUND";
        evidence.port_path=port_labels(G,portPath);
        evidence.path=compress_blocks(G,portPath);
        evidence.edge_kinds=edgeKinds;
        detail=sprintf('PASS:PHYSICAL_PATH_FOUND blocks=%s',strjoin(cellstr(evidence.path),' -> '));
        return;
    end

    if failure_depends_on_unknown(G,src,dst,via)
        evidence.status="UNKNOWN";
        evidence.reason="PATH_MAY_DEPEND_ON_UNSUPPORTED_COMPONENT_OR_BOUNDARY";
    else
        evidence.status="FAIL";
        evidence.reason="NO_PHYSICAL_PATH";
    end
    detail=char(evidence.status+":"+evidence.reason);
catch ex
    ok=false;
    evidence.status="UNKNOWN";
    evidence.reason="GRAPH_BUILD_OR_QUERY_ERROR";
    evidence.error=string(strtrim(ex.message));
    detail=sprintf('UNKNOWN:GRAPH_BUILD_OR_QUERY_ERROR:%s',strtrim(ex.message));
end
end

function G=build_physical_graph(modelName)
blocks=find_system(modelName,'LookUnderMasks','all','FollowLinks','on','Type','Block');
blockRecords=struct('path',{},'descriptor',{});
nodes=struct('handle',{},'block',{},'descriptor',{},'field',{},'ordinal',{}, ...
    'line',{});
portIndex=containers.Map('KeyType','char','ValueType','double');
blockPorts=containers.Map('KeyType','char','ValueType','any');
scanUnsupported=strings(0,1);

for i=1:numel(blocks)
    b=blocks{i};
    blockRecords(end+1)=struct('path',string(b),'descriptor',descriptor_for(b)); %#ok<AGROW>
    ph=[]; try, ph=get_param(b,'PortHandles'); catch, end
    if isempty(ph), continue; end
    fields=fieldnames(ph);
    for f=1:numel(fields)
        hs=ph.(fields{f});
        for q=1:numel(hs)
            h=hs(q); if isempty(h)||h<=0, continue; end
            pt=''; try, pt=get_param(h,'PortType'); catch, end
            if ~strcmpi(pt,'connection')
                if ~isempty(regexpi(fields{f},'conn|phys|conserv','once'))
                    scanUnsupported(end+1)=string(b)+":UNSUPPORTED_PORT_TYPE("+ ...
                        string(fields{f})+":"+string(pt)+")"; %#ok<AGROW>
                end
                continue;
            end
            lh=-1;
            try, lh=get_param(h,'Line'); catch, end
            n=numel(nodes)+1;
            nodes(n)=struct('handle',double(h),'block',string(b),'descriptor',descriptor_for(b), ...
                'field',string(fields{f}),'ordinal',q,'line',double(lh)); %#ok<AGROW>
            portIndex(handle_key(h))=n;
            if isKey(blockPorts,b), ids=blockPorts(b); else, ids=[]; end
            blockPorts(b)=[ids n];
        end
    end
end

n=numel(nodes); adj=cell(1,n); edgeKind=cell(1,n);
unsupported=unique(scanUnsupported,'stable'); unsupportedNodes=[];
if n==0
    allLines=find_system(modelName,'FindAll','on','Type','line');
    G=finish_graph(nodes,adj,edgeKind,blockRecords,unsupported,unsupportedNodes,numel(allLines),0,0);
    return;
end

% Resolve SPS/Simscape conserving nets from native line families and exact
% PortConnectivity handles. Drawing coordinates are never connectivity.
[lineNets,nativeNetStats]=sat_native_physical_line_nets( ...
    modelName,[nodes.handle]);
physicalLineCount=nativeNetStats.physical_line_count;
junctionEdges=nativeNetStats.native_branch_unions+nativeNetStats.port_connectivity_unions;
totalLineCount=nativeNetStats.total_line_count;
netMap=containers.Map('KeyType','char','ValueType','any');
for i=1:n
    if nodes(i).line<=0, continue; end
    k=handle_key(nodes(i).line); if ~isKey(lineNets,k), continue; end
    nk=sprintf('%d',lineNets(k));
    if isKey(netMap,nk), ids=netMap(nk); else, ids=[]; end
    netMap(nk)=[ids i];
end
nk=keys(netMap);
for i=1:numel(nk)
    [adj,edgeKind]=connect_clique(adj,edgeKind,netMap(nk{i}),'physical_net');
end

% Internal component semantics and generic subsystem boundaries.
componentEdges=0; boundaryEdges=0;
bpKeys=keys(blockPorts);
for i=1:numel(bpKeys)
    b=bpKeys{i}; ids=blockPorts(b);
    bt=getp(b,'BlockType'); mt=getp(b,'MaskType'); rb=getp(b,'ReferenceBlock');
    if strcmpi(bt,'PMIOPort')
        [mapped,reason,parentNode]=map_pmio_boundary(b,ids,portIndex);
        if mapped
            [adj,edgeKind,added]=add_edge(adj,edgeKind,ids(1),parentNode,'subsystem_boundary');
            boundaryEdges=boundaryEdges+double(added);
        else
            unsupported(end+1)=string(b)+":"+string(reason); %#ok<AGROW>
            unsupportedNodes=[unsupportedNodes ids]; %#ok<AGROW>
        end
        continue;
    end
    if numel(ids)<2, continue; end

    genericSubsystem=strcmpi(bt,'SubSystem') && isempty(strtrim(mt)) && isempty(strtrim(rb));
    if genericSubsystem
        % The exterior ports are connected only through PMIO mappings. Never
        % collapse a generic subsystem into one conductive decorative node.
        continue;
    end

    [groups,supported,reason]=component_groups(b,ids,nodes,bt,mt,rb);
    if ~supported
        unsupported(end+1)=string(b)+":"+string(reason); %#ok<AGROW>
        unsupportedNodes=[unsupportedNodes ids]; %#ok<AGROW>
        continue;
    end
    for g=1:numel(groups)
        before=count_edges(adj);
        [adj,edgeKind]=connect_clique(adj,edgeKind,groups{g},'component_internal');
        componentEdges=componentEdges+(count_edges(adj)-before);
    end
end

unsupported=unique(unsupported,'stable'); unsupportedNodes=unique(unsupportedNodes);
signalIgnored=max(0,totalLineCount-physicalLineCount);
G=finish_graph(nodes,adj,edgeKind,blockRecords,unsupported,unsupportedNodes, ...
    signalIgnored,junctionEdges,componentEdges+boundaryEdges);
end

function [groups,supported,reason]=component_groups(block,ids,nodes,bt,mt,rb)
groups={}; supported=true; reason="";
% Classify from the block's own metadata. The full path is intentionally
% excluded: a model/subsystem named "Inverter" must not make every nested
% unknown multi-port component look like a supported inverter.
d=lower(strjoin(string({getp(block,'Name'),bt,mt,rb}),'|'));

% Voltage sensors observe two nodes but do not provide a conducting path.
if contains(d,'voltage measurement') && ~contains(d,'three-phase')
    groups=num2cell(ids); return;
end

L=ids(strcmpi([nodes(ids).field],'LConn'));
R=ids(strcmpi([nodes(ids).field],'RConn'));
isPaired=contains(d,'three-phase vi measurement') || ...
    contains(d,'three-phase series rlc branch') || ...
    contains(d,'three-phase parallel rlc branch') || ...
    contains(d,'three-phase breaker') || contains(d,'current measurement');
if isPaired && ~isempty(L) && numel(L)==numel(R)
    groups=cell(1,numel(L));
    for i=1:numel(L), groups{i}=[L(i) R(i)]; end
    return;
end

if numel(ids)==2
    groups={ids}; return;
end

% The SPS Three-Level Bridge is a documented switching-energy stage.  Admit
% only its exact mask/library identity; do not infer conductivity from a
% user-chosen block name containing "three-level bridge".
isSpsThreeLevelBridge=strcmpi(strtrim(mt),'Three-Level Bridge') && ...
    contains(lower(string(rb)),'spsthreelevelbridgelib/three-level bridge');
knownEnergy=contains(d,'universal bridge') || isSpsThreeLevelBridge || contains(d,'converter') || ...
    contains(d,'inverter') || contains(d,'rectifier') || contains(d,'transformer') || ...
    contains(d,'machine') || contains(d,'motor') || contains(d,'generator') || ...
    contains(d,'voltage source') || contains(d,'current source') || ...
    contains(d,'thyristor') || contains(d,'diode bridge');
knownTerminal=contains(d,'three-phase series rlc load') || ...
    contains(d,'three-phase parallel rlc load') || contains(d,'ground');
if knownEnergy
    groups={ids}; return;
elseif knownTerminal
    % A terminal/load can be reached at any terminal, but is not used to
    % jump between phases and fabricate an upstream/downstream path.
    groups=num2cell(ids); return;
end

% Multi-terminal PMComponent/linked masks without known semantics are not
% collapsed. This deliberately sacrifices recall to avoid false connectivity.
supported=false;
reason="UNSUPPORTED_MULTI_TERMINAL_SEMANTICS";
end

function [ok,reason,parentNode]=map_pmio_boundary(block,ids,portIndex)
ok=false; reason="PMIO_BOUNDARY_UNMAPPED"; parentNode=[];
if numel(ids)~=1, reason="PMIO_PORT_COUNT_NOT_ONE"; return; end
parent=getp(block,'Parent'); if isempty(parent), reason="PMIO_PARENT_MISSING"; return; end
ph=[]; try, ph=get_param(parent,'PortHandles'); catch, end
if isempty(ph), reason="PMIO_PARENT_PORTS_UNREADABLE"; return; end
ordered=[];
for f={'LConn','RConn'}
    if isfield(ph,f{1}), ordered=[ordered ph.(f{1})]; end %#ok<AGROW>
end
pn=str2double(getp(block,'Port'));
if ~isfinite(pn)||pn<1||pn>numel(ordered), reason="PMIO_PORT_NUMBER_OUT_OF_RANGE"; return; end
k=handle_key(ordered(pn));
if ~isKey(portIndex,k), reason="PMIO_PARENT_CONNECTION_PORT_NOT_INDEXED"; return; end
parentNode=portIndex(k); ok=true; reason="";
end

function G=finish_graph(nodes,adj,edgeKind,blocks,unsupported,unsupportedNodes,signalIgnored,junctionEdges,internalEdges)
G=struct('nodes',nodes,'adj',{adj},'edge_kind',{edgeKind},'blocks',blocks, ...
    'unsupported',unsupported,'unsupported_nodes',unsupportedNodes);
G.stats=struct('physical_port_count',numel(nodes),'physical_block_count',numel(unique([nodes.block])), ...
    'ordinary_or_unclassified_lines_ignored',signalIgnored,'physical_junction_edges',junctionEdges, ...
    'component_or_boundary_edges',internalEdges,'unsupported_count',numel(unsupported));
end

function [early,e]=validate_matches(src,srcBlocks,via,viaBlocks,dst,dstBlocks,viaPatterns,e)
early=true;
if isempty(srcBlocks), e.status="FAIL"; e.reason="SOURCE_PATTERN_NOT_FOUND"; return; end
if isempty(src), e.status="UNKNOWN"; e.reason="SOURCE_MATCH_HAS_NO_PHYSICAL_PORT"; return; end
if ~isempty(viaPatterns)
    if isempty(viaBlocks), e.status="FAIL"; e.reason="VIA_PATTERN_NOT_FOUND"; return; end
    if isempty(via), e.status="UNKNOWN"; e.reason="VIA_MATCH_HAS_NO_PHYSICAL_PORT"; return; end
end
if isempty(dstBlocks), e.status="FAIL"; e.reason="TARGET_PATTERN_NOT_FOUND"; return; end
if isempty(dst), e.status="UNKNOWN"; e.reason="TARGET_MATCH_HAS_NO_PHYSICAL_PORT"; return; end
early=false;
end

function [ids,matchedBlocks]=match_ports(G,patterns)
ids=[]; matchedBlocks=strings(0,1);
if isempty(patterns), return; end
for i=1:numel(G.blocks)
    if matches_any(G.blocks(i).descriptor,patterns)
        matchedBlocks(end+1)=G.blocks(i).path; %#ok<AGROW>
    end
end
matchedBlocks=unique(matchedBlocks,'stable');
for i=1:numel(G.nodes)
    if matches_any(G.nodes(i).descriptor,patterns), ids(end+1)=i; end %#ok<AGROW>
end
ids=unique(ids);
end

function tf=matches_any(descriptor,patterns)
tf=false;
for i=1:numel(patterns)
    if ~isempty(regexpi(char(descriptor),patterns{i},'once')), tf=true; return; end
end
end

function tf=failure_depends_on_unknown(G,src,dst,via)
if isempty(G.unsupported_nodes), tf=false; return; end
reachSrc=reachable(G,src); reachDst=reachable(G,dst);
tf=any(reachSrc(G.unsupported_nodes)) || any(reachDst(G.unsupported_nodes));
if ~isempty(via), reachVia=reachable(G,via); tf=tf||any(reachVia(G.unsupported_nodes)); end
end

function seen=reachable(G,starts)
seen=false(1,numel(G.nodes)); q=unique(starts(:)');
while ~isempty(q)
    x=q(1); q(1)=[];
    if x<1||x>numel(seen)||seen(x), continue; end
    seen(x)=true; q=[q G.adj{x}]; %#ok<AGROW>
end
end

function [found,path,kinds]=shortest_path(G,starts,goals,excluded)
found=false; path=[]; kinds=strings(0,1);
if nargin<4, excluded=[]; end
starts=unique(starts(:)'); goals=unique(goals(:)'); n=numel(G.nodes);
excluded=unique(excluded(:)');
starts=setdiff(starts,excluded); goals=setdiff(goals,excluded);
if isempty(starts)||isempty(goals), return; end
seen=false(1,n); seen(excluded)=true; prev=zeros(1,n); prevKind=strings(1,n); q=starts;
seen(starts)=true; hit=0;
while ~isempty(q)
    x=q(1); q(1)=[];
    if any(goals==x), hit=x; break; end
    for j=1:numel(G.adj{x})
        y=G.adj{x}(j); if seen(y), continue; end
        seen(y)=true; prev(y)=x; prevKind(y)=string(G.edge_kind{x}{j}); q(end+1)=y; %#ok<AGROW>
    end
end
if hit==0, return; end
path=hit;
while prev(path(1))~=0, path=[prev(path(1)) path]; end %#ok<AGROW>
for i=2:numel(path), kinds(end+1,1)=prevKind(path(i)); end %#ok<AGROW>
found=true;
end

function labels=port_labels(G,path)
labels=strings(numel(path),1);
for i=1:numel(path)
    n=G.nodes(path(i));
    labels(i)=n.block+"["+n.field+"#"+string(n.ordinal)+"]";
end
end

function blocks=compress_blocks(G,path)
blocks=strings(0,1);
for i=1:numel(path)
    b=G.nodes(path(i)).block;
    if isempty(blocks)||blocks(end)~=b, blocks(end+1,1)=b; end %#ok<AGROW>
end
end

function [adj,kinds]=connect_clique(adj,kinds,ids,kind)
ids=unique(ids);
for i=1:numel(ids), for j=i+1:numel(ids), [adj,kinds]=add_edge(adj,kinds,ids(i),ids(j),kind); end, end
end

function [adj,kinds,added]=add_edge(adj,kinds,a,b,kind)
added=false; if isempty(a)||isempty(b)||a==b, return; end
if any(adj{a}==b), return; end
adj{a}(end+1)=b; kinds{a}{end+1}=kind;
adj{b}(end+1)=a; kinds{b}{end+1}=kind; added=true;
end

function n=count_edges(adj)
n=sum(cellfun(@numel,adj))/2;
end

function d=descriptor_for(block)
full=string(block); slash=strfind(char(full),'/'); rel=full; if ~isempty(slash),rel=extractAfter(full,slash(1));end
% Exclude the root model name from match text. Otherwise a model named
% "...Grid" would make every nested block match a generic "grid" target.
d=lower(strjoin(string({rel,getp(block,'Name'),getp(block,'BlockType'), ...
    getp(block,'MaskType'),getp(block,'ReferenceBlock')}),'|'));
end

function v=getp(block,param)
v=''; try, v=get_param(block,param); catch, end
if isnumeric(v), v=num2str(v); end
end

function k=handle_key(h)
k=sprintf('%.15g',double(h));
end

function p=normalise_patterns(x)
if nargin==0||isempty(x), p={}; return; end
if iscell(x), p=cellfun(@(z) char(string(z)),x,'UniformOutput',false);
else, p=cellstr(string(x)); end
p=p(~cellfun(@isempty,p));
end

function e=empty_evidence()
e=struct('status',"UNKNOWN",'reason',"",'path',strings(0,1), ...
    'port_path',strings(0,1),'edge_kinds',strings(0,1), ...
    'source_matches',strings(0,1),'via_matches',strings(0,1), ...
    'target_matches',strings(0,1),'unsupported',strings(0,1), ...
    'via_is_cut',false,'stats',struct(),'error',"");
end
