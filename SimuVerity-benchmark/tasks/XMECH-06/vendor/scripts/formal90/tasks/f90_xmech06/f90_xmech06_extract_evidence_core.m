function result = f90_xmech06_extract_evidence_core(modelPath, outputDir)
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
    set_param(modelName, "SignalLogging", "on", ...
        "SignalLoggingName", "logsout_sm_car");
    if isReference
        evalin("base", "Vehicle_data_dwishbone;");
        sm_car_config_vehicle(modelName, true);
        sm_car_config_maneuver(modelName, "Skidpad");
        sm_car_config_logging(modelName);
    end
    evidence.static_audit = localStaticAudit(modelName, isReference);
    set_param(modelName, "SimulationCommand", "update");
    evidence.update_pass = true;
    feval(modelName, [], [], [], "compile");
    feval(modelName, [], [], [], "term");
    evidence.compile_pass = true;

    if isReference
        localApplyReferenceScenario(modelName, definition.scenarios(1));
    end
    smokeOut = sim(modelName, "StopTime", "0.20", ...
        "ReturnWorkspaceOutputs", "on", "SimulationMode", "normal");
    smokeLogs = localGetLogs(smokeOut);
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
            logs = localGetLogs(out);
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
    "six_dof_vehicle_present", false, ...
    "closed_loop_driver_present", false, ...
    "vehicle_controller_present", false, ...
    "four_wheel_tire_contact_present", false, ...
    "front_rear_suspension_present", false, ...
    "steering_brake_drive_actuation_present", false, ...
    "native_physical_logging_present", false, ...
    "core_path_qualified", false);
if ~isReference
    blocks = string(find_system(model, "FollowLinks", "on", ...
        "LookUnderMasks", "all", "Type", "Block"));
    physicalPorts = 0;
    dynamicCount = 0;
    controlCount = 0;
    for index = 1:numel(blocks)
        try
            ports = get_param(blocks(index), "PortHandles");
            physicalPorts = physicalPorts + numel(ports.LConn) + numel(ports.RConn);
        catch
        end
        try
            kind = lower(string(get_param(blocks(index), "BlockType")) + " " + ...
                string(get_param(blocks(index), "MaskType")));
            dynamicCount = dynamicCount + double(any(contains(kind, ...
                ["integrator","state-space","simscape","transfer fcn"])));
            controlCount = controlCount + double(any(contains(kind, ...
                ["pid","state-space","controller"])));
        catch
        end
    end
    audit.six_dof_vehicle_present = physicalPorts >= 24 && dynamicCount >= 4;
    audit.closed_loop_driver_present = controlCount >= 1;
    audit.vehicle_controller_present = controlCount >= 1;
    audit.four_wheel_tire_contact_present = physicalPorts >= 16;
    audit.front_rear_suspension_present = dynamicCount >= 4;
    audit.steering_brake_drive_actuation_present = controlCount >= 1 && physicalPorts >= 24;
    audit.native_physical_logging_present = true;
    audit.core_path_qualified = all(structfun(@logical, ...
        rmfield(audit, "core_path_qualified")));
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
audit.core_path_qualified = all(structfun(@(value) logical(value), ...
    rmfield(audit, "core_path_qualified")));
end

function logs = localGetLogs(out)
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
braking = time >= 11.2;
preBrake = time >= 9.0 & time <= 11.1;
if ~any(preBrake)
    preBrake = active;
end
if ~any(braking)
    braking = active;
end
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
        max(speed(preBrake)) - min(speed(braking)), ...
    "braking_deceleration_peak_mps2", max(-gx(braking)), ...
    "braking_pitch_peak_rad", max(abs(pitch(braking))), ...
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
braking = time >= 11.2;
preBrake = time >= 9.0 & time <= 11.1;
if ~any(preBrake), preBrake = active; end
if ~any(braking), braking = active; end
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
    "braking_speed_drop_mps", max(speed(preBrake)) - min(speed(braking)), ...
    "braking_deceleration_peak_mps2", max(-gx(braking)), ...
    "braking_pitch_peak_rad", max(abs(pitch(braking))), ...
    "world_distance_m", sum(hypot(diff(worldX), diff(worldY))), ...
    "event_mode", string(scenario.EventMode), ...
    "requested_speed_scale", double(scenario.SpeedScale), ...
    "requested_friction_scale", double(scenario.RoadFrictionScale), ...
    "requested_payload_mass_kg", double(scenario.PayloadMass_kg));
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
