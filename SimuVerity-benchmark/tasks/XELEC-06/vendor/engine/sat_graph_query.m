function [ok,evidence] = sat_graph_query(G,query)
%SAT_GRAPH_QUERY Deterministic port-aware reachability over graph facts.
% Selectors are string regexes or structs with node_id, block (exact),
% block_regex/descriptor_regex, port_field, and port_ordinal. q.via is an
% ordered selector list; no engineering meaning is inferred from a path.

evidence=empty_evidence();ok=false;
try
    validate_graph(G);validate_query(query);
    network=lower(string(query.network));direction=lower(string(query.direction));
    [adj,kinds]=select_adjacency(G,network,direction);
    src=select_union(G,query.source,network);dst=select_union(G,query.target,network);
    via=ordered_via(query);
    evidence.source_matches=labels(G,src);evidence.target_matches=labels(G,dst);
    if isempty(src),evidence.status="FAIL";evidence.reason="SOURCE_SELECTOR_NOT_FOUND";return;end
    if isempty(dst),evidence.status="FAIL";evidence.reason="TARGET_SELECTOR_NOT_FOUND";return;end
    stages=cell(1,numel(via));
    for i=1:numel(via)
        stages{i}=select_union(G,via{i},network);
        if isempty(stages{i})
            evidence.status="FAIL";evidence.reason="VIA_SELECTOR_NOT_FOUND";
            evidence.via_matches=append_labels(evidence.via_matches,labels(G,stages{i}));return;
        end
        evidence.via_matches=append_labels(evidence.via_matches,labels(G,stages{i}));
    end
    groups=[{src} stages {dst}];portPath=[];edgeKinds=strings(0,1);
    for i=1:numel(groups)-1
        [found,p,k]=shortest_path(adj,kinds,groups{i},groups{i+1});
        if ~found
            if isfield(G,'unsupported')&&~isempty(G.unsupported)
                evidence.status="UNKNOWN";evidence.reason="PATH_MAY_DEPEND_ON_UNSUPPORTED_GRAPH";
                evidence.unsupported=G.unsupported;
            else
                evidence.status="FAIL";evidence.reason="NO_PATH";
            end
            return;
        end
        if isempty(portPath),portPath=p;else,portPath=[portPath p(2:end)];end %#ok<AGROW>
        edgeKinds=[edgeKinds;k]; %#ok<AGROW>
    end
    ok=true;evidence.status="PASS";evidence.reason="PATH_FOUND";
    evidence.port_path=labels(G,portPath);evidence.block_path=compress_blocks(G,portPath);
    evidence.edge_kinds=edgeKinds;evidence.matched_blocks=unique([ ...
        blocks_for(G,src);blocks_for(G,[stages{:}]);blocks_for(G,dst)],'stable');
    if isfield(G,'unsupported'),evidence.unsupported=G.unsupported;end
catch ex
    ok=false;evidence.status="UNKNOWN";evidence.reason="GRAPH_QUERY_ERROR";
    evidence.error=string(strtrim(ex.message));
end
end

function validate_graph(G)
required={'nodes','signal_forward','signal_reverse','physical_undirected'};
assert(isstruct(G)&&isscalar(G)&&all(isfield(G,required)), ...
    'SimuVerity:GraphQuery:GraphSchema','Malformed graph.');
end
function validate_query(q)
required={'network','direction','source','target'};
assert(isstruct(q)&&isscalar(q)&&all(isfield(q,required)), ...
    'SimuVerity:GraphQuery:QuerySchema','Query is missing required fields.');
network=lower(string(q.network));direction=lower(string(q.direction));
assert(any(network==["signal","physical"]),'SimuVerity:GraphQuery:Network','Unknown network.');
assert(any(direction==["forward","reverse","undirected"]), ...
    'SimuVerity:GraphQuery:Direction','Unknown direction.');
if network=="physical",assert(direction=="undirected", ...
        'SimuVerity:GraphQuery:Direction','Physical queries must be undirected.');end
end
function [adj,kinds]=select_adjacency(G,network,direction)
if network=="physical"
    adj=G.physical_undirected;kinds=G.physical_edge_kinds;
elseif direction=="reverse"
    adj=G.signal_reverse;kinds=G.signal_reverse_edge_kinds;
elseif direction=="undirected"
    adj=G.signal_forward;kinds=G.signal_forward_edge_kinds;
    for i=1:numel(adj)
        rev=G.signal_reverse{i};revKinds=G.signal_reverse_edge_kinds{i};
        for q=1:numel(rev),[adj,kinds]=add_edge(adj,kinds,i,rev(q),revKinds{q});end
    end
else
    adj=G.signal_forward;kinds=G.signal_forward_edge_kinds;
end
end
function via=ordered_via(q)
via={};if ~isfield(q,'via')||isempty(q.via),return;end
x=q.via;
if iscell(x),via=x(:)';elseif isstruct(x)&&numel(x)>1,via=num2cell(x(:)'); ...
elseif isstring(x)&&numel(x)>1,via=num2cell(x(:)');else,via={x};end
end
function ids=select_union(G,selectors,network)
if iscell(selectors),items=selectors(:)';elseif isstruct(selectors)&&numel(selectors)>1,items=num2cell(selectors(:)'); ...
else,items={selectors};end
ids=[];for i=1:numel(items),ids=[ids select_one(G,items{i},network)];end %#ok<AGROW>
ids=unique(ids);
end
function ids=select_one(G,s,network)
ids=find(string({G.nodes.network})==network);if isempty(s),ids=[];return;end
if ischar(s)||isstring(s)
    pattern=char(string(s));ids=ids(arrayfun(@(i)~isempty(regexpi( ...
        char(G.nodes(i).descriptor),pattern,'once')),ids));return;
end
assert(isstruct(s)&&isscalar(s),'SimuVerity:GraphQuery:Selector','Selector must be scalar.');
if isfield(s,'node_id')&&~isempty(s.node_id),ids=intersect(ids,double(s.node_id(:)'));end
if isfield(s,'block')&&strlength(string(s.block))>0
    ids=ids(string({G.nodes(ids).block})==string(s.block));
end
if isfield(s,'block_regex')&&strlength(string(s.block_regex))>0
    p=char(string(s.block_regex));ids=ids(arrayfun(@(i)~isempty(regexpi( ...
        char(G.nodes(i).block),p,'once')),ids));
end
if isfield(s,'descriptor_regex')&&strlength(string(s.descriptor_regex))>0
    p=char(string(s.descriptor_regex));ids=ids(arrayfun(@(i)~isempty(regexpi( ...
        char(G.nodes(i).descriptor),p,'once')),ids));
end
if isfield(s,'port_field')&&strlength(string(s.port_field))>0
    ids=ids(strcmpi(string({G.nodes(ids).port_field}),string(s.port_field)));
end
if isfield(s,'port_ordinal')&&~isempty(s.port_ordinal)
    ids=ids(ismember([G.nodes(ids).port_ordinal],double(s.port_ordinal)));
end
end
function [found,path,edgeKinds]=shortest_path(adj,kinds,start,goal)
found=false;path=[];edgeKinds=strings(0,1);n=numel(adj);
start=unique(start(:)');goal=unique(goal(:)');seen=false(1,n);prev=zeros(1,n);prevKind=strings(1,n);
queue=start;seen(start)=true;hit=0;
while ~isempty(queue)
    x=queue(1);queue(1)=[];if any(goal==x),hit=x;break;end
    for j=1:numel(adj{x})
        y=adj{x}(j);if seen(y),continue;end
        seen(y)=true;prev(y)=x;prevKind(y)=string(kinds{x}{j});queue(end+1)=y; %#ok<AGROW>
    end
end
if hit==0,return;end
path=hit;while prev(path(1))~=0,path=[prev(path(1)) path];end %#ok<AGROW>
for i=2:numel(path),edgeKinds(end+1,1)=prevKind(path(i));end %#ok<AGROW>
found=true;
end
function out=labels(G,ids)
out=strings(numel(ids),1);for i=1:numel(ids),n=G.nodes(ids(i)); ...
        out(i)=n.block+"["+n.port_field+"#"+string(n.port_ordinal)+"]";end
end
function out=blocks_for(G,ids)
if isempty(ids),out=strings(0,1);else,out=unique([G.nodes(ids).block]','stable');end
end
function out=compress_blocks(G,ids)
out=strings(0,1);for i=ids(:)',b=G.nodes(i).block;if isempty(out)||out(end)~=b,out(end+1,1)=b;end,end %#ok<AGROW>
end
function out=append_labels(out,more),out=unique([out(:);more(:)],'stable');end
function [adj,kinds]=add_edge(adj,kinds,a,b,kind)
if any(adj{a}==b),return;end;adj{a}(end+1)=b;kinds{a}{end+1}=char(kind);
end
function e=empty_evidence()
e=struct('status',"UNKNOWN",'reason',"",'source_matches',strings(0,1), ...
    'via_matches',strings(0,1),'target_matches',strings(0,1), ...
    'matched_blocks',strings(0,1),'port_path',strings(0,1), ...
    'block_path',strings(0,1),'edge_kinds',strings(0,1), ...
    'unsupported',struct([]),'error',"");
end
