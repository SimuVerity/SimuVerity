function [origins,ok,detail] = sat_channel_origins(modelName,sinkBlock,sinkPort,expectedChannels,maxDepth)
%SAT_CHANNEL_ORIGINS Trace channel-sensitive logical/physical origins.
% Origins survive transparent Gain/Delay/subsystem wrappers and preserve
% Mux/Demux channel selection, so duplicated sensors cannot be hidden by
% adding signal-processing blocks in front of the contract sink.

if nargin<3||isempty(sinkPort),sinkPort=1;end
if nargin<4||isempty(expectedChannels),expectedChannels=1;end
if nargin<5||isempty(maxDepth),maxDepth=32;end
origins=strings(1,0);ok=false;detail="";
try
    ph=get_param(sinkBlock,'PortHandles');
    if numel(ph.Inport)<sinkPort,detail="SINK_PORT_MISSING";return;end
    src=source_from_inport(ph.Inport(sinkPort));
    if src<0,detail="SINK_SOURCE_MISSING";return;end
    [origins,ok,detail]=trace_source(modelName,src,double(expectedChannels),0,double(maxDepth),strings(0,1));
    if ok&&(numel(origins)~=expectedChannels||any(strlength(origins)==0))
        ok=false;detail=sprintf('ORIGIN_COUNT_%d_NE_%d',numel(origins),expectedChannels);
    end
catch e
    origins=strings(1,0);ok=false;detail="ORIGIN_TRACE_ERROR:"+string(strtrim(e.message));
end
end

function [origins,ok,detail]=trace_source(modelName,src,expected,depth,maxDepth,seen)
origins=strings(1,0);ok=false;detail="";
if src<0||depth>maxDepth,detail="ORIGIN_DEPTH_OR_PORT";return;end
blk=string(get_param(src,'Parent'));outNo=port_number(src);key=blk+"#"+outNo+"#"+expected;
if any(seen==key),detail="ORIGIN_CYCLE:"+key;return;end
seen(end+1)=key;bt=string(getp(blk,'BlockType'));
semantic=sat_provenance_semantic(char(blk));

if semantic.trusted&&semantic.kind=="measurement"
    origins=terminal_origins(blk,outNo,expected);ok=true;detail="TERMINAL:"+blk;return;
end
if semantic.trusted&&semantic.kind=="converter"
    up=source_from_physical_input(char(blk));
    if up<0,detail="CONVERTER_INPUT_UNRESOLVED:"+blk;return;end
    [origins,ok,detail]=trace_source(modelName,up,expected,depth+1,maxDepth,seen);return;
end
if is_source_terminal(blk)
    origins=terminal_origins(blk,outNo,expected);ok=true;detail="TERMINAL:"+blk;return;
end

switch char(bt)
    case 'From'
        tag=getp(blk,'GotoTag');gotos=find_system(modelName,'LookUnderMasks','on','FollowLinks','on','BlockType','Goto','GotoTag',tag);
        if numel(gotos)~=1,detail=sprintf('FROM_GOTO_COUNT_%d:%s',numel(gotos),tag);return;end
        gp=get_param(gotos{1},'PortHandles');up=source_from_inport(gp.Inport(1));
        [origins,ok,detail]=trace_source(modelName,up,expected,depth+1,maxDepth,seen);return;
    case 'SubSystem'
        outs=find_system(char(blk),'SearchDepth',1,'LookUnderMasks','on','FollowLinks','on','BlockType','Outport');hit={};
        for i=1:numel(outs),pn=str2double(getp(outs{i},'Port'));if isnan(pn),pn=i;end;if pn==outNo,hit{end+1}=outs{i};end,end %#ok<AGROW>
        if numel(hit)~=1,detail=sprintf('SUBSYSTEM_OUTPORT_COUNT_%d',numel(hit));return;end
        hp=get_param(hit{1},'PortHandles');up=source_from_inport(hp.Inport(1));
        [origins,ok,detail]=trace_source(modelName,up,expected,depth+1,maxDepth,seen);return;
    case 'Inport'
        sub=string(get_param(blk,'Parent'));pn=str2double(getp(blk,'Port'));if isnan(pn),pn=1;end
        if sub==string(modelName),origins=terminal_origins(blk,1,expected);ok=true;detail="ROOT_INPORT";return;end
        sph=get_param(sub,'PortHandles');if numel(sph.Inport)<pn,detail="SUBSYSTEM_INPORT_MISSING";return;end
        up=source_from_inport(sph.Inport(pn));[origins,ok,detail]=trace_source(modelName,up,expected,depth+1,maxDepth,seen);return;
    case {'Mux','BusCreator','VectorConcatenate'}
        ph=get_param(blk,'PortHandles');n=numel(ph.Inport);
        if n~=expected,detail=sprintf('MUX_INPUT_COUNT_%d_NE_EXPECTED_%d',n,expected);return;end
        parts=strings(1,0);
        for i=1:n
            up=source_from_inport(ph.Inport(i));[part,partOk,partDetail]=trace_source(modelName,up,1,depth+1,maxDepth,seen);
            if ~partOk,detail="MUX_INPUT_"+i+":"+partDetail;return;end
            parts=[parts part]; %#ok<AGROW>
        end
        origins=parts;ok=numel(origins)==expected;detail="MUX";return;
    case 'Demux'
        ph=get_param(blk,'PortHandles');n=numel(ph.Outport);widths=demux_widths(blk,n,expected);
        if isempty(widths)||numel(widths)~=n||widths(outNo)~=expected,detail="DEMUX_WIDTH_UNRESOLVED";return;end
        up=source_from_inport(ph.Inport(1));[allOrigins,allOk,allDetail]=trace_source(modelName,up,sum(widths),depth+1,maxDepth,seen);
        if ~allOk,detail="DEMUX_INPUT:"+allDetail;return;end
        first=1+sum(widths(1:outNo-1));origins=allOrigins(first:first+expected-1);ok=true;detail="DEMUX";return;
    case 'Selector'
        [indices,indexOk]=selector_indices(blk,expected);
        if ~indexOk,detail="SELECTOR_INDICES_UNRESOLVED";return;end
        ph=get_param(blk,'PortHandles');up=source_from_inport(ph.Inport(1));[allOrigins,allOk,allDetail]=trace_source(modelName,up,max(indices),depth+1,maxDepth,seen);
        if ~allOk,detail="SELECTOR_INPUT:"+allDetail;return;end
        origins=allOrigins(indices);ok=numel(origins)==expected;detail="SELECTOR";return;
    case 'BusSelector'
        % A Bus Selector may expose several distinct physical measurement
        % elements through one upstream measurement-bus port.  Preserve the
        % selected element label in the origin identity; otherwise ias/ibs/ics
        % from one official machine boundary collapse to the same channel.
        if expected~=1,detail="BUS_SELECTOR_VECTOR_WIDTH_UNSUPPORTED";return;end
        labels=strip(split(string(getp(blk,'OutputSignals')),','));
        if outNo<1||outNo>numel(labels)||strlength(labels(outNo))==0
            detail="BUS_SELECTOR_LABEL_UNRESOLVED";return;
        end
        ph=get_param(blk,'PortHandles');
        if numel(ph.Inport)~=1,detail="BUS_SELECTOR_INPUT_UNRESOLVED";return;end
        up=source_from_inport(ph.Inport(1));
        [base,baseOk,baseDetail]=trace_source(modelName,up,1,depth+1,maxDepth,seen);
        if ~baseOk||numel(base)~=1,detail="BUS_SELECTOR_INPUT:"+baseDetail;return;end
        label=lower(regexprep(strtrim(labels(outNo)),'\s+',''));
        origins=base+"#bus:"+label;ok=true;detail="BUS_SELECTOR:"+label;return;
end

ph=get_param(blk,'PortHandles');
if numel(ph.Inport)==1
    up=source_from_inport(ph.Inport(1));[origins,ok,detail]=trace_source(modelName,up,expected,depth+1,maxDepth,seen);return;
elseif numel(ph.Inport)==expected
    parts=strings(1,0);
    for i=1:numel(ph.Inport)
        up=source_from_inport(ph.Inport(i));[part,partOk,partDetail]=trace_source(modelName,up,1,depth+1,maxDepth,seen);
        if ~partOk,detail="MULTI_INPUT_"+i+":"+partDetail;return;end
        parts=[parts part]; %#ok<AGROW>
    end
    origins=parts;ok=true;detail="MULTI_INPUT";return;
end
detail="UNSUPPORTED_CHANNEL_BLOCK:"+bt+":"+blk;
end

function widths=demux_widths(blk,n,expected)
widths=[];raw=getp(blk,'Outputs');v=str2num(raw); %#ok<ST2NM>
if numel(v)==n,widths=double(v(:)');elseif isscalar(v)&&v==n,widths=repmat(double(expected),1,n);end
end

function [indices,ok]=selector_indices(blk,expected)
indices=[];ok=false;raw=getp(blk,'Indices');if isempty(raw),return;end
v=str2num(raw); %#ok<ST2NM>
if isempty(v),return;end;v=double(v(:)');if numel(v)~=expected||any(v<1)||any(mod(v,1)~=0),return;end
indices=v;ok=true;
end

function origins=terminal_origins(blk,outNo,width)
origins=strings(1,width);for i=1:width,origins(i)=string(blk)+"#out"+outNo+"#ch"+i;end
end

function tf=is_source_terminal(blk)
ph=get_param(blk,'PortHandles');hasPhysical= ...
    (isfield(ph,'LConn')&&~isempty(ph.LConn))||(isfield(ph,'RConn')&&~isempty(ph.RConn));
tf=isempty(ph.Inport)&&~hasPhysical&&isfield(ph,'Outport')&&~isempty(ph.Outport);
end

function p=source_from_physical_input(block)
p=-1;try,ph=get_param(block,'PortHandles');catch,return;end
ports=[];for f={'LConn','RConn'},if isfield(ph,f{1}),ports=[ports ph.(f{1})(:)'];end,end %#ok<AGROW>
hits=[];
for i=1:numel(ports)
    kind='';try,kind=get_param(ports(i),'ConnectionType');catch,end
    if strcmpi(strtrim(kind),'network_engine_domain.input'),hits(end+1)=ports(i);end %#ok<AGROW>
end
if numel(hits)==1,p=source_from_inport(hits(1));end
end

function p=source_from_inport(inport)
p=-1;try,ln=get_param(inport,'Line');if isempty(ln)||ln<0,return;end;p=get_param(ln,'SrcPortHandle');if isempty(p),p=-1;end,catch,p=-1;end
end
function n=port_number(port),n=1;try,n=double(get_param(port,'PortNumber'));catch,end,end
function v=getp(block,param),v='';try,v=get_param(block,param);catch,end;if isnumeric(v),v=num2str(v);end,end
