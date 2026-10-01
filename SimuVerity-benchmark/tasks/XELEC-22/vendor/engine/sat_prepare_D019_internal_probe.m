function state=sat_prepare_D019_internal_probe(modelName,checkSpec) %#ok<INUSD>
%SAT_PREPARE_D019_INTERNAL_PROBE Attach logging to a unique aggregate,
% pre-filter internal voltage measurement. It never falls back to Vout.

state=struct('task',"D019",'scenario',"nominal",'model',string(modelName), ...
    'prepared',true,'valid',false,'detail',"UNINITIALIZED",'evidence',struct(), ...
    'probe_handles',[],'probe_signals',struct());
if isempty(modelName)||~bdIsLoaded(modelName)
    state.detail="MODEL_NOT_LOADED"; return;
end
allBlocks=find_system(modelName,'LookUnderMasks','all','FollowLinks','off','Type','Block');
candidates=struct('block',{},'out',{},'switch_count',{},'public_sink',{});
minLevels=getnum(checkSpec,'min_effective_levels',3);
minSwitchNeighbors=max(2,2*(minLevels-1));
for i=1:numel(allBlocks)
    b=allBlocks{i}; mt=""; try,mt=lower(string(get_param(b,'MaskType')));catch,end
    if ~contains(mt,"voltage measurement"), continue; end
    ph=get_param(b,'PortHandles'); if ~isfield(ph,'Outport')||isempty(ph.Outport), continue; end
    public=reaches_public_workspace(ph.Outport(1),16);
    nsw=terminal_switch_neighbors(b);
    if ~public&&nsw>=minSwitchNeighbors
        candidates(end+1)=struct('block',string(b),'out',ph.Outport(1), ...
            'switch_count',nsw,'public_sink',false); %#ok<AGROW>
    end
end
if isempty(candidates)
    state.detail="AMBIGUOUS_OR_NON_AGGREGATE_PROBE:NO_CANDIDATE"; return;
end
counts=[candidates.switch_count]; best=max(counts); ix=find(counts==best);
if numel(ix)~=1
    state.detail="AMBIGUOUS_OR_NON_AGGREGATE_PROBE:NONUNIQUE"; return;
end
c=candidates(ix);
probeName='__p4_D019_internal_probe'; varName='p4_D019_internal_probe';
probePath=[char(modelName) '/' probeName];
if getSimulinkBlockHandle(probePath)>0
    state.detail="PROBE_NAME_COLLISION"; return;
end
try
    add_block('simulink/Sinks/To Workspace',probePath,'VariableName',varName, ...
        'SaveFormat','Timeseries','MaxDataPoints','1e7','Position',[30 30 180 60]);
    ph=get_param(probePath,'PortHandles');
    lh=add_line(modelName,c.out,ph.Inport(1),'autorouting','on');
catch e
    if getSimulinkBlockHandle(probePath)>0, try,delete_block(probePath);catch,end,end
    state.detail="PROBE_ATTACH_FAIL:"+string(strtrim(e.message)); return;
end
state.valid=true; state.detail="OK";
state.probe_handles=[get_param(probePath,'Handle') lh];
state.probe_signals=struct('variable_name',string(varName));
state.evidence=struct('aggregate_node_valid',true,'signal_role',"aggregate_pre_filter", ...
    'measurement_block',c.block,'probe_block',string(probePath), ...
    'probe_variable',string(varName),'switch_neighbor_count',best, ...
    'min_switch_neighbor_count',minSwitchNeighbors, ...
    'public_sink_reachable',false,'reused_internal_measurement',true);
end

function n=terminal_switch_neighbors(block)
n=0; pc=get_param(block,'PortConnectivity'); seen=[];
for i=1:numel(pc)
    typ=string(pc(i).Type); if ~startsWith(typ,"LConn")&&~startsWith(typ,"RConn"),continue;end
    h=[pc(i).SrcBlock(:);pc(i).DstBlock(:)];
    for k=1:numel(h)
        if h(k)<=0||any(seen==h(k)),continue;end; seen(end+1)=h(k); %#ok<AGROW>
        b=getfullname(h(k)); d=block_descriptor(b);
        if contains(d,"mosfet")||contains(d,"igbt")||contains(d,"thyristor")|| ...
                contains(d,"gto")||contains(d,"switch"), n=n+1; end
    end
end
end

function yes=reaches_public_workspace(outPort,maxDepth)
yes=false; frontier=outPort; visited=[];
for depth=1:maxDepth
    next=[];
    for p=frontier(:)'
        if p<=0||any(visited==p),continue;end;visited(end+1)=p; %#ok<AGROW>
        lh=get_param(p,'Line'); if isempty(lh)||lh<0,continue;end
        dst=get_param(lh,'DstBlockHandle');
        for b=dst(:)'
            if b<=0,continue;end
            bt=string(get_param(b,'BlockType'));
            if bt=="ToWorkspace"
                v=string(get_param(b,'VariableName'));
                if v=="Vout"||startsWith(v,"__v4_out_Vout"),yes=true;return;end
            end
            ph=get_param(b,'PortHandles'); if isfield(ph,'Outport'),next=[next ph.Outport(:)'];end %#ok<AGROW>
        end
    end
    frontier=next; if isempty(frontier),break;end
end
end

function d=block_descriptor(b)
parts=string(b);
for f={'BlockType','MaskType','ReferenceBlock'}
    try,parts(end+1)=string(get_param(b,f{1}));catch,end %#ok<AGROW>
end
d=lower(strjoin(parts," "));
end
function v=getnum(s,f,d)
v=d;if isstruct(s)&&isfield(s,f)&&isnumeric(s.(f))&&isscalar(s.(f))&&isfinite(s.(f)),v=double(s.(f));end
end
