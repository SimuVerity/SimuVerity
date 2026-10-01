function [ok, detail] = sat_signal_path(modelName, sourcePatterns, viaPatterns, targetPatterns)
%SAT_SIGNAL_PATH Verify a directed Simulink signal path source -> via -> target.
% Adds subsystem-boundary and Goto/From edges to ordinary signal lines.

sourcePatterns=cellstr(string(sourcePatterns)); viaPatterns=cellstr(string(viaPatterns)); targetPatterns=cellstr(string(targetPatterns));
[nodes,adj]=build_graph(modelName); ok=false; detail='';
if isempty(nodes), detail='EMPTY_GRAPH'; return; end
src=find_matches(nodes,sourcePatterns); via=find_matches(nodes,viaPatterns); dst=find_matches(nodes,targetPatterns);
if isempty(src), detail='SOURCE_PATTERN_NOT_FOUND'; return; end
if isempty(via), detail='VIA_PATTERN_NOT_FOUND'; return; end
if isempty(dst), detail='TARGET_PATTERN_NOT_FOUND'; return; end

for v=via(:)'
    if any_reaches(src,v,adj) && any_reaches(v,dst,adj)
        ok=true; detail=sprintf('path_through=%s',nodes(v).path); return;
    end
end
detail=sprintf('NO_DIRECTED_PATH source=%d via=%d target=%d',numel(src),numel(via),numel(dst));
end

function [nodes,adj]=build_graph(modelName)
blks=find_system(modelName,'LookUnderMasks','on','FollowLinks','on','Type','Block'); n=numel(blks);
nodes=struct('path',{},'descriptor',{}); index=containers.Map('KeyType','char','ValueType','double');
for i=1:n
    p=blks{i}; bt=getp(p,'BlockType'); mt=getp(p,'MaskType'); rb=getp(p,'ReferenceBlock'); nm=getp(p,'Name');
    nodes(i)=struct('path',string(p),'descriptor',lower(strjoin(string({p,nm,bt,mt,rb}),'|'))); %#ok<AGROW>
    index(p)=i;
end
adj=cell(1,n);
lines=find_system(modelName,'FindAll','on','Type','line');
for i=1:numel(lines)
    try, sh=get_param(lines(i),'SrcBlockHandle'); dh=get_param(lines(i),'DstBlockHandle'); catch, continue; end
    if isempty(sh)||sh<0, continue; end
    try, sp=getfullname(sh); catch, continue; end
    if ~isKey(index,sp), continue; end; si=index(sp);
    for q=1:numel(dh)
        if dh(q)<0, continue; end
        try, dp=getfullname(dh(q)); catch, continue; end
        if isKey(index,dp), adj{si}(end+1)=index(dp); end %#ok<AGROW>
    end
end

% Goto -> matching From.
gotos=find_system(modelName,'LookUnderMasks','on','FollowLinks','on','BlockType','Goto');
froms=find_system(modelName,'LookUnderMasks','on','FollowLinks','on','BlockType','From');
for i=1:numel(gotos)
    tag=getp(gotos{i},'GotoTag'); if ~isKey(index,gotos{i}), continue; end; gi=index(gotos{i});
    for q=1:numel(froms), if strcmp(getp(froms{q},'GotoTag'),tag)&&isKey(index,froms{q}), adj{gi}(end+1)=index(froms{q}); end, end %#ok<AGROW>
end

% Parent subsystem block <-> internal port blocks.
subs=find_system(modelName,'LookUnderMasks','on','FollowLinks','on','BlockType','SubSystem');
for i=1:numel(subs)
    if ~isKey(index,subs{i}), continue; end; si=index(subs{i});
    ins=find_system(subs{i},'SearchDepth',1,'LookUnderMasks','on','FollowLinks','on','BlockType','Inport');
    outs=find_system(subs{i},'SearchDepth',1,'LookUnderMasks','on','FollowLinks','on','BlockType','Outport');
    for q=1:numel(ins), if isKey(index,ins{q}), adj{si}(end+1)=index(ins{q}); end, end %#ok<AGROW>
    for q=1:numel(outs), if isKey(index,outs{q}), adj{index(outs{q})}(end+1)=si; end, end %#ok<AGROW>
end
for i=1:n, if ~isempty(adj{i}), adj{i}=unique(adj{i}); end, end
end

function idx=find_matches(nodes,patterns)
idx=[];
for i=1:numel(nodes)
    d=nodes(i).descriptor; hit=false;
    for q=1:numel(patterns), if ~isempty(regexpi(d,patterns{q},'once')), hit=true; break; end, end
    if hit, idx(end+1)=i; end %#ok<AGROW>
end
end

function tf=any_reaches(starts,goals,adj)
if isscalar(goals), goals=[goals]; end
tf=false; seen=false(1,numel(adj)); queue=starts(:)';
while ~isempty(queue)
    x=queue(1); queue(1)=[]; if x<1||x>numel(adj)||seen(x), continue; end; seen(x)=true;
    if any(goals==x), tf=true; return; end
    queue=[queue adj{x}]; %#ok<AGROW>
end
end

function v=getp(block,param)
v=''; try, v=get_param(block,param); catch, end
if isnumeric(v), v=num2str(v); end
end
