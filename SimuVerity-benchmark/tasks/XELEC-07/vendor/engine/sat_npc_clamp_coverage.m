function proof=sat_npc_clamp_coverage(taps,legs,directedEdges,rails,switchEdges)
%SAT_NPC_CLAMP_COVERAGE Directional, series-chain-tolerant NPC proof.
% directedEdges(:,1) is diode anode net and directedEdges(:,2) is cathode.
% A valid cell needs both tap->leg and leg->tap directed reachability. Paths
% may contain multiple series diodes.  Each DC tap must terminate at a
% distinct internal switching junction in a phase leg, rejecting the common
% false-positive topology where all taps form a diode star at one node.

if nargin<5,switchEdges=zeros(0,2);end
taps=double(taps(:)');rails=double(rails(:)');directedEdges=double(directedEdges);
if isempty(directedEdges),n=max([taps rails 1]);else,n=max([taps rails directedEdges(:)']);end
forward=cell(1,n);reverse=cell(1,n);
for i=1:size(directedEdges,1)
    a=directedEdges(i,1);k=directedEdges(i,2);
    if a<=0||k<=0||a==k,continue;end
    forward{a}(end+1)=k;reverse{k}(end+1)=a; %#ok<AGROW>
end
for i=1:n,forward{i}=unique(forward{i},'stable');reverse{i}=unique(reverse{i},'stable');end
nt=numel(taps);nl=numel(legs);outHits=cell(nt,nl);inHits=cell(nt,nl);
outPaths=cell(nt,nl);inPaths=cell(nt,nl);complete=nt>0&&nl>0;
allLegNets=[];for l=1:nl,legs{l}=double(legs{l}(:)');allLegNets=unique([allLegNets legs{l}],'stable');end
for t=1:nt
    for l=1:nl
        forbidden=unique([rails taps([1:t-1 t+1:end]) setdiff(allLegNets,legs{l})],'stable');
        [outHits{t,l},outPaths{t,l}]=first_hits(forward,taps(t),legs{l},forbidden);
        [inHits{t,l},inPaths{t,l}]=first_hits(reverse,taps(t),legs{l},forbidden);
        complete=complete&&~isempty(outHits{t,l})&&~isempty(inHits{t,l});
    end
end
distinct=true(nt,nl);attachments=cell(nt,nl);
for l=1:nl
    for t=1:nt,attachments{t,l}=unique([outHits{t,l} inHits{t,l}],'stable');end
    for a=1:nt,for b=a+1:nt
        if ~isempty(intersect(attachments{a,l},attachments{b,l}))
            distinct(a,l)=false;distinct(b,l)=false;
        end
    end,end
end
[potentialOk,depthEvidence]=potential_order(taps,legs,outHits,inHits,rails,switchEdges);
proof=struct('forward_hits',{outHits},'reverse_hits',{inHits}, ...
    'forward_paths',{outPaths},'reverse_paths',{inPaths}, ...
    'attachments',{attachments},'directional_complete',logical(complete), ...
    'distinct_attachment_mask',distinct,'no_shared_tap_star',logical(all(distinct(:))), ...
    'potential_order_consistent',logical(potentialOk),'potential_depths',depthEvidence);
end

function [ok,evidence]=potential_order(taps,legs,outHits,inHits,rails,edges)
nt=numel(taps);nl=numel(legs);outDepths=cell(nt,nl);inDepths=cell(nt,nl);
ok=nt>0&&nl>0&&numel(rails)==2&&~isempty(edges);
if ~ok,evidence=struct('forward',{outDepths},'reverse',{inDepths});return;end
n=max([rails(:);edges(:);1]);adj=cell(1,n);
for i=1:size(edges,1),a=edges(i,1);b=edges(i,2);adj{a}(end+1)=b;adj{b}(end+1)=a;end
dist=shortest_distances(adj,rails(1));
for l=1:nl
    for t=1:nt
        outDepths{t,l}=dist(outHits{t,l});inDepths{t,l}=dist(inHits{t,l});
        ok=ok&&~isempty(outDepths{t,l})&&~isempty(inDepths{t,l}) ...
            &&all(isfinite(outDepths{t,l}))&&all(isfinite(inDepths{t,l}));
    end
    for t=1:nt-1
        ok=ok&&max(outDepths{t,l})<min(outDepths{t+1,l}) ...
            &&max(inDepths{t,l})<min(inDepths{t+1,l});
    end
end
evidence=struct('forward',{outDepths},'reverse',{inDepths},'reference_rail',rails(1));
end
function dist=shortest_distances(adj,start)
dist=inf(1,numel(adj));dist(start)=0;queue=start;
while ~isempty(queue),x=queue(1);queue(1)=[];
    for y=adj{x}(:)',if dist(y)>dist(x)+1,dist(y)=dist(x)+1;queue(end+1)=y;end,end %#ok<AGROW>
end
end

function [hits,paths]=first_hits(adj,start,targets,forbidden)
hits=[];paths={};n=numel(adj);seen=false(1,n);prev=zeros(1,n);
if start<1||start>n,return;end;seen(start)=true;queue=start;
while ~isempty(queue)
    x=queue(1);queue(1)=[];
    for y=adj{x}(:)'
        if y<1||y>n||seen(y)||any(forbidden==y),continue;end
        seen(y)=true;prev(y)=x;
        if any(targets==y),hits(end+1)=y;paths{end+1}=restore(prev,start,y);continue;end %#ok<AGROW>
        queue(end+1)=y; %#ok<AGROW>
    end
end
hits=unique(hits,'stable');
end
function path=restore(prev,start,hit)
path=hit;while path(1)~=start
    p=prev(path(1));if p==0,path=[];return;end;path=[p path]; %#ok<AGROW>
end
end
