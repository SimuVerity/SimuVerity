function trace = sat_trace_upstream(modelName, sinkBlock, sinkPort, maxDepth)
%SAT_TRACE_UPSTREAM Best-effort upstream signal provenance for the public contracts.
% Traverses ordinary signal lines, subsystem boundaries, and Goto/From routing.
% It deliberately stops at physical measurement blocks so a legitimate sensor
% is not rejected merely because the measured electrical network contains sources.

if nargin<3||isempty(sinkPort), sinkPort=1; end
if nargin<4||isempty(maxDepth), maxDepth=24; end
trace=struct('path',{},'name',{},'block_type',{},'mask_type',{}, ...
    'reference_block',{},'trusted_semantic',{},'depth',{},'descriptor',{});

if getSimulinkBlockHandle(sinkBlock)<0, return; end
ph=get_param(sinkBlock,'PortHandles');
if isempty(ph.Inport)||numel(ph.Inport)<sinkPort, return; end
src=source_from_inport(ph.Inport(sinkPort));
if src<0, return; end

queue={struct('port',src,'depth',0)}; seen=containers.Map('KeyType','char','ValueType','logical');
while ~isempty(queue)
    item=queue{1}; queue(1)=[]; %#ok<AGROW>
    if item.depth>maxDepth||item.port<0, continue; end
    try, blk=get_param(item.port,'Parent'); catch, continue; end
    if isempty(blk)||~startsWith(string(blk),string(modelName)), continue; end
    key=sprintf('%s|%g',blk,item.port); if isKey(seen,key), continue; end; seen(key)=true;

    bt=getp(blk,'BlockType'); mt=getp(blk,'MaskType'); rb=getp(blk,'ReferenceBlock'); nm=getp(blk,'Name');
    desc=lower(strjoin(string({nm,bt,mt,rb}),'|'));
    semantic=sat_provenance_semantic(blk);
    trace(end+1)=struct('path',string(blk),'name',string(nm),'block_type',string(bt), ...
        'mask_type',string(mt),'reference_block',string(rb), ...
        'trusted_semantic',string(semantic.semantic),'depth',item.depth, ...
        'descriptor',desc); %#ok<AGROW>

    if semantic.trusted&&semantic.kind=="measurement", continue; end

    nextPorts=[];
    if semantic.trusted&&semantic.kind=="converter"
        sp=source_from_physical_input(blk);
        if sp>=0,nextPorts(end+1)=sp;end %#ok<AGROW>
    elseif strcmp(bt,'From')
        tag=getp(blk,'GotoTag');
        gotos=find_system(modelName,'LookUnderMasks','on','FollowLinks','on','BlockType','Goto','GotoTag',tag);
        for g=1:numel(gotos), gp=get_param(gotos{g},'PortHandles'); if ~isempty(gp.Inport), sp=source_from_inport(gp.Inport(1)); if sp>=0, nextPorts(end+1)=sp; end, end, end %#ok<AGROW>
    elseif strcmp(bt,'Inport')
        sub=get_param(blk,'Parent'); root=get_param(sub,'Parent');
        if ~isempty(root)
            pn=str2double(getp(blk,'Port')); if isnan(pn), pn=1; end
            sph=get_param(sub,'PortHandles');
            if numel(sph.Inport)>=pn, sp=source_from_inport(sph.Inport(pn)); if sp>=0, nextPorts(end+1)=sp; end, end %#ok<AGROW>
        end
    elseif strcmp(bt,'SubSystem')
        outNo=port_number(item.port);
        outs=find_system(blk,'SearchDepth',1,'LookUnderMasks','on','FollowLinks','on','BlockType','Outport');
        for q=1:numel(outs)
            pn=str2double(getp(outs{q},'Port')); if isnan(pn), pn=q; end
            if pn==outNo, oph=get_param(outs{q},'PortHandles'); if ~isempty(oph.Inport), sp=source_from_inport(oph.Inport(1)); if sp>=0, nextPorts(end+1)=sp; end, end, end %#ok<AGROW>
        end
    else
        try
            iph=get_param(blk,'PortHandles');
            for q=1:numel(iph.Inport), sp=source_from_inport(iph.Inport(q)); if sp>=0, nextPorts(end+1)=sp; end, end %#ok<AGROW>
        catch
        end
    end

    for q=1:numel(nextPorts), queue{end+1}=struct('port',nextPorts(q),'depth',item.depth+1); end %#ok<AGROW>
end

function p=source_from_physical_input(block)
p=-1;try,ph=get_param(block,'PortHandles');catch,return;end
ports=[];for f={'LConn','RConn'},if isfield(ph,f{1}),ports=[ports ph.(f{1})(:)'];end,end %#ok<AGROW>
hits=[];
for i=1:numel(ports)
    kind='';try,kind=get_param(ports(i),'ConnectionType');catch,end
    if strcmpi(strtrim(kind),'network_engine_domain.input'),hits(end+1)=ports(i);end %#ok<AGROW>
end
if numel(hits)~=1,return;end
p=source_from_inport(hits(1));
end
end

function p=source_from_inport(inport)
p=-1;
try
    ln=get_param(inport,'Line'); if isempty(ln)||ln<0, return; end
    p=get_param(ln,'SrcPortHandle'); if isempty(p), p=-1; end
catch
    p=-1;
end
end

function n=port_number(portHandle)
n=1;
try, n=double(get_param(portHandle,'PortNumber')); catch, end
end

function v=getp(block,param)
v=''; try, v=get_param(block,param); catch, end
if isnumeric(v), v=num2str(v); end
end
