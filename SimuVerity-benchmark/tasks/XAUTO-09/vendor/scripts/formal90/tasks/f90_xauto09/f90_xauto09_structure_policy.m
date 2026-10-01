function audit = f90_xauto09_structure_policy(model, outputNames)
%F90_XAUTO09_STRUCTURE_POLICY Connected sensing/control/vehicle audit.
%
% Output connectivity and generic dynamics are not substitutes for radar,
% vision, fusion, lane estimation, MPC, or finite-mass vehicle identities.
arguments
    model (1,1) string
    outputNames (:,1) string
end

base = simuverity_candidate_structure(model,outputNames);
blocks = string(find_system(model,"LookUnderMasks","all", ...
    "FollowLinks","on","Type","Block"));
blocks = blocks(blocks ~= model);
assert(numel(blocks)==numel(base.block_rows), ...
    "SimuVerity:F90:XAUTO09:StructureRows","Structural block enumeration changed.");
rows=base.block_rows; semantic=string({rows.semantic_type})';
explicitIdentity = logical([rows.has_physical_ports])' | ...
    strlength(string({rows.source_block})')>0 | ...
    strlength(string({rows.reference_block})')>0 | ...
    strlength(string({rows.mask_type})')>0;
script=localChartScripts(blocks);

radar=localIdentity(semantic,explicitIdentity, ...
    ["radar","range detection","range sensor"]) | ...
    (contains(script,"radveh") & contains(script,"rmax") & ...
     contains(script,"rr") & contains(script,"zeros(1,8)"));
visionVehicle=localIdentity(semantic,explicitIdentity, ...
    ["vision vehicle","vehicle detector","vehicle detection", ...
     "monocular detector","camera detector"]) | ...
    (contains(script,"vehvis") & contains(script,"laney") & ...
     contains(script,"rmax") & contains(script,"kappa"));
fusion=localIdentity(semantic,explicitIdentity, ...
    ["multi-object tracker","multi object tracker","sensor fusion", ...
     "track-level fusion","track level fusion","object fusion", ...
     "lead selection","lead vehicle selector"]) | ...
    (contains(script,"radveh") & contains(script,"vehvis") & ...
     contains(script,"rpred") & contains(script,"resid") & ...
     contains(script,"leadvalid") & contains(script,"trk"));
laneSensor=localIdentity(semantic,explicitIdentity, ...
    ["lane detector","lane detection","lane boundary", ...
     "vision lane","camera lane"]) | ...
    (contains(script,"laney") & contains(script,"kappa") & ...
     contains(script,"xs=") & contains(script,"hn("));
laneEstimator=localIdentity(semantic,explicitIdentity, ...
    ["lane center","lane estimator","lane fit","lane geometry", ...
     "polynomial lane"]) | ...
    (contains(script,"latdev") & contains(script,"relyaw") & ...
     contains(script,"kappaprev") & contains(script,"sxy") & ...
     contains(script,"sx2y"));
controller=localIdentity(semantic,explicitIdentity, ...
    ["model predictive controller","mpc controller", ...
     "lane following controller","adaptive cruise controller", ...
     "longitudinal lateral controller"]) | ...
    (contains(script,"d_safe") & contains(script,"e_gap") & ...
     contains(script,"acmd") & contains(script,"delta_fb") & ...
     contains(script,"delta_ff") & contains(script,"deltacmd"));
vehicle=localIdentity(semantic,explicitIdentity, ...
    ["vehicle body","bicycle model","vehicle dynamics", ...
     "finite mass vehicle","planar vehicle"]) | ...
    (contains(script,"vydot") & contains(script,"rdot") & ...
     contains(script,"cf=") & contains(script,"cr=") & ...
     contains(script,"iz=") & contains(script,"deltacmd"));
environment=localIdentity(semantic,explicitIdentity, ...
    ["driving scenario","scenario reader","traffic environment", ...
     "actor poses"]) | ...
    (contains(script,"tru=") & contains(script,"v_lead") & ...
     contains(script,"rng1") & contains(script,"rr1") & ...
     contains(script,"kappa_true"));

graphValue=localConnectionGraph(blocks);
sources=localOutputSources(model,blocks,outputNames);
source=@(name) any(sources(outputNames==name,:),1)';
rangeSource=source("relative_distance"); rateSource=source("relative_velocity");
lateralSource=source("lateral_deviation"); yawSource=source("relative_yaw_angle");
accelerationSource=source("ego_acceleration"); steeringSource=source("steering_angle");
speedSource=source("ego_velocity");

radarToFusion=localPath(graphValue,radar,fusion);
visionToFusion=localPath(graphValue,visionVehicle,fusion);
fusionToRangeRate=localReach(graphValue,fusion,rangeSource) && ...
    localReach(graphValue,fusion,rateSource);
laneDetectionToEstimate=localReach(graphValue,laneSensor,laneEstimator);
laneToLogs=localReach(graphValue,laneEstimator,lateralSource) && ...
    localReach(graphValue,laneEstimator,yawSource);
fusionToControl=localPath(graphValue,fusion,controller);
laneToControl=localPath(graphValue,laneEstimator,controller);
longitudinalControl=localReach(graphValue,controller,accelerationSource);
lateralControl=localReach(graphValue,controller,steeringSource);
controlToVehicle=localPath(graphValue,controller,vehicle);
vehicleToSensors=localPath(graphValue,vehicle,environment|radar|visionVehicle|laneSensor);
vehicleToSpeed=localReach(graphValue,vehicle,speedSource);
closedSensorLoop=controlToVehicle && vehicleToSensors && ...
    radarToFusion && visionToFusion && fusionToControl && ...
    laneDetectionToEstimate && laneToControl;

audit=struct;
audit.schema="simuverity.f90-xauto09-structure-audit.v1";
audit.policy_id="f90_xauto09_structure_policy";
audit.audit_complete=numel(blocks)>0&& ...
    base.connected_output_count==numel(outputNames)&&all(any(sources,2));
audit.radar_and_vision_detection_path=any(radar)&&any(visionVehicle)&& ...
    radarToFusion&&visionToFusion;
audit.multi_object_fusion_and_lead_selection=any(fusion)&& ...
    radarToFusion&&visionToFusion&&fusionToRangeRate;
audit.detected_lane_center_estimation=any(laneSensor)&&any(laneEstimator)&& ...
    laneDetectionToEstimate&&laneToLogs;
audit.coupled_longitudinal_lateral_mpc=any(controller)&& ...
    fusionToControl&&laneToControl&&longitudinalControl&&lateralControl;
audit.finite_mass_vehicle_dynamics=any(vehicle)&&controlToVehicle&&vehicleToSpeed;
audit.closed_sensor_control_vehicle_loop=closedSensorLoop;
audit.native_fusion_derived_range_rate_logs=fusionToRangeRate;
audit.native_lane_derived_lateral_yaw_logs=laneToLogs;
audit.connected_public_output_count=base.connected_output_count;
audit.generic_connected_or_dynamic_used_as_mechanism_fallback=false;
audit.qualification_basis= ...
    "distinct library identities or executable equation signatures plus actual sensing-estimation-control-vehicle subpaths";
audit.proof_counts=struct("radar",nnz(radar),"vision_vehicle",nnz(visionVehicle), ...
    "fusion_or_tracker",nnz(fusion),"lane_sensor",nnz(laneSensor), ...
    "lane_estimator",nnz(laneEstimator),"mpc_or_coupled_controller",nnz(controller), ...
    "vehicle",nnz(vehicle),"environment",nnz(environment));
audit.path_proofs=struct("radar_to_fusion",radarToFusion, ...
    "vision_to_fusion",visionToFusion,"fusion_to_range_rate",fusionToRangeRate, ...
    "lane_detection_to_estimator",laneDetectionToEstimate, ...
    "lane_estimator_to_logs",laneToLogs,"fusion_to_control",fusionToControl, ...
    "lane_to_control",laneToControl,"longitudinal_control_to_log",longitudinalControl, ...
    "lateral_control_to_log",lateralControl,"control_to_vehicle",controlToVehicle, ...
    "vehicle_to_sensors",vehicleToSensors,"vehicle_to_speed_log",vehicleToSpeed, ...
    "closed_sensor_loop",closedSensorLoop);
end

function scripts=localChartScripts(blocks)
scripts=strings(numel(blocks),1);
try
    charts=find(sfroot,"-isa","Stateflow.EMChart");
catch
    return
end
for index=1:numel(charts)
    try
        blockIndex=find(blocks==string(charts(index).Path),1);
        if ~isempty(blockIndex),scripts(blockIndex)=lower(string(charts(index).Script));end
    catch
    end
end
end

function mask=localIdentity(semantic,explicitIdentity,tokens)
mask=explicitIdentity&any(contains(semantic,tokens),2);
end

function graphValue=localConnectionGraph(blocks)
count=numel(blocks);handles=zeros(count,1);
for index=1:count,handles(index)=get_param(blocks(index),"Handle");end
from=zeros(0,1);to=zeros(0,1);
for index=1:count
    try
        ports=get_param(blocks(index),"PortHandles");
        for port=reshape(ports.Outport,1,[])
            line=get_param(port,"Line");if line<0,continue,end
            destinations=double(reshape(get_param(line,"DstBlockHandle"),[],1));
            for destination=destinations(destinations>0)'
                target=find(handles==destination,1);
                if ~isempty(target),from(end+1,1)=index;to(end+1,1)=target;end %#ok<AGROW>
            end
        end
        physicalPorts=[reshape(ports.LConn,1,[]),reshape(ports.RConn,1,[])];
        for port=physicalPorts
            line=get_param(port,"Line");if line<0,continue,end
            connected=unique([double(get_param(line,"SrcBlockHandle")); ...
                double(reshape(get_param(line,"DstBlockHandle"),[],1))]);
            indices=find(ismember(handles,connected(connected>0)));
            for left=reshape(indices,1,[])
                for right=reshape(indices,1,[])
                    if left~=right,from(end+1,1)=left;to(end+1,1)=right;end %#ok<AGROW>
                end
            end
        end
    catch
    end
end
for index=1:count
    if string(localGet(blocks(index),"BlockType"))~="SubSystem",continue,end
    children=string(find_system(blocks(index),"SearchDepth",1,"Type","Block"));
    children=children(children~=blocks(index));
    for child=children'
        childIndex=find(blocks==child,1);if isempty(childIndex),continue,end
        childType=string(localGet(child,"BlockType"));
        if childType=="Inport",from(end+1,1)=index;to(end+1,1)=childIndex;end %#ok<AGROW>
        if childType=="Outport",from(end+1,1)=childIndex;to(end+1,1)=index;end %#ok<AGROW>
    end
end
graphValue=digraph(from,to,[],count);
end

function sources=localOutputSources(model,blocks,outputNames)
sources=false(numel(outputNames),numel(blocks));
sinks=string(find_system(model,"LookUnderMasks","all","FollowLinks","on", ...
    "BlockType","ToWorkspace"));
for outputIndex=1:numel(outputNames)
    sink="";
    for candidate=sinks'
        if string(localGet(candidate,"VariableName"))==outputNames(outputIndex)
            sink=candidate;break
        end
    end
    if strlength(sink)==0
        candidates=string(find_system(model,"SearchDepth",1,"BlockType","Outport"));
        for candidate=candidates'
            if string(localGet(candidate,"Name"))==outputNames(outputIndex)
                sink=candidate;break
            end
        end
    end
    if strlength(sink)==0,continue,end
    try
        ports=get_param(sink,"PortHandles");line=get_param(ports.Inport(1),"Line");
        sourcePort=get_param(line,"SrcPortHandle");
        sourceBlock=string(get_param(sourcePort,"Parent"));
        sourceIndex=find(blocks==sourceBlock,1);
        if ~isempty(sourceIndex),sources(outputIndex,sourceIndex)=true;end
    catch
    end
end
end

function present=localPath(graphValue,fromMask,toMask)
source=find(fromMask);target=find(toMask);present=false;
if isempty(source)||isempty(target),return,end
distance=distances(graphValue,source,target);
present=any(isfinite(distance(:))&distance(:)>0);
end

function present=localReach(graphValue,fromMask,toMask)
present=any(fromMask&toMask)||localPath(graphValue,fromMask,toMask);
end

function value=localGet(block,parameter)
value="";try,value=string(get_param(block,parameter));catch,end
end
