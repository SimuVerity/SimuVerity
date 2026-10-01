function audit=f90_xmech04_static_audit(modelPath)
%f90_xmech04_static_audit Extract opaque, port-connected mechanism facts.
% No score decision is made here.  Capabilities come from trusted built-in
% types, resolved library links, block parameters, and public log identities;
% candidate display names and canvas positions are never semantic evidence.
arguments
    modelPath (1,1) string
end
assert(isfile(modelPath),'F90_XMECH04_current_MODEL_MISSING');
[~,model]=fileparts(modelPath);model=string(model);
loaded=bdIsLoaded(model);
if ~loaded,load_system(modelPath);end
cleanup=onCleanup(@()local_close(model,loaded)); %#ok<NASGU>
audit=struct( ...
    'schema',"simuverity.f90-xmech04-static-audit.v1", ...
    'port_graph',local_port_graph(model), ...
    'structure_decision_deferred_to_offline_policy',true, ...
    'display_names_used_for_capability_classification',false, ...
    'canvas_coordinates_used',false);
end

function graph=local_port_graph(model)
blocks=string(find_system(model,'LookUnderMasks','all', ...
    'FollowLinks','on','Type','Block'));
blocks=blocks(blocks~=model);
handles=zeros(numel(blocks),1);
nodes=repmat(struct('id',"",'capabilities',strings(0,1), ...
    'capability_provenance',""),numel(blocks),1);
for index=1:numel(blocks)
    handles(index)=double(get_param(blocks(index),'Handle'));
    nodes(index).id="n"+string(index);
    [nodes(index).capabilities,nodes(index).capability_provenance]= ...
        local_capabilities(blocks(index));
end

edges=repmat(struct('from',"",'to',"",'kind',"", ...
    'from_port',"",'to_port',""),0,1);
for index=1:numel(blocks)
    try
        ports=get_param(blocks(index),'PortHandles');
        for port=reshape(ports.Outport,1,[])
            line=get_param(port,'Line');
            if isempty(line)||any(double(line)<0),continue;end
            destinations=double(reshape(get_param(line,'DstPortHandle'),[],1));
            for destinationPort=reshape(destinations,1,[])
                target=find(handles==local_port_owner(destinationPort),1);
                if isempty(target),continue;end
                edges=local_add_edge(edges,index,target,"signal", ...
                    local_port_identity(blocks(index),index,port), ...
                    local_port_identity(blocks(target),target,destinationPort));
            end
        end
    catch
    end
end

lineHandles=find_system(model,'FindAll','on','LookUnderMasks','all', ...
    'FollowLinks','on','Type','line');
for line=reshape(lineHandles,1,[])
    try
        if ~strcmpi(string(get_param(line,'LineType')),'connection'),continue;end
        ports=[double(get_param(line,'SrcPortHandle')); ...
            reshape(double(get_param(line,'DstPortHandle')),[],1)];
        ports=ports(isfinite(ports)&ports>0);
        owners=zeros(0,1);identities=strings(0,1);
        for port=reshape(ports,1,[])
            owner=find(handles==local_port_owner(port),1);
            if isempty(owner),continue;end
            owners(end+1,1)=owner; %#ok<AGROW>
            identities(end+1,1)=local_port_identity( ...
                blocks(owner),owner,port); %#ok<AGROW>
        end
        for left=1:numel(owners)
            for right=left+1:numel(owners)
                edges=local_add_edge(edges,owners(left),owners(right), ...
                    "physical",identities(left),identities(right));
            end
        end
    catch
    end
end

% Explicit hierarchy bridges preserve causal direction without assigning a
% mechanism role to subsystem display names.
for child=1:numel(blocks)
    blockType=lower(local_get(blocks(child),'BlockType'));
    if blockType~="inport"&&blockType~="outport",continue;end
    parent=find(blocks==string(local_get(blocks(child),'Parent')),1);
    if isempty(parent),continue;end
    portNumber=string(local_get(blocks(child),'Port'));
    if blockType=="inport"
        edges=local_add_edge(edges,parent,child,"signal", ...
            "n"+parent+":in"+portNumber, ...
            "n"+child+":hierarchy-in"+portNumber);
    else
        edges=local_add_edge(edges,child,parent,"signal", ...
            "n"+child+":hierarchy-out"+portNumber, ...
            "n"+parent+":out"+portNumber);
    end
end

% Simscape physical-signal converters give connection lines a single causal
% direction.  Conserving physical connections remain undirected evidence.
physicalRows=edges(arrayfun(@(row)string(row.kind)=="physical",edges));
for index=1:numel(physicalRows)
    row=physicalRows(index);
    left=str2double(extractAfter(string(row.from),1));
    right=str2double(extractAfter(string(row.to),1));
    if any(nodes(left).capabilities=="ps_to_simulink_converter")
        edges=local_add_edge(edges,right,left,"signal",row.to_port,row.from_port);
    elseif any(nodes(right).capabilities=="ps_to_simulink_converter")
        edges=local_add_edge(edges,left,right,"signal",row.from_port,row.to_port);
    end
    if any(nodes(left).capabilities=="simulink_to_ps_converter")
        edges=local_add_edge(edges,left,right,"signal",row.from_port,row.to_port);
    elseif any(nodes(right).capabilities=="simulink_to_ps_converter")
        edges=local_add_edge(edges,right,left,"signal",row.to_port,row.from_port);
    end
end
graph=struct( ...
    'schema',"simuverity.f90-xmech04-port-graph.v1", ...
    'node_identity',"opaque_index_not_display_name", ...
    'capability_sources', ...
        "trusted_BlockType_resolved_library_parameters_and_public_interface", ...
    'hierarchy_and_physical_signal_bridges',true, ...
    'nodes',nodes,'edges',edges);
end

function [capabilities,provenance]=local_capabilities(block)
blockType=lower(local_get(block,'BlockType'));
descriptor=local_normalize(strjoin([blockType,local_get(block,'SourceBlock'), ...
    local_get(block,'ReferenceBlock')]," "));
linkStatus=lower(local_get(block,'LinkStatus'));
resolvedLibrary=any(linkStatus==["resolved","implicit"])&& ...
    strlength(strtrim(strjoin([local_get(block,'SourceBlock'), ...
    local_get(block,'ReferenceBlock')],"")))>0;
builtinController=any(blockType==["gain","sum","product","pidcontroller", ...
    "discretepidcontroller","statespace","discretestatespace", ...
    "integrator","discreteintegrator","matlabfunction","lookup_n-d"]);
physical=local_has_physical_ports(block);
capabilities=strings(0,1);provenance="none";

variable="";
if blockType=="toworkspace",variable=string(local_get(block,'VariableName'));end
if blockType=="outport",variable=string(local_get(block,'Name'));end
if any(blockType==["toworkspace","outport"])
    switch variable
        case "joint_state"
            capabilities(end+1,1)="public_joint_state_sink";
        case "joint_torque"
            capabilities(end+1,1)="public_joint_torque_sink";
        case "end_effector_pose"
            capabilities(end+1,1)="public_pose_sink";
    end
    if ~isempty(capabilities),provenance="public_interface_contract";end
end
if any(blockType==["mux","demux","selector","buscreator", ...
        "busselector","goto","from","inport","outport", ...
        "signalconversion","datatypeconversion","subsystem"])
    capabilities(end+1,1)="signal_router";
end
if builtinController
    capabilities(end+1,1)="feedback_controller";
    provenance="trusted_builtin";
end
if blockType=="saturate"||contains(descriptor,"dynamic saturation")|| ...
        (resolvedLibrary&&local_any(descriptor,["saturation","limiter"]))
    capabilities(end+1,1)="torque_limiter";
    if resolvedLibrary,provenance="resolved_library_link";else,provenance="trusted_builtin";end
end
if resolvedLibrary&&local_any(descriptor, ...
        ["ps-simulink converter","ps simulink converter"])
    capabilities(end+1,1)=["ps_to_simulink_converter"];
    capabilities(end+1,1)="signal_router";provenance="resolved_library_link";
end
if resolvedLibrary&&local_any(descriptor, ...
        ["simulink-ps converter","simulink ps converter"])
    capabilities(end+1,1)="simulink_to_ps_converter";
    capabilities(end+1,1)="signal_router";provenance="resolved_library_link";
end
if resolvedLibrary&&physical&&contains(descriptor,"revolute joint")
    capabilities(end+1,1)="revolute_joint";
    if strcmp(local_get(block,'MotionActuationMode'),'ComputedMotion')
        capabilities(end+1,1)="computed_motion";
    end
    if strcmp(local_get(block,'TorqueActuationMode'),'InputTorque')
        capabilities(end+1,1)="torque_actuator";
    end
    if strcmp(local_get(block,'SensePosition'),'on')
        capabilities(end+1,1)="joint_position_sensor";
    end
    if strcmp(local_get(block,'SenseVelocity'),'on')
        capabilities(end+1,1)="joint_velocity_sensor";
    end
    provenance="resolved_library_link";
end
if resolvedLibrary&&physical&&local_any(descriptor, ...
        ["solid","rigid body","body inertia","inertia"])
    capabilities(end+1,1)="rigid_body";provenance="resolved_library_link";
end
if resolvedLibrary&&physical&&local_any(descriptor, ...
        ["transform sensor","motion sensor"])
    capabilities(end+1,1)="physical_pose_sensor";provenance="resolved_library_link";
end
capabilities=unique(capabilities,'stable');
end

function edges=local_add_edge(edges,left,right,kind,fromPort,toPort)
if left==right,return;end
row=struct('from',"n"+string(left),'to',"n"+string(right), ...
    'kind',string(kind),'from_port',string(fromPort),'to_port',string(toPort));
if ~isempty(edges)
    duplicate=arrayfun(@(existing)string(existing.from)==row.from&& ...
        string(existing.to)==row.to&&string(existing.kind)==row.kind&& ...
        string(existing.from_port)==row.from_port&& ...
        string(existing.to_port)==row.to_port,edges);
    if any(duplicate),return;end
end
edges(end+1,1)=row;
end

function owner=local_port_owner(port)
parent=get_param(port,'Parent');
if isnumeric(parent),owner=double(parent); ...
else,owner=double(get_param(parent,'Handle'));end
end

function identity=local_port_identity(block,nodeIndex,port)
identity="n"+string(nodeIndex)+":unknown";
try
    handles=get_param(block,'PortHandles');names=string(fieldnames(handles));
    for name=names'
        ordinal=find(double(reshape(handles.(name),[],1))==double(port),1);
        if ~isempty(ordinal)
            identity="n"+string(nodeIndex)+":"+lower(name)+string(ordinal);return
        end
    end
catch
end
end

function value=local_normalize(value)
value=lower(regexprep(strtrim(string(value)),'\s+',' '));
end
function present=local_any(value,patterns),present=any(contains(value,patterns));end
function present=local_has_physical_ports(block)
present=false;try,ports=get_param(block,'PortHandles'); ...
    present=~isempty(ports.LConn)||~isempty(ports.RConn);catch,end
end
function value=local_get(block,parameter)
value="";try,value=string(get_param(block,parameter));catch,end
end
function local_close(model,wasLoaded)
try,if ~wasLoaded&&bdIsLoaded(model),close_system(model,0);end,catch,end
end
