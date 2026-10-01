function result = f90_xmech06_extract_evidence(modelPath, outputDir)
repo = pwd;
definition = f90_xmech06_definition;
taskRoot = fileparts(definition.public_spec);
referenceRoot = string(getenv("SIMUVERITY_RUNTIME_SUBMISSION_BUNDLE"));
if nargin < 1 || strlength(string(modelPath)) == 0
    modelPath = definition.reference_model;
end
generationRunId = string(getenv("SIMUVERITY_GENERATION_RUN_ID"));
if strlength(generationRunId) == 0
    generationRunId = "f90_xmech06_manual_" + ...
        string(datetime("now", "Format", "yyyyMMdd'T'HHmmss"));
end
if nargin < 2 || strlength(string(outputDir)) == 0
    outputDir = fullfile(repo, "results", "cross_domain", ...
        "simuverity_public", "F90-XMECH-06", "fixed_evidence", generationRunId);
end
if ~isfolder(outputDir)
    mkdir(outputDir);
end

referenceBinding = lower(string(definition.reference_file_presence));
bindingBefore = localFilePresence(modelPath);
isReference = lower(strtrim(string(getenv("SIMUVERITY_EVALUATION_SUBJECT")))) == "reference";
evidence = struct( ...
    "schema", "simuverity.f90-xmech06-evidence.v1", ...
    "metric_semantics", "event-derived-brake-window", ...
    "task_id", "F90-XMECH-06", ...
    "generation_run_id", generationRunId, ...
    "model_path", string(modelPath), ...
    "model_file_presence_before", bindingBefore, ...
    "reference_direct_golden", isReference, ...
    "reference_substantive_modifications", 0, ...
    "extraction_only", true, ...
    "contains_score_decisions", false, ...
    "load_pass", false, ...
    "update_pass", false, ...
    "compile_pass", false, ...
    "nominal_smoke_pass", false, ...
    "static_audit", struct(), ...
    "scenarios", [], ...
    "errors", {{}}, ...
    "started_at", localNow());

projectHandle = [];
modelName = 'sm_car';
try
    if isReference
        projectHandle = openProject(fullfile(referenceRoot, "SSVT_FSAE.prj"));
        modelName = 'sm_car';
    else
        [modelDir, modelName] = fileparts(modelPath);
        addpath(modelDir, "-begin");
        load_system(modelPath);
    end
    evidence.load_pass = bdIsLoaded(modelName);
    set_param(modelName, "SimulationMode", "normal");
    if isReference
        set_param(modelName, "SignalLogging", "on", ...
            "SignalLoggingName", "logsout_sm_car");
    end
    if isReference
        evalin("base", "Vehicle_data_dwishbone;");
        sm_car_config_vehicle(modelName, true);
        sm_car_config_maneuver(modelName, "Skidpad");
        sm_car_config_logging(modelName);
    end
    set_param(modelName, "SimulationCommand", "update");
    evidence.update_pass = true;
    feval(modelName, [], [], [], "compile");
    feval(modelName, [], [], [], "term");
    evidence.compile_pass = true;
    evidence.static_audit = localStaticAudit(modelName, isReference);

    if isReference
        localApplyReferenceScenario(modelName, definition.scenarios(1));
    end
    smokeOut = sim(modelName, "StopTime", "0.20", ...
        "ReturnWorkspaceOutputs", "on", "SimulationMode", "normal");
    smokeLogs = localGetSimulationLogs(smokeOut, isReference);
    evidence.nominal_smoke_pass = ~isempty(smokeLogs);

    rows = repmat(localEmptyScenario(), numel(definition.scenarios), 1);
    batchTimer = tic;
    for index = 1:numel(definition.scenarios)
        scenario = definition.scenarios(index);
        row = localEmptyScenario();
        row.id = string(scenario.id);
        row.requested_inputs = rmfield(rmfield(scenario, "id"), "class");
        scenarioTimer = tic;
        try
            assignin("base", "EventMode", string(scenario.EventMode));
            assignin("base", "SpeedScale", double(scenario.SpeedScale));
            assignin("base", "RoadFrictionScale", ...
                double(scenario.RoadFrictionScale));
            assignin("base", "PayloadMass_kg", double(scenario.PayloadMass_kg));
            if isReference
                localApplyReferenceScenario(modelName, scenario);
            end
            stopTime = double(scenario.stop_time_s);
            out = sim(modelName, "StopTime", string(stopTime), ...
                "ReturnWorkspaceOutputs", "on", "SimulationMode", "normal");
            logs = localGetSimulationLogs(out, isReference);
            [row.metrics, row.output_contract] = ...
                localExtractMetrics(logs, stopTime, scenario);
            row.simulation_pass = true;
            row.valid = all(structfun(@(value) logical(value), ...
                row.output_contract));
            if ~row.valid
                row.error = struct("identifier", ...
                    "SimuVerity:F90:XMECH06:OutputContract", ...
                    "message", "One or more required output contracts failed.");
            end
        catch exception
            row.error = localError(exception);
        end
        row.simulation_wall_seconds = toc(scenarioTimer);
        rows(index) = row;
    end
    evidence.official_batch_wall_seconds = toc(batchTimer);
    evidence.scenarios = rows;
catch exception
    evidence.errors{end + 1} = localError(exception);
    try
        feval(modelName, [], [], [], "term");
    catch
    end
end

try
    close_system(modelName, 0);
catch
end
try
    if ~isempty(projectHandle)
        close(projectHandle);
    end
catch
end
evidence.model_file_presence_after = localFilePresence(modelPath);
evidence.reference_binding_preserved = (~isReference) || ...
    evidence.model_file_presence_after == referenceBinding;
evidence.model_closed_without_save = true;
evidence.finished_at = localNow();
evidence.runtime = struct( ...
    "matlab_release", string(version("-release")), ...
    "generation_run_id", generationRunId, ...
    "matlab_prefdir", string(prefdir), ...
    "appdata", string(getenv("APPDATA")), ...
    "temp", string(getenv("TEMP")), ...
    "cache", string(getenv("SIMULINK_CACHE_FOLDER")), ...
    "codegen", string(getenv("SIMULINK_CODEGEN_FOLDER")), ...
    "mcp_port", string(getenv("SIMUVERITY_MCP_PORT")));

evidencePath = fullfile(outputDir, "evidence.json");
localWriteJson(evidencePath, evidence);
result = evidence;
validCount = 0;
if ~isempty(evidence.scenarios)
    validCount = sum([evidence.scenarios.valid]);
end
fprintf("F90_XMECH06_EVIDENCE load=%d update=%d compile=%d smoke=%d valid=%d/%d path=%s\n", ...
    evidence.load_pass, evidence.update_pass, evidence.compile_pass, ...
    evidence.nominal_smoke_pass, validCount, numel(evidence.scenarios), ...
    evidencePath);
end

function localApplyReferenceScenario(model, scenario)
evalin("base", "Vehicle_data_dwishbone;");
sm_car_config_vehicle(model, true);
event = char(string(scenario.EventMode));
if strcmpi(event, "WOT_Braking")
    sm_car_config_maneuver(model, "WOT Braking");
else
    sm_car_config_maneuver(model, "Skidpad");
    maneuver = evalin("base", "Maneuver");
    maneuver.vGain.Value = double(scenario.SpeedScale);
    assignin("base", "Maneuver", maneuver);
end
vehicle = evalin("base", "Vehicle");
vehicle.Chassis.Body.m.Value = vehicle.Chassis.Body.m.Value + ...
    double(scenario.PayloadMass_kg);
assignin("base", "Vehicle", vehicle);
options = Simulink.FindOptions("LookUnderMasks", "all");
muBlocks = Simulink.findBlocks(model, "Name", "Mu Scaling by Position", options);
assert(~isempty(muBlocks), "SimuVerity:F90:XMECH06:FrictionLocator", ...
    "The native road-friction block was not found.");
mu = string(double(scenario.RoadFrictionScale));
for index = 1:numel(muBlocks)
    set_param(muBlocks(index), "muFL_in", mu, "muFR_in", mu, ...
        "muRL_in", mu, "muRR_in", mu);
end
set_param(model, "StopTime", string(double(scenario.stop_time_s)));
set_param(model, "SimulationCommand", "update");
end

function audit = localStaticAudit(model, isReference)
audit = struct( ...
    "audit_policy_id", "f90-xmech06-connected-causal-path", ...
    "six_dof_vehicle_present", false, ...
    "closed_loop_driver_present", false, ...
    "vehicle_controller_present", false, ...
    "four_wheel_tire_contact_present", false, ...
    "front_rear_suspension_present", false, ...
    "steering_brake_drive_actuation_present", false, ...
    "native_physical_logging_present", false, ...
    "core_path_qualified", false, ...
    "connected_causal_path_qualified", false, ...
    "output_contract_connected", false, ...
    "stateful_feedback_path_connected", false, ...
    "input_source_to_dynamic_path", false, ...
    "reference_to_command_path", false, ...
    "dynamic_path_to_mechanism_outputs", false, ...
    "causal_graph_covers_six_outputs", false, ...
    "top_level_block_count", 0, ...
    "top_level_line_count", 0, ...
    "state_owner_count", 0, ...
    "qualifying_feedback_state_count", 0, ...
    "public_output_count", 0, ...
    "failure_facts", strings(0, 1));
if ~isReference
    connectionAudit = localCandidateConnectionAudit(model);
    names = fieldnames(connectionAudit);
    for index = 1:numel(names)
        audit.(names{index}) = connectionAudit.(names{index});
    end
    audit.native_physical_logging_present = ...
        audit.output_contract_connected;
    audit.core_path_qualified = ...
        audit.connected_causal_path_qualified;
    return;
end
audit.six_dof_vehicle_present = ...
    getSimulinkBlockHandle(model + "/Vehicle/Vehicle") > 0;
audit.closed_loop_driver_present = ...
    getSimulinkBlockHandle(model + "/Driver/Closed Loop") > 0;
audit.vehicle_controller_present = ...
    getSimulinkBlockHandle(model + "/Controller") > 0;
audit.four_wheel_tire_contact_present = ...
    getSimulinkBlockHandle(model + "/Vehicle") > 0;
audit.front_rear_suspension_present = ...
    getSimulinkBlockHandle(model + "/Vehicle/Vehicle") > 0;
audit.steering_brake_drive_actuation_present = ...
    getSimulinkBlockHandle(model + "/Controller") > 0;
audit.native_physical_logging_present = ...
    getSimulinkBlockHandle(model + "/Road") > 0;
audit.core_path_qualified = all([ ...
    audit.six_dof_vehicle_present, ...
    audit.closed_loop_driver_present, ...
    audit.vehicle_controller_present, ...
    audit.four_wheel_tire_contact_present, ...
    audit.front_rear_suspension_present, ...
    audit.steering_brake_drive_actuation_present, ...
    audit.native_physical_logging_present]);
audit.connected_causal_path_qualified = audit.core_path_qualified;
end

function audit = localCandidateConnectionAudit(model)
contracts = {
    "VehicleState", 9;
    "ReferenceState", 3;
    "WheelForces", 12;
    "TireSlip", 4;
    "SuspensionState", 8;
    "DriverCommands", 3
};
[blocks, handles, adjacency, lineCount] = localTopLevelGraph(model);
blockCount = numel(blocks);
outputIndices = zeros(size(contracts, 1), 1);
outputConnected = false(size(contracts, 1), 1);
for index = 1:size(contracts, 1)
    outputName = char(contracts{index, 1});
    matches = find_system(model, "SearchDepth", 1, ...
        "BlockType", "ToWorkspace", "VariableName", outputName);
    if numel(matches) ~= 1 || ...
            ~strcmpi(string(get_param(matches{1}, "SaveFormat")), "Timeseries")
        continue;
    end
    outputIndices(index) = localHandleIndex( ...
        handles, getSimulinkBlockHandle(matches{1}));
    if outputIndices(index) > 0
        outputConnected(index) = any(adjacency(:, outputIndices(index)));
    end
end
outputContractConnected = all(outputConnected);

stateOwners = false(blockCount, 1);
for index = 1:blockCount
    try
        stateOwners(index) = strcmpi(string( ...
            get_param(blocks(index), "IsStateOwnerBlock")), "on");
    catch
    end
end

commandSource = 0;
referenceSource = 0;
if outputContractConnected
    commandSource = localUniqueSource(adjacency, outputIndices(6));
    referenceSource = localUniqueSource(adjacency, outputIndices(2));
end
mechanismOutputs = outputIndices([1, 3, 4, 5]);
qualifyingStates = false(blockCount, 1);
if commandSource > 0 && all(mechanismOutputs > 0)
    for stateIndex = reshape(find(stateOwners), 1, [])
        qualifyingStates(stateIndex) = ...
            localPathExists(adjacency, commandSource, stateIndex) && ...
            localPathExists(adjacency, stateIndex, commandSource) && ...
            all(arrayfun(@(target) localPathExists( ...
                adjacency, stateIndex, target), mechanismOutputs));
    end
end
statefulFeedback = any(qualifyingStates);

inDegree = sum(adjacency, 1)';
inputSources = find(inDegree == 0);
if ~isempty(outputIndices)
    inputSources = setdiff(inputSources, outputIndices(outputIndices > 0));
end
inputToDynamic = false;
for sourceIndex = reshape(inputSources, 1, [])
    for stateIndex = reshape(find(qualifyingStates), 1, [])
        inputToDynamic = inputToDynamic || ...
            localPathExists(adjacency, sourceIndex, stateIndex);
    end
end
referenceToCommand = referenceSource > 0 && commandSource > 0 && ...
    localPathExists(adjacency, referenceSource, commandSource);
dynamicToMechanism = false;
for stateIndex = reshape(find(qualifyingStates), 1, [])
    dynamicToMechanism = dynamicToMechanism || all(arrayfun( ...
        @(target) localPathExists(adjacency, stateIndex, target), ...
        mechanismOutputs));
end
causalGraphCoversSix = statefulFeedback && referenceToCommand && ...
    localPathExists(adjacency, commandSource, outputIndices(6)) && ...
    localPathExists(adjacency, referenceSource, outputIndices(2)) && ...
    dynamicToMechanism;
qualified = outputContractConnected && statefulFeedback && ...
    inputToDynamic && referenceToCommand && dynamicToMechanism && ...
    causalGraphCoversSix;

failureFacts = strings(0, 1);
if ~outputContractConnected
    failureFacts(end+1, 1) = "required_public_outputs_not_connected";
end
if ~statefulFeedback
    failureFacts(end+1, 1) = "stateful_command_feedback_path_not_connected";
end
if ~inputToDynamic
    failureFacts(end+1, 1) = "input_source_does_not_reach_dynamic_path";
end
if ~referenceToCommand
    failureFacts(end+1, 1) = "reference_path_does_not_reach_command_path";
end
if ~dynamicToMechanism
    failureFacts(end+1, 1) = "dynamic_path_does_not_reach_mechanism_outputs";
end
if ~causalGraphCoversSix
    failureFacts(end+1, 1) = "causal_graph_does_not_cover_six_public_outputs";
end
audit = struct( ...
    "connected_causal_path_qualified", qualified, ...
    "output_contract_connected", outputContractConnected, ...
    "stateful_feedback_path_connected", statefulFeedback, ...
    "input_source_to_dynamic_path", inputToDynamic, ...
    "reference_to_command_path", referenceToCommand, ...
    "dynamic_path_to_mechanism_outputs", dynamicToMechanism, ...
    "causal_graph_covers_six_outputs", causalGraphCoversSix, ...
    "top_level_block_count", blockCount, ...
    "top_level_line_count", lineCount, ...
    "state_owner_count", sum(stateOwners), ...
    "qualifying_feedback_state_count", sum(qualifyingStates), ...
    "public_output_count", sum(outputConnected), ...
    "failure_facts", failureFacts);
end

function [blocks, handles, adjacency, lineCount] = localTopLevelGraph(model)
blocks = string(find_system(model, "SearchDepth", 1, "Type", "Block"));
blocks(blocks == string(model)) = [];
handles = zeros(numel(blocks), 1);
for index = 1:numel(blocks)
    handles(index) = getSimulinkBlockHandle(blocks(index));
end
adjacency = false(numel(blocks));
lines = find_system(model, "SearchDepth", 1, ...
    "FindAll", "on", "Type", "line");
lineCount = numel(lines);
for line = reshape(lines, 1, [])
    try
        sourcePort = get_param(line, "SrcPortHandle");
        sourceBlock = getSimulinkBlockHandle(get_param(sourcePort, "Parent"));
        sourceIndex = localHandleIndex(handles, sourceBlock);
        destinationPorts = get_param(line, "DstPortHandle");
        for destinationPort = reshape(destinationPorts, 1, [])
            if destinationPort <= 0 || sourceIndex == 0
                continue;
            end
            destinationBlock = getSimulinkBlockHandle( ...
                get_param(destinationPort, "Parent"));
            destinationIndex = localHandleIndex(handles, destinationBlock);
            if destinationIndex > 0
                adjacency(sourceIndex, destinationIndex) = true;
            end
        end
    catch
    end
end
end

function index = localHandleIndex(handles, handle)
index = find(handles == double(handle), 1);
if isempty(index), index = 0; end
end

function source = localUniqueSource(adjacency, target)
sources = find(adjacency(:, target));
if numel(sources) == 1
    source = sources(1);
else
    source = 0;
end
end

function present = localPathExists(adjacency, source, target)
present = false;
if source <= 0 || target <= 0
    return;
end
visited = false(size(adjacency, 1), 1);
pending = source;
visited(source) = true;
while ~isempty(pending)
    current = pending(1);
    pending(1) = [];
    if current == target
        present = true;
        return;
    end
    next = find(adjacency(current, :));
    next = next(~visited(next));
    visited(next) = true;
    pending = [pending; next(:)]; %#ok<AGROW>
end
end

function logs = localGetSimulationLogs(out, isReference)
if isReference
    logs = localGetNativeLogs(out);
else
    logs = localGetCandidatePublicLogs(out);
end
end

function logs = localGetCandidatePublicLogs(out)
contracts = {
    "VehicleState", 9;
    "ReferenceState", 3;
    "WheelForces", 12;
    "TireSlip", 4;
    "SuspensionState", 8;
    "DriverCommands", 3
};
logs = Simulink.SimulationData.Dataset;
for index = 1:size(contracts, 1)
    name = string(contracts{index, 1});
    width = double(contracts{index, 2});
    [value, ~] = simuverity_public_output_compatibility( ...
        out, name, width, AllowBaseWorkspace=true);
    logs = logs.addElement(value, char(name));
end
end

function logs = localGetNativeLogs(out)
logs = [];
names = ["logsout_sm_car", "logsout"];
for name = names
    try
        logs = out.get(name);
    catch
    end
    if ~isempty(logs)
        return;
    end
    try
        logs = evalin("base", name);
    catch
    end
    if ~isempty(logs)
        return;
    end
end
assert(~isempty(logs), "SimuVerity:F90:XMECH06:MissingLogsout", ...
    "The required native logsout dataset was not produced.");
end

function [metrics, contract] = localExtractMetrics(logs, stopTime, scenario)
% Candidate submissions are evaluated through the public output contract.
% The native sm_car branch below is retained only for reference evaluation.
if localDatasetHas(logs, "VehicleState") && ...
        localDatasetHas(logs, "ReferenceState") && ...
        localDatasetHas(logs, "WheelForces") && ...
        localDatasetHas(logs, "TireSlip") && ...
        localDatasetHas(logs, "SuspensionState") && ...
        localDatasetHas(logs, "DriverCommands")
    [metrics, contract] = localExtractPublicMetrics(logs, stopTime, scenario);
    return;
end
vehicle = evalin("base", "Vehicle");
% The upstream R2025a helper indexes varName as a character vector
% (for example, varName(2)); normalize all calls at this adapter boundary.
timeResult = sm_car_sim_res_get(logs, [], vehicle, 'time');
time = double(timeResult.data(:));
speed = localResult(logs, vehicle, "vVeh", time);
gx = localResult(logs, vehicle, "gxVeh", time);
gy = localResult(logs, vehicle, "gyVeh", time);
roll = localResult(logs, vehicle, "aRoll", time);
pitch = localResult(logs, vehicle, "aPitch", time);
yaw = localResult(logs, vehicle, "aYaw", time);
yawRate = localResult(logs, vehicle, "nYaw", time);
worldX = localResult(logs, vehicle, "pxVeh", time);
worldY = localResult(logs, vehicle, "pyVeh", time);
fxResult = sm_car_sim_res_get(logs, [], vehicle, 'fxWhl');
fyResult = sm_car_sim_res_get(logs, [], vehicle, 'fyWhl');
fzResult = sm_car_sim_res_get(logs, [], vehicle, 'fzWhl');
slipResult = sm_car_sim_res_get(logs, [], vehicle, 'aSlipWhl');
fx = localWheelOrder(localAlign(fxResult.data, time), fxResult.labels);
fy = localWheelOrder(localAlign(fyResult.data, time), fyResult.labels);
fz = localWheelOrder(localAlign(fzResult.data, time), fzResult.labels);
slip = localWheelOrder(localAlign(slipResult.data, time), slipResult.labels);
xShock = localResult(logs, vehicle, "xShock", time);
vShock = localResult(logs, vehicle, "vShock", time);

driver = logs.get("DrvBus").Values;
targetSpeed = localSample(driver.Reference.vTarget, time);
referenceYaw = localSample(driver.Reference.ayaw, time);
referenceDistance = localSample(driver.Reference.dist, time);
steering = localSample(driver.aSteerWheel, time);
accelerator = localSample(driver.rAccelPedal, time);
brake = localSample(driver.rBrakePedal, time);

vehicleState = [speed, gx, gy, roll, pitch, yaw, yawRate, worldX, worldY];
referenceState = [targetSpeed, referenceYaw, referenceDistance];
wheelForces = [fx, fy, fz];
suspensionState = [xShock, vShock];
driverCommands = [steering, accelerator, brake];
contract = struct( ...
    "vehicle_state_9_channels", localContract(time, vehicleState, stopTime, 9), ...
    "reference_state_3_channels", localContract(time, referenceState, stopTime, 3), ...
    "wheel_forces_12_channels", localContract(time, wheelForces, stopTime, 12), ...
    "tire_slip_4_channels", localContract(time, slip, stopTime, 4), ...
    "suspension_state_8_channels", ...
        localContract(time, suspensionState, stopTime, 8), ...
    "driver_commands_3_channels", ...
        localContract(time, driverCommands, stopTime, 3));

steady = time >= min(2.0, 0.2 * stopTime);
if strcmpi(string(scenario.EventMode), "WOT_Braking")
    active = time >= 1.0;
else
    active = steady;
end
yawError = atan2(sin(yaw - referenceYaw), cos(yaw - referenceYaw));
sumFx = sum(fx, 2);
sumFy = sum(fy, 2);
leftRightFz = (fz(:, 2) + fz(:, 4)) - (fz(:, 1) + fz(:, 3));
frontRearFz = (fz(:, 1) + fz(:, 2)) - (fz(:, 3) + fz(:, 4));
[preBrake, braking, brakeDetected] = ...
    localBrakeWindows(time, brake, stopTime);
metrics = struct( ...
    "sample_count", numel(time), ...
    "time_start_s", time(1), ...
    "time_end_s", time(end), ...
    "speed_rmse_mps", localRmse(speed(active) - targetSpeed(active)), ...
    "yaw_rmse_rad", localRmse(yawError(active)), ...
    "speed_mean_mps", mean(speed(active)), ...
    "target_speed_mean_mps", mean(targetSpeed(active)), ...
    "speed_final_mps", mean(speed(max(1, end - min(20, numel(speed)-1)):end)), ...
    "lateral_accel_rms_mps2", localRms(gy(active)), ...
    "longitudinal_accel_rms_mps2", localRms(gx(active)), ...
    "max_abs_roll_rad", max(abs(roll(active))), ...
    "max_abs_pitch_rad", max(abs(pitch(active))), ...
    "max_abs_yaw_rate_radps", max(abs(yawRate(active))), ...
    "peak_abs_slip_deg", max(abs(slip(active, :)), [], "all"), ...
    "slip_rms_deg", localRms(slip(active, :)), ...
    "suspension_travel_peak_m", max(abs(xShock(active, :)), [], "all"), ...
    "suspension_velocity_peak_mps", max(abs(vShock(active, :)), [], "all"), ...
    "suspension_active_fraction", ...
        mean(std(xShock(active, :), 0, 2) > 1e-5), ...
    "wheel_force_active_fraction", mean(abs(wheelForces(active, :)) > 1.0, "all"), ...
    "independent_wheel_load_fraction", mean(std(fz(active, :), 0, 2) > 5.0), ...
    "vertical_load_mean_N", mean(sum(abs(fz(active, :)), 2)), ...
    "longitudinal_force_accel_correlation", ...
        localCorrelation(sumFx(active), gx(active)), ...
    "lateral_force_accel_correlation", ...
        localCorrelation(sumFy(active), gy(active)), ...
    "lateral_load_transfer_correlation", ...
        localCorrelation(leftRightFz(active), gy(active)), ...
    "longitudinal_load_transfer_correlation", ...
        localCorrelation(frontRearFz(active), gx(active)), ...
    "steering_peak_rad", max(abs(steering(active))), ...
    "accelerator_peak", max(accelerator(active)), ...
    "brake_peak", max(brake(active)), ...
    "braking_speed_drop_mps", ...
        localBrakingSpeedDrop(speed, preBrake, braking, brakeDetected), ...
    "braking_deceleration_peak_mps2", ...
        localBrakingPeak(-gx, braking, brakeDetected), ...
    "braking_pitch_peak_rad", ...
        localBrakingPeak(abs(pitch), braking, brakeDetected), ...
    "world_distance_m", sum(hypot(diff(worldX), diff(worldY))), ...
    "event_mode", string(scenario.EventMode), ...
    "requested_speed_scale", double(scenario.SpeedScale), ...
    "requested_friction_scale", double(scenario.RoadFrictionScale), ...
    "requested_payload_mass_kg", double(scenario.PayloadMass_kg));
end

function [metrics, contract] = localExtractPublicMetrics(logs, stopTime, scenario)
vehicleSeries = localDatasetTimeseries(logs, "VehicleState", 9);
time = double(vehicleSeries.Time(:));
vehicleState = localAlign(double(vehicleSeries.Data), time);
referenceState = localSample(localDatasetTimeseries(logs, "ReferenceState", 3), time);
wheelForces = localSample(localDatasetTimeseries(logs, "WheelForces", 12), time);
slip = localSample(localDatasetTimeseries(logs, "TireSlip", 4), time);
suspensionState = localSample(localDatasetTimeseries(logs, "SuspensionState", 8), time);
driverCommands = localSample(localDatasetTimeseries(logs, "DriverCommands", 3), time);

contract = struct( ...
    "vehicle_state_9_channels", localContract(time, vehicleState, stopTime, 9), ...
    "reference_state_3_channels", localContract(time, referenceState, stopTime, 3), ...
    "wheel_forces_12_channels", localContract(time, wheelForces, stopTime, 12), ...
    "tire_slip_4_channels", localContract(time, slip, stopTime, 4), ...
    "suspension_state_8_channels", localContract(time, suspensionState, stopTime, 8), ...
    "driver_commands_3_channels", localContract(time, driverCommands, stopTime, 3));

assert(all(structfun(@logical, contract)), ...
    "SimuVerity:F90:XMECH06:PublicContract", ...
    "Candidate public Timeseries contract is incomplete.");
speed = vehicleState(:, 1);
gx = vehicleState(:, 2);
gy = vehicleState(:, 3);
roll = vehicleState(:, 4);
pitch = vehicleState(:, 5);
yaw = vehicleState(:, 6);
yawRate = vehicleState(:, 7);
worldX = vehicleState(:, 8);
worldY = vehicleState(:, 9);
targetSpeed = referenceState(:, 1);
referenceYaw = referenceState(:, 2);
fx = wheelForces(:, 1:4);
fy = wheelForces(:, 5:8);
fz = wheelForces(:, 9:12);
xShock = suspensionState(:, 1:4);
vShock = suspensionState(:, 5:8);
steering = driverCommands(:, 1);
accelerator = driverCommands(:, 2);
brake = driverCommands(:, 3);

steady = time >= min(2.0, 0.2 * stopTime);
if strcmpi(string(scenario.EventMode), "WOT_Braking")
    active = time >= 1.0;
else
    active = steady;
end
yawError = atan2(sin(yaw - referenceYaw), cos(yaw - referenceYaw));
sumFx = sum(fx, 2);
sumFy = sum(fy, 2);
leftRightFz = (fz(:, 2) + fz(:, 4)) - (fz(:, 1) + fz(:, 3));
frontRearFz = (fz(:, 1) + fz(:, 2)) - (fz(:, 3) + fz(:, 4));
[preBrake, braking, brakeDetected] = ...
    localBrakeWindows(time, brake, stopTime);
metrics = struct( ...
    "sample_count", numel(time), ...
    "time_start_s", time(1), ...
    "time_end_s", time(end), ...
    "speed_rmse_mps", localRmse(speed(active) - targetSpeed(active)), ...
    "yaw_rmse_rad", localRmse(yawError(active)), ...
    "speed_mean_mps", mean(speed(active)), ...
    "target_speed_mean_mps", mean(targetSpeed(active)), ...
    "speed_final_mps", mean(speed(max(1, end - min(20, numel(speed)-1)):end)), ...
    "lateral_accel_rms_mps2", localRms(gy(active)), ...
    "longitudinal_accel_rms_mps2", localRms(gx(active)), ...
    "max_abs_roll_rad", max(abs(roll(active))), ...
    "max_abs_pitch_rad", max(abs(pitch(active))), ...
    "max_abs_yaw_rate_radps", max(abs(yawRate(active))), ...
    "peak_abs_slip_deg", max(abs(slip(active, :)), [], "all"), ...
    "slip_rms_deg", localRms(slip(active, :)), ...
    "suspension_travel_peak_m", max(abs(xShock(active, :)), [], "all"), ...
    "suspension_velocity_peak_mps", max(abs(vShock(active, :)), [], "all"), ...
    "suspension_active_fraction", mean(std(xShock(active, :), 0, 2) > 1e-5), ...
    "wheel_force_active_fraction", mean(abs(wheelForces(active, :)) > 1.0, "all"), ...
    "independent_wheel_load_fraction", mean(std(fz(active, :), 0, 2) > 5.0), ...
    "vertical_load_mean_N", mean(sum(abs(fz(active, :)), 2)), ...
    "longitudinal_force_accel_correlation", localCorrelation(sumFx(active), gx(active)), ...
    "lateral_force_accel_correlation", localCorrelation(sumFy(active), gy(active)), ...
    "lateral_load_transfer_correlation", localCorrelation(leftRightFz(active), gy(active)), ...
    "longitudinal_load_transfer_correlation", localCorrelation(frontRearFz(active), gx(active)), ...
    "steering_peak_rad", max(abs(steering(active))), ...
    "accelerator_peak", max(accelerator(active)), ...
    "brake_peak", max(brake(active)), ...
    "braking_speed_drop_mps", ...
        localBrakingSpeedDrop(speed, preBrake, braking, brakeDetected), ...
    "braking_deceleration_peak_mps2", ...
        localBrakingPeak(-gx, braking, brakeDetected), ...
    "braking_pitch_peak_rad", ...
        localBrakingPeak(abs(pitch), braking, brakeDetected), ...
    "world_distance_m", sum(hypot(diff(worldX), diff(worldY))), ...
    "event_mode", string(scenario.EventMode), ...
    "requested_speed_scale", double(scenario.SpeedScale), ...
    "requested_friction_scale", double(scenario.RoadFrictionScale), ...
    "requested_payload_mass_kg", double(scenario.PayloadMass_kg));
end

function [preBrake, braking, detected] = ...
        localBrakeWindows(time, brake, stopTime)
% DriverCommands(:,3) is the public positive brake command in [0, 1].
time = double(time(:));
brake = double(brake(:));
peakBrake = max(brake);
activationThreshold = max(0.02, 0.10 * peakBrake);
braking = peakBrake > 0.02 & brake > activationThreshold;
detected = any(braking);
preBrake = false(size(time));
if ~detected
    return
end
firstBrake = find(braking, 1, "first");
brakeStartTime = time(firstBrake);
lookbackSeconds = max(0.5, min(2.0, 0.10 * double(stopTime)));
preBrake = time >= brakeStartTime - lookbackSeconds & ...
    time < brakeStartTime;
if ~any(preBrake) && firstBrake > 1
    preBrake(firstBrake - 1) = true;
end
if ~any(preBrake)
    preBrake(firstBrake) = true;
end
end

function value = localBrakingSpeedDrop(speed, preBrake, braking, detected)
if ~detected
    value = 0.0;
    return
end
value = max(double(speed(preBrake))) - min(double(speed(braking)));
end

function value = localBrakingPeak(signal, braking, detected)
if ~detected
    value = 0.0;
    return
end
value = max(double(signal(braking)));
end

function present = localDatasetHas(logs, name)
present = false;
try
    present = ~isempty(logs.get(char(name)));
catch
end
end

function value = localDatasetTimeseries(logs, name, width)
element = logs.get(char(name));
assert(~isempty(element), "SimuVerity:F90:XMECH06:PublicOutput", ...
    "Missing public output %s.", name);
[value, ~] = simuverity_public_output_compatibility(element, name, width);
end

function data = localResult(logs, vehicle, name, time)
result = sm_car_sim_res_get(logs, [], vehicle, char(name));
data = localAlign(result.data, time);
end

function data = localAlign(data, time)
data = double(data);
if isvector(data)
    data = data(:);
end
if size(data, 1) == numel(time)
    return;
end
source = linspace(time(1), time(end), size(data, 1))';
data = interp1(source, data, time, "linear", "extrap");
end

function data = localWheelOrder(data, labels)
wanted = ["WhlL1", "WhlR1", "WhlL2", "WhlR2"];
source = string(labels);
indices = zeros(1, 4);
for index = 1:4
    match = find(source == wanted(index), 1);
    assert(~isempty(match), "SimuVerity:F90:XMECH06:WheelOrder", ...
        "Missing wheel %s in native evidence.", wanted(index));
    indices(index) = match;
end
data = data(:, indices);
end

function data = localSample(value, time)
if isa(value, "timeseries")
    sourceTime = double(value.Time(:));
    sourceData = double(value.Data);
else
    sourceData = double(value);
    sourceTime = linspace(time(1), time(end), size(sourceData, 1))';
end
if isvector(sourceData)
    sourceData = sourceData(:);
end
if numel(sourceTime) == 1
    data = repmat(sourceData(1, :), numel(time), 1);
else
    data = interp1(sourceTime, sourceData, time, "nearest", "extrap");
end
end

function valid = localContract(time, data, stopTime, width)
valid = ~isempty(time) && time(1) <= 1e-6 && ...
    time(end) >= stopTime - 0.1 && size(data, 2) == width && ...
    all(isfinite(data), "all");
end

function value = localRmse(data)
value = sqrt(mean(double(data).^2, "all"));
end

function value = localRms(data)
value = sqrt(mean(double(data).^2, "all"));
end

function value = localCorrelation(first, second)
first = double(first(:));
second = double(second(:));
first = first - mean(first);
second = second - mean(second);
value = abs(first' * second) / max(norm(first) * norm(second), 1e-12);
value = double(value);
end

function row = localEmptyScenario
row = struct( ...
    "id", "", ...
    "requested_inputs", struct(), ...
    "simulation_pass", false, ...
    "valid", false, ...
    "simulation_wall_seconds", 0, ...
    "output_contract", struct(), ...
    "metrics", struct(), ...
    "error", struct());
end

function value = localFilePresence(path)
assert(isfile(path), "SimuVerity:FileMissing", "Required file is missing: %s", path);
value = "present";
end

function value = localNow
value = string(datetime("now", "TimeZone", "Asia/Shanghai", ...
    "Format", "yyyy-MM-dd'T'HH:mm:ssXXX"));
end

function output = localError(exception)
output = struct( ...
    "identifier", string(exception.identifier), ...
    "message", string(exception.message), ...
    "report", string(getReport(exception, "extended", "hyperlinks", "off")));
end

function localWriteJson(path, value)
fid = fopen(path, "w", "n", "UTF-8");
assert(fid >= 0, "SimuVerity:F90:XMECH06:Write");
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, "%s", jsonencode(value));
end
