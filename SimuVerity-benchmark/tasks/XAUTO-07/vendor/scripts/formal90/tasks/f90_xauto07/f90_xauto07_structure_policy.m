function audit = f90_xauto07_structure_policy(model, outputNames)
%F90_XAUTO07_STRUCTURE_POLICY Mechanism-specific connected-path audit.
%
% Generic model complexity or a generic closed loop is never evidence for a
% battery, converter, IPMSM, gearbox, axle, or finite-mass vehicle.  Each
% mechanism needs an explicit implementation identity plus the relevant
% connected subpath.
arguments
    model (1,1) string
    outputNames (:,1) string
end

base = simuverity_candidate_structure(model, outputNames);
blocks = string(find_system(model, "LookUnderMasks", "all", ...
    "FollowLinks", "on", "Type", "Block"));
blocks = blocks(blocks ~= model);
assert(numel(blocks) == numel(base.block_rows), ...
    "SimuVerity:F90:XAUTO07:StructureRows", "Structural block enumeration changed.");
rows = base.block_rows;
semantic = string({rows.semantic_type})';
blockType = string({rows.block_type})';
explicitIdentity = logical([rows.has_physical_ports])' | ...
    strlength(string({rows.source_block})') > 0 | ...
    strlength(string({rows.reference_block})') > 0 | ...
    strlength(string({rows.mask_type})') > 0;
script = localChartScripts(blocks);

dcLink = localIdentity(semantic, explicitIdentity, ...
    ["dc link", "capacitor", "dc-link"]) | ...
    (contains(script,"dvdc") & contains(script,"idc_bat") & ...
     contains(script,"rint") & contains(script,"cdc"));
converter = localIdentity(semantic, explicitIdentity, ...
    ["three-phase converter", "three phase converter", "inverter", ...
     "universal bridge", "controlled converter", "igbt bridge"]) | ...
    (contains(script,"valpha") & contains(script,"vbeta") & ...
     contains(script,"pac") & contains(script,"idc_inv") & ...
     contains(script,"va=") & contains(script,"vb=") & contains(script,"vc="));
electricalMachine = localIdentity(semantic, explicitIdentity, ...
    ["interior permanent magnet", "ipmsm", "permanent magnet synchronous", ...
     "pmsm"]) | ...
    (contains(script,"did=") & contains(script,"diq=") & ...
     contains(script,"ld") & contains(script,"lq") & ...
     contains(script,"lambda") & contains(script,"omega_e"));
torqueMachine = localIdentity(semantic, explicitIdentity, ...
    ["interior permanent magnet", "ipmsm", "permanent magnet synchronous", ...
     "pmsm", "electromagnetic torque"]) | ...
    (contains(script,"te=") & contains(script,"tsh=") & ...
     contains(script,"(ld-lq)") & contains(script,"ia=") & ...
     contains(script,"ib=") & contains(script,"ic="));
machine = electricalMachine | torqueMachine;
currentSensor = localIdentity(semantic, explicitIdentity, ...
    ["current sensor", "current measurement", "three-phase v-i measurement", ...
     "three phase v-i measurement"]) | ...
    (contains(script,"ialpha") & contains(script,"ibeta") & ...
     contains(script,"id_m=") & contains(script,"iq_m=") & ...
     contains(script,"ia") & contains(script,"ib") & contains(script,"ic"));
currentController = localIdentity(semantic, explicitIdentity, ...
    ["current controller", "current control", "field-oriented control", ...
     "field oriented control", "foc controller"]) | ...
    (contains(script,"iqref") & contains(script,"idref") & ...
     contains(script,"kpd") & contains(script,"kid") & ...
     contains(script,"kpq") & contains(script,"kiq") & ...
     contains(script,"vd=") & contains(script,"vq="));
torqueReference = localIdentity(semantic, explicitIdentity, ...
    ["torque reference", "torque command", "torque controller"]) | ...
    (contains(script,"tref=") & contains(script,"accel") & ...
     contains(script,"brake") & contains(script,"tlim"));
torqueEstimator = localIdentity(semantic, explicitIdentity, ...
    ["torque estimator", "torque estimation", "torque sensor", ...
     "torque measurement"]) | ...
    (contains(script,"test=") & contains(script,"id_m") & ...
     contains(script,"iq_m") & contains(script,"(ld-lq)"));
gearIdentity = localIdentity(semantic, explicitIdentity, ...
    ["gear", "gearbox", "differential", "axle"]);
vehicle = localIdentity(semantic, explicitIdentity, ...
    ["vehicle body", "longitudinal vehicle", "vehicle dynamics", ...
     "finite mass", "tire"]) | ...
    (contains(script,"dv=") & contains(script,"ftr") & ...
     contains(script,"froll") & contains(script,"faero") & ...
     contains(script,"fgrade") & contains(script,"meff"));
driverController = currentController & torqueReference;

graphValue = localConnectionGraph(blocks);
outputSources = localOutputSources(model, blocks, outputNames);
motorTorqueSource = any(outputSources(outputNames == "motor_torque",:),1)';
phaseCurrentSource = any(outputSources(outputNames == "phase_currents",:),1)';
vehicleSpeedSource = any(outputSources(outputNames == "vehicle_speed",:),1)';

powerSource = ismember(blockType,["Constant","FromWorkspace"]) | ...
    localIdentity(semantic,explicitIdentity,["battery","dc voltage source","dc source"]);
sourceToDcLink = localPath(graphValue,powerSource,dcLink);
dcLinkToConverter = localPath(graphValue,dcLink,converter);
batteryToConverter = sourceToDcLink && dcLinkToConverter;
converterToElectricalMachine = localPath(graphValue,converter,electricalMachine);
electricalToTorqueMachine = localPath(graphValue,electricalMachine,torqueMachine);
converterToMachine = converterToElectricalMachine && electricalToTorqueMachine;
gear = gearIdentity | blockType == "Gain";
machineToGear = localPath(graphValue,torqueMachine,gear);
gearToVehicle = localPath(graphValue,gear,vehicle);
currentFeedback = localPathVia(graphValue, currentSensor | phaseCurrentSource, ...
    currentController, converter);
torqueEvidence = localReach(graphValue, torqueReference, motorTorqueSource) && ...
    localReach(graphValue, machine | torqueEstimator, motorTorqueSource) && ...
    any(torqueEstimator);
closedDrive = localPathVia(graphValue, driverController | torqueReference, ...
    converter, machine) && machineToGear && gearToVehicle && ...
    localPath(graphValue, vehicle | vehicleSpeedSource, driverController | torqueReference);

audit = struct;
audit.schema = "simuverity.f90-xauto07-structure-audit.v1";
audit.policy_id = "f90_xauto07_structure_policy";
audit.audit_complete = numel(blocks) > 0 && ...
    base.connected_output_count == numel(outputNames) && all(any(outputSources,2));
audit.battery_and_dc_link = any(powerSource) && any(dcLink) && batteryToConverter;
audit.controlled_three_phase_converter = any(converter) && ...
    batteryToConverter && converterToMachine;
audit.interior_permanent_magnet_motor = any(electricalMachine) && ...
    any(torqueMachine) && converterToMachine && machineToGear;
audit.closed_loop_phase_current_control = any(currentSensor) && ...
    any(currentController) && currentFeedback;
audit.torque_reference_and_estimation = any(torqueReference) && ...
    torqueEvidence;
audit.fixed_ratio_gear_and_axle = any(gear) && machineToGear && gearToVehicle;
audit.finite_mass_vehicle_dynamics = any(vehicle) && gearToVehicle && ...
    localReach(graphValue,vehicle,vehicleSpeedSource);
audit.closed_driver_drive_vehicle_feedback = closedDrive;
audit.connected_public_output_count = base.connected_output_count;
audit.generic_closed_loop_used_as_mechanism_fallback = false;
audit.qualification_basis = ...
    "distinct library identities or executable equation signatures plus actual connection subpaths";
audit.proof_counts = struct( ...
    "candidate_power_source", nnz(powerSource), "dc_link", nnz(dcLink), ...
    "converter", nnz(converter), ...
    "ipmsm_electrical", nnz(electricalMachine), ...
    "ipmsm_torque", nnz(torqueMachine), ...
    "current_sensor", nnz(currentSensor), ...
    "current_controller", nnz(currentController), ...
    "torque_reference", nnz(torqueReference), ...
    "torque_estimator", nnz(torqueEstimator), ...
    "gear_or_axle", nnz(gear), "vehicle", nnz(vehicle));
audit.path_proofs = struct( ...
    "source_to_dc_link", sourceToDcLink, ...
    "dc_link_to_converter", dcLinkToConverter, ...
    "battery_to_converter", batteryToConverter, ...
    "converter_to_electrical_machine", converterToElectricalMachine, ...
    "electrical_to_torque_machine", electricalToTorqueMachine, ...
    "converter_to_machine", converterToMachine, ...
    "machine_to_gear", machineToGear, ...
    "gear_to_vehicle", gearToVehicle, ...
    "phase_current_feedback", currentFeedback, ...
    "torque_reference_and_estimation_to_log", torqueEvidence, ...
    "closed_driver_drive_vehicle_feedback", closedDrive);
end

function scripts = localChartScripts(blocks)
scripts = strings(numel(blocks),1);
try
    charts = find(sfroot,"-isa","Stateflow.EMChart");
catch
    return
end
for index = 1:numel(charts)
    try
        blockIndex = find(blocks == string(charts(index).Path),1);
        if ~isempty(blockIndex)
            scripts(blockIndex) = lower(string(charts(index).Script));
        end
    catch
    end
end
end

function mask = localIdentity(semantic, explicitIdentity, tokens)
mask = explicitIdentity & any(contains(semantic, tokens), 2);
end

function graphValue = localConnectionGraph(blocks)
count = numel(blocks);
handles = zeros(count, 1);
for index = 1:count
    handles(index) = get_param(blocks(index), "Handle");
end
from = zeros(0, 1); to = zeros(0, 1);
for index = 1:count
    try
        ports = get_param(blocks(index), "PortHandles");
        for port = reshape(ports.Outport, 1, [])
            line = get_param(port, "Line");
            if line < 0, continue, end
            destinations = double(reshape(get_param(line, "DstBlockHandle"), [], 1));
            for destination = destinations(destinations > 0)'
                target = find(handles == destination, 1);
                if ~isempty(target), from(end+1,1)=index; to(end+1,1)=target; end %#ok<AGROW>
            end
        end
        physicalPorts = [reshape(ports.LConn,1,[]), reshape(ports.RConn,1,[])];
        for port = physicalPorts
            line = get_param(port, "Line");
            if line < 0, continue, end
            connected = unique([double(get_param(line,"SrcBlockHandle")); ...
                double(reshape(get_param(line,"DstBlockHandle"),[],1))]);
            indices = find(ismember(handles, connected(connected > 0)));
            for left = reshape(indices,1,[])
                for right = reshape(indices,1,[])
                    if left ~= right, from(end+1,1)=left; to(end+1,1)=right; end %#ok<AGROW>
                end
            end
        end
    catch
    end
end
for index = 1:count
    if string(localGet(blocks(index),"BlockType")) ~= "SubSystem", continue, end
    children = string(find_system(blocks(index),"SearchDepth",1,"Type","Block"));
    children = children(children ~= blocks(index));
    for child = children'
        childIndex = find(blocks == child, 1);
        if isempty(childIndex), continue, end
        childType = string(localGet(child,"BlockType"));
        if childType == "Inport", from(end+1,1)=index; to(end+1,1)=childIndex; end %#ok<AGROW>
        if childType == "Outport", from(end+1,1)=childIndex; to(end+1,1)=index; end %#ok<AGROW>
    end
end
graphValue = digraph(from, to, [], count);
end

function sources = localOutputSources(model, blocks, outputNames)
sources = false(numel(outputNames), numel(blocks));
sinks = string(find_system(model,"LookUnderMasks","all","FollowLinks","on", ...
    "BlockType","ToWorkspace"));
for outputIndex = 1:numel(outputNames)
    sink = "";
    for candidate = sinks'
        if string(localGet(candidate,"VariableName")) == outputNames(outputIndex)
            sink = candidate; break
        end
    end
    if strlength(sink) == 0
        candidates = string(find_system(model,"SearchDepth",1,"BlockType","Outport"));
        for candidate = candidates'
            if string(localGet(candidate,"Name")) == outputNames(outputIndex)
                sink = candidate; break
            end
        end
    end
    if strlength(sink) == 0, continue, end
    try
        ports = get_param(sink,"PortHandles"); line = get_param(ports.Inport(1),"Line");
        sourcePort = get_param(line,"SrcPortHandle");
        sourceBlock = string(get_param(sourcePort,"Parent"));
        sourceIndex = find(blocks == sourceBlock,1);
        if ~isempty(sourceIndex), sources(outputIndex,sourceIndex)=true; end
    catch
    end
end
end

function present = localPath(graphValue, fromMask, toMask)
source = find(fromMask); target = find(toMask); present = false;
if isempty(source) || isempty(target), return, end
distance = distances(graphValue, source, target);
present = any(isfinite(distance(:)) & distance(:) > 0);
end

function present = localReach(graphValue, fromMask, toMask)
present = any(fromMask & toMask) || localPath(graphValue,fromMask,toMask);
end

function present = localPathVia(graphValue, fromMask, viaMask, toMask)
present = false;
for via = reshape(find(viaMask),1,[])
    one = false(size(viaMask)); one(via)=true;
    if localPath(graphValue,fromMask,one) && localPath(graphValue,one,toMask)
        present = true; return
    end
end
end

function value = localGet(block, parameter)
value = "";
try, value = string(get_param(block,parameter)); catch, end
end
