function [lineNets,stats]=simuverity_physical_line_networks(modelName,physicalPortHandles)
%simuverity_physical_line_networks Resolve conserving nets from native facts.
% Geometry is deliberately excluded: coincident/crossing Points do not
% imply connectivity.  Only a port's Line handle, native LineParent /
% LineChildren relationships, and exact PortConnectivity port handles may
% place two line objects in the same physical net.

modelName=char(string(modelName));
physicalPortHandles=unique(double(physicalPortHandles(:)'));
physicalPortHandles=physicalPortHandles(isfinite(physicalPortHandles)&physicalPortHandles>0);
lineNets=containers.Map('KeyType','char','ValueType','double');

allLines=[];
try,allLines=double(find_system(modelName,'FindAll','on','Type','line'));catch,end
allLines=allLines(:)';
physicalPortSet=containers.Map('KeyType','char','ValueType','logical');
physicalLineSet=containers.Map('KeyType','char','ValueType','logical');
unresolvedPorts=0;
for h=physicalPortHandles
    physicalPortSet(handle_key(h))=true;
    lh=-1;try,lh=double(get_param(h,'Line'));catch,end
    if isempty(lh)||~isfinite(lh(1))||lh(1)<=0
        unresolvedPorts=unresolvedPorts+1;
    else
        physicalLineSet(handle_key(lh(1)))=true;
    end
end

rec=struct('handle',{},'parent',{},'physical_seed',{},'signal_seed',{});
for i=1:numel(allLines)
    lh=allLines(i);parent="";sh=[];dh=[];
    try,parent=string(get_param(lh,'Parent'));catch,end
    try,sh=get_param(lh,'SrcPortHandle');dh=get_param(lh,'DstPortHandle');catch,end
    if strlength(parent)==0,continue;end
    hs=double([sh(:);dh(:)]);hasPhysical=false;hasSignal=false;
    for h=hs(:)'
        if ~isfinite(h)||h<=0,continue;end
        portType="";try,portType=string(get_param(h,'PortType'));catch,end
        if strcmpi(portType,"connection"),hasPhysical=true;
        elseif strlength(portType)>0,hasSignal=true;
        end
    end
    isPhysicalSeed=hasPhysical||isKey(physicalLineSet,handle_key(lh));
    connected=true;try,connected=strcmpi(get_param(lh,'Connected'),'on');catch,end
    if ~(connected||isPhysicalSeed||hasSignal),continue;end
    rec(end+1)=struct('handle',lh,'parent',parent, ...
        'physical_seed',isPhysicalSeed,'signal_seed',hasSignal); %#ok<AGROW>
end

if isempty(rec)
    stats=make_stats(numel(allLines),0,0,0,unresolvedPorts,0);
    return;
end

lineIndex=containers.Map('KeyType','char','ValueType','double');
for i=1:numel(rec),lineIndex(handle_key(rec(i).handle))=i;end
uf=1:numel(rec);nativeUnions=0;
for i=1:numel(rec)
    parentHandle=[];children=[];
    try,parentHandle=double(get_param(rec(i).handle,'LineParent'));catch,end
    try,children=double(get_param(rec(i).handle,'LineChildren'));catch,end
    relatives=unique([parentHandle(:);children(:)]);
    for h=relatives(:)'
        if ~isfinite(h)||h<=0,continue;end
        key=handle_key(h);if ~isKey(lineIndex,key),continue;end
        j=lineIndex(key);
        if rec(i).parent~=rec(j).parent,continue;end
        [uf,added]=uf_union(uf,i,j);nativeUnions=nativeUnions+double(added);
    end
end

% Some SPS releases expose a complete physical net directly through the
% block PortConnectivity table even when individual branch fragments have
% no Src/Dst port.  Use only exact remote port handles that are already
% known physical ports; numeric port ordinals and names are never guessed.
pcUnions=0;blocks=strings(0,1);
for h=physicalPortHandles
    try,blocks(end+1)=string(get_param(h,'Parent'));catch,end %#ok<AGROW>
end
blocks=unique(blocks(strlength(blocks)>0),'stable');
for b=blocks(:)'
    ph=[];pc=[];
    try,ph=get_param(char(b),'PortHandles');catch,end
    try,pc=get_param(char(b),'PortConnectivity');catch,end
    if ~isstruct(ph)||~isstruct(pc),continue;end
    for p=1:numel(pc)
        local=local_physical_port(ph,pc(p).Type,physicalPortSet);
        if local<=0,continue;end
        remotes=[];
        if isfield(pc,'SrcPort'),remotes=[remotes;double(pc(p).SrcPort(:))];end %#ok<AGROW>
        if isfield(pc,'DstPort'),remotes=[remotes;double(pc(p).DstPort(:))];end %#ok<AGROW>
        for remote=unique(remotes(:))'
            if ~isfinite(remote)||remote<=0||~isKey(physicalPortSet,handle_key(remote)),continue;end
            a=port_line_index(local,lineIndex);c=port_line_index(remote,lineIndex);
            if a<=0||c<=0||rec(a).parent~=rec(c).parent,continue;end
            [uf,added]=uf_union(uf,a,c);pcUnions=pcUnions+double(added);
        end
    end
end

roots=zeros(1,numel(rec));for i=1:numel(rec),roots(i)=uf_root(uf,i);end
physicalRoots=unique(roots([rec.physical_seed]));
signalRoots=unique(roots([rec.signal_seed]));
contaminated=intersect(physicalRoots,signalRoots);
keep=ismember(roots,setdiff(physicalRoots,signalRoots));
for i=find(keep),lineNets(handle_key(rec(i).handle))=roots(i);end
stats=make_stats(numel(allLines),sum(keep),nativeUnions,pcUnions, ...
    unresolvedPorts,numel(contaminated));
end

function local=local_physical_port(ph,type,physicalPortSet)
local=-1;type=lower(regexprep(char(string(type)),'\s+',''));
if isempty(type),return;end
fields=fieldnames(ph);
for f=1:numel(fields)
    hs=double(ph.(fields{f})(:));
    for q=1:numel(hs)
        labels={lower([fields{f} num2str(q)])};
        if q==1,labels{end+1}=lower(fields{f});end %#ok<AGROW>
        if any(strcmp(type,labels))&&hs(q)>0&&isKey(physicalPortSet,handle_key(hs(q)))
            local=hs(q);return;
        end
    end
end
end

function index=port_line_index(portHandle,lineIndex)
index=-1;lh=-1;try,lh=double(get_param(portHandle,'Line'));catch,end
if isempty(lh)||~isfinite(lh(1))||lh(1)<=0,return;end
key=handle_key(lh(1));if isKey(lineIndex,key),index=lineIndex(key);end
end

function [uf,added]=uf_union(uf,a,b)
ra=uf_root(uf,a);rb=uf_root(uf,b);added=ra~=rb;
if added,uf(rb)=ra;end
end
function r=uf_root(uf,a),r=a;while uf(r)~=r,r=uf(r);end,end
function key=handle_key(handle),key=sprintf('%.15g',double(handle));end
function s=make_stats(total,physical,native,pc,unresolved,contaminated)
s=struct('total_line_count',double(total),'physical_line_count',double(physical), ...
    'native_branch_unions',double(native),'port_connectivity_unions',double(pc), ...
    'unresolved_physical_ports',double(unresolved), ...
    'signal_contaminated_components',double(contaminated));
end
