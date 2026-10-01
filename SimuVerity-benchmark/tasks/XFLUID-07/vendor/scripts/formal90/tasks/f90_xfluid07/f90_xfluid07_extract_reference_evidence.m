function evidence = f90_xfluid07_extract_reference_evidence(referenceModel, outDir)
%F90_XFLUID07_EXTRACT_EVIDENCE Direct-golden, score-free evidence extraction.
%
% The official Tractor-Simscape project is opened at its pinned source
% version.  The evaluation adapter only exposes existing workspace inputs,
% shortens the native run in memory, and reads native logged measurements.
% The source project and model are never saved.
arguments
    referenceModel (1,1) string
    outDir (1,1) string
end

scenarioPath = string(getenv("SIMUVERITY_OFFICIAL_SCENARIOS"));
runtimeRoot = string(getenv("SIMUVERITY_RUNTIME_SUBMISSION_BUNDLE"));
assert(isfile(scenarioPath) && isfolder(runtimeRoot), ...
    "SimuVerity:F90:XFLUID07:PublicRuntime", ...
    "The evaluator-owned scenario contract and runtime bundle are required.");
official = jsondecode(fileread(scenarioPath));
assert(string(official.task_id) == "F90-XFLUID-07" && ...
    isfield(official, "scenarios") && isfield(official, "simulation"), ...
    "SimuVerity:F90:XFLUID07:ScenarioContract", ...
    "The official XFLUID-07 scenario contract is missing or changed.");
sourceRoot = fullfile(runtimeRoot, "Tractor-Simscape");
projectPath = fullfile(sourceRoot, "TractorSimscape.prj");
modelPath = fullfile(sourceRoot, "Workflow", ...
    "TransmissionTradeOffStudy", "TractorTransmissionTradeOff.slx");
inputScript = fullfile(sourceRoot, "Scripts", ...
    "TractorEnergyComputationInput.m");

generationRunId = string(getenv("SIMUVERITY_GENERATION_RUN_ID"));
if strlength(generationRunId) == 0
    generationRunId = string(getenv("SIMUVERITY_SCORING_RUN_ID"));
end
if strlength(generationRunId) == 0, generationRunId = "reference_replay"; end
assert(isfile(referenceModel) && isfile(projectPath) && ...
        isfile(modelPath) && isfile(inputScript), ...
    "SimuVerity:F90:XFLUID07:ReferenceMissing", ...
    "The pinned reference project is incomplete.");
assert(~isfolder(outDir), "SimuVerity:F90:XFLUID07:OutputReuse", ...
    "Evidence output already exists for GenerationRunId %s.", generationRunId);
mkdir(outDir);

cacheDir = string(getenv("SIMULINK_CACHE_FOLDER"));
codegenDir = string(getenv("SIMULINK_CODEGEN_FOLDER"));
assert(strlength(cacheDir) > 0 && strlength(codegenDir) > 0, ...
    "SimuVerity:F90:XFLUID07:Isolation", ...
    "Isolated Simulink cache and codegen folders are required.");
Simulink.fileGenControl("set", "CacheFolder", cacheDir, ...
    "CodeGenFolder", codegenDir, "createDir", true);
set(groot, "defaultFigureVisible", "off");

evidence = struct;
evidence.schema = "simuverity.f90-xfluid07-evidence.v1";
evidence.task_id = "F90-XFLUID-07";
evidence.reference_adapter = ...
    "direct_pinned_project_in_memory_workspace_and_logging_adapter";
evidence.source = struct( ...
    "repository", "https://github.com/simscape/Tractor-Simscape.git", ...
    "tag", "25.1.1.0", ...
    "commit", "866554b3fcbe8a01c4366790b35c007688e223ca", ...
    "main_model", ...
        "Workflow/TransmissionTradeOffStudy/TractorTransmissionTradeOff.slx", ...
    "fluid_model", "Component/Transmission/HydrostaticCVT.slx");
evidence.reference_substantive_modifications = 0;
evidence.extraction_only = true;
evidence.contains_score_decisions = false;
evidence.load_pass = false;
evidence.update_pass = false;
evidence.compile_pass = false;
evidence.scenarios = struct([]);
evidence.static_audit = struct;
evidence.errors = struct;
evidence.started_at = localNow;
evidence.runtime = struct( ...
    "generation_run_id", generationRunId, ...
    "matlab_release", string(version("-release")), ...
    "matlab_prefdir", string(getenv("MATLAB_PREFDIR")), ...
    "appdata", string(getenv("APPDATA")), ...
    "temp", string(getenv("TEMP")), ...
    "cache", cacheDir, ...
    "codegen", codegenDir, ...
    "mcp_port", string(getenv("SIMUVERITY_MCP_PORT")));

project = [];
model = "TractorTransmissionTradeOff";
artifacts = repmat(struct("id", "", "signals", struct), ...
    numel(official.scenarios), 1);
try
    project = openProject(projectPath);
    projectCleanup = onCleanup(@() localCloseProject(project)); %#ok<NASGU>
    load_system(modelPath);
    modelCleanup = onCleanup(@() localCloseModel(model)); %#ok<NASGU>
    evidence.load_pass = true;

    originalInit = string(get_param(model, "InitFcn"));
    initCleanup = onCleanup(@() localRestoreInit(model, originalInit)); %#ok<NASGU>
    set_param(model, "InitFcn", "");
    set_param(model, ...
        "StopTime", string(official.simulation.stop_time_s), ...
        "ReturnWorkspaceOutputs", "on", ...
        "SignalLogging", "on", ...
        "SignalLoggingSaveFormat", "Dataset");

    localLoadNativeInputs(inputScript);
    localApplyScenario(official.scenarios(1));
    try
        set_param(model, "SimulationCommand", "update");
        evidence.update_pass = true;
    catch ME
        evidence.errors.update = localError(ME);
    end

    if evidence.update_pass
        compiled = false;
        try
            feval(model, [], [], [], "compile");
            compiled = true;
            evidence.compile_pass = true;
        catch ME
            evidence.errors.compile = localError(ME);
        end
        if compiled
            try
                feval(model, [], [], [], "term");
            catch
            end
        end
    end

    evidence.static_audit = localStaticAudit(model);
    rows = repmat(localEmptyScenario, numel(official.scenarios), 1);
    for index = 1:numel(official.scenarios)
        scenario = official.scenarios(index);
        rows(index).id = string(scenario.id);
        rows(index).requested_inputs = rmfield(scenario, "id");
        artifacts(index).id = string(scenario.id);
        try
            localLoadNativeInputs(inputScript);
            localApplyScenario(scenario);
            simOut = sim(model, "ReturnWorkspaceOutputs", "on", ...
                "StopTime", string(official.simulation.stop_time_s));
            logs = localGetLogs(simOut);
            [signals, metrics] = localExtractNativeSignals(logs, scenario);
            rows(index).simulation_pass = true;
            rows(index).sample_count = numel(signals.time_s);
            rows(index).end_time_s = signals.time_s(end);
            rows(index).time_coverage_pass = ...
                signals.time_s(1) <= 0.05 && ...
                signals.time_s(end) >= ...
                    double(official.simulation.stop_time_s) - 0.1;
            rows(index).required_evidence_pass = ...
                rows(index).sample_count >= 20 && ...
                all(isfinite(localNumericValues(signals)));
            rows(index).valid = rows(index).time_coverage_pass && ...
                rows(index).required_evidence_pass;
            rows(index).metrics = metrics;
            artifacts(index).signals = signals;
        catch ME
            rows(index).simulation_pass = false;
            rows(index).valid = false;
            rows(index).error = localError(ME);
        end
    end
    evidence.scenarios = rows;

    rawPath = fullfile(outDir, "raw_evidence.mat");
    save(rawPath, "artifacts", "-v7.3");
    evidence.raw_artifact = struct( ...
        "path", string(rawPath), ...
        "format", "MAT-v7.3", ...
        "variable", "artifacts");
catch ME
    evidence.errors.session = localError(ME);
end

localCloseModel(model);
localCloseProject(project);
evidence.model_closed_without_save = ~bdIsLoaded(model);
evidence.finished_at = localNow;
evidencePath = fullfile(outDir, "evidence.json");
localWriteJson(evidencePath, evidence);
fprintf("F90_XFLUID07_EVIDENCE load=%d update=%d compile=%d valid=%d/%d path=%s\n", ...
    evidence.load_pass, evidence.update_pass, evidence.compile_pass, ...
    localValidCount(evidence.scenarios), numel(evidence.scenarios), ...
    evidencePath);
end

function localLoadNativeInputs(inputScript)
escaped = replace(string(inputScript), "'", "''");
evalin("base", "run('" + escaped + "')");
end

function localApplyScenario(scenario)
implement = evalin("base", "implement");
tire = evalin("base", "tire");
engine = evalin("base", "engine");

distanceBreakpoints = double(scenario.distance_breakpoints_m(:))';
targetVelocity = double(scenario.target_velocity_kph(:))';
assert(numel(distanceBreakpoints) == numel(targetVelocity) && ...
    all(diff(distanceBreakpoints) > 0), ...
    "SimuVerity:F90:XFLUID07:SpeedProfile", ...
    "Distance and target-speed vectors must have equal length and increasing distance.");
implement.depth3Tillage = double(scenario.implement_depth_cm);
tire.tc = double(scenario.soil_cohesion_kpa);
tire.inflationPressure = double(scenario.tire_inflation_kpa);
engine.upperLimit = double(scenario.engine_speed_rpm);

assignin("base", "implement", implement);
assignin("base", "tire", tire);
assignin("base", "engine", engine);
assignin("base", "distanceVector", distanceBreakpoints);
assignin("base", "targetVelocityVector", targetVelocity);
assignin("base", "distance_breakpoints_m", distanceBreakpoints);
assignin("base", "target_velocity_kph", targetVelocity);
assignin("base", "engine_speed_rpm", double(scenario.engine_speed_rpm));
assignin("base", "implement_depth_cm", double(scenario.implement_depth_cm));
assignin("base", "soil_cohesion_kpa", double(scenario.soil_cohesion_kpa));
assignin("base", "tire_inflation_kpa", double(scenario.tire_inflation_kpa));
end

function logs = localGetLogs(simOut)
logs = [];
names = string(simOut.who);
preferred = ["logsoutTractorTransmissionTradeOff", "logsout"];
for key = preferred
    if any(names == key)
        logs = simOut.get(key);
        break
    end
end
if isempty(logs)
    for key = preferred
        try
            logs = evalin("base", key);
            if ~isempty(logs), break; end
        catch
        end
    end
end
assert(~isempty(logs) && numElements(logs) >= 1, ...
    "SimuVerity:F90:XFLUID07:LogsMissing", ...
    "The native logged bus was not returned.");
end

function [signals, metrics] = localExtractNativeSignals(logs, scenario)
values = logs{1}.Values;
engine = localSeries(values, ["Engine", "engineSpeed"]);
pumpDisp = localSeries(values, ["Pump_Displacement"]);
pumpTorque = localSeries(values, ...
    ["Transmission", "Main_Pump", "trq__N_m_"]);
pumpFlow = localSeries(values, ...
    ["Transmission", "Main_Pump", "q__m_3_s_"]);
frontSpeed = localSeries(values, ...
    ["Transmission", "Front_Motor", "w__rpm_"]);
frontTorque = localSeries(values, ...
    ["Transmission", "Front_Motor", "trq__N_m_"]);
frontFlow = localSeries(values, ...
    ["Transmission", "Front_Motor", "q__m_3_s_"]);
rearSpeed = localSeries(values, ...
    ["Transmission", "Rear_Motor", "w__rpm_"]);
rearTorque = localSeries(values, ...
    ["Transmission", "Rear_Motor", "trq__N_m_"]);
rearFlow = localSeries(values, ...
    ["Transmission", "Rear_Motor", "q__m_3_s_"]);
pA1 = localSeries(values, ["Transmission", "Pipe_A", "pA__bar_"]);
pB1 = localSeries(values, ["Transmission", "Pipe_A", "pB__bar_"]);
pA2 = localSeries(values, ["Transmission", "Pipe_B", "pA__bar_"]);
pB2 = localSeries(values, ["Transmission", "Pipe_B", "pB__bar_"]);
tractorSpeed = localSeries(values, ["Tractor_Velocity"]);
implementDepth = localSeries(values, ...
    ["Controller", "Implement_Depth_Command"]);

t = double(engine.time(:));
assert(numel(t) >= 20, "SimuVerity:F90:XFLUID07:Samples", ...
    "The native log has insufficient samples.");
interp = @(series) localInterp(series, t);
engineRpm = interp(engine);
pumpDispValue = interp(pumpDisp);
pumpTorqueValue = interp(pumpTorque);
pumpFlowValue = interp(pumpFlow);
frontSpeedValue = interp(frontSpeed);
frontTorqueValue = interp(frontTorque);
frontFlowValue = interp(frontFlow);
rearSpeedValue = interp(rearSpeed);
rearTorqueValue = interp(rearTorque);
rearFlowValue = interp(rearFlow);
pressureMatrix = [interp(pA1), interp(pB1), interp(pA2), interp(pB2)];
loopHighPressure = max(pressureMatrix, [], 2);
tractorSpeedKph = interp(tractorSpeed);
tractorSpeedMps = tractorSpeedKph / 3.6;
implementDepthValue = interp(implementDepth);
distanceM = cumtrapz(t, max(tractorSpeedMps, 0));
breakpoints = double(scenario.distance_breakpoints_m(:));
targetVectorKph = double(scenario.target_velocity_kph(:));
profileTime = min(max(t, 2), 12);
profileDistance = 0.0694 * profileTime.^2 - ...
    0.2083 * profileTime + 0.1389 + ...
    max(t - 12, 0) * (5 * 1000 / 3600);
queryDistance = min(max(profileDistance, breakpoints(1)), breakpoints(end));
targetSpeedKph = interp1(breakpoints, targetVectorKph, queryDistance, ...
    "linear", "extrap");
targetSpeedMps = targetSpeedKph / 3.6;

signals = struct;
signals.time_s = t;
signals.speed_control = [targetSpeedKph, tractorSpeedKph, pumpDispValue];
signals.hydraulic_state = [loopHighPressure, pumpFlowValue, ...
    frontSpeedValue, rearSpeedValue];
signals.drivetrain_effort = [engineRpm, pumpTorqueValue, ...
    frontTorqueValue, rearTorqueValue];
signals.adapter_auxiliary = [distanceM, implementDepthValue, ...
    frontFlowValue, rearFlowValue];

late = t >= max(t(end) - 15, 0.8 * t(end));
assert(nnz(late) >= 5, "SimuVerity:F90:XFLUID07:LateWindow", ...
    "The native log has insufficient late-window samples.");
tracking = t >= min(5, 0.05 * t(end)) & targetSpeedMps >= 0.2;
assert(nnz(tracking) >= 10, "SimuVerity:F90:XFLUID07:TrackingWindow", ...
    "The native log has insufficient commanded-motion samples.");
trackingError = tractorSpeedMps - targetSpeedMps;
trackingRmse = sqrt(mean(trackingError(tracking).^2));
trackingMae = mean(abs(trackingError(tracking)));
trackingNrmse = trackingRmse / ...
    max(sqrt(mean(targetSpeedMps(tracking).^2)), 0.5);
trackingR2 = 1 - sum(trackingError(tracking).^2) / ...
    max(sum((targetSpeedMps(tracking) - ...
    mean(targetSpeedMps(tracking))).^2), eps);
vehicleFinal = median(tractorSpeedMps(late));
targetFinal = median(targetSpeedMps(late));
engineFinal = median(engineRpm(late));
pumpDispFinal = median(pumpDispValue(late));
frontSpeedFinal = median(frontSpeedValue(late));
rearSpeedFinal = median(rearSpeedValue(late));
frontTorqueRms = sqrt(mean(frontTorqueValue(late).^2));
rearTorqueRms = sqrt(mean(rearTorqueValue(late).^2));
frontFlowRms = sqrt(mean(frontFlowValue(late).^2));
rearFlowRms = sqrt(mean(rearFlowValue(late).^2));
pressureMax = max(loopHighPressure);
inputPowerKw = abs(engineRpm * (2*pi/60) .* pumpTorqueValue) / 1000;
frontPowerKw = abs(frontSpeedValue * (2*pi/60) .* frontTorqueValue) / 1000;
rearPowerKw = abs(rearSpeedValue * (2*pi/60) .* rearTorqueValue) / 1000;
outputPowerKw = frontPowerKw + rearPowerKw;
lateInputPower = mean(inputPowerKw(late));
lateOutputPower = mean(outputPowerKw(late));
efficiency = lateOutputPower / max(lateInputPower, eps);
lossPowerKw = max(lateInputPower - lateOutputPower, 0);
riseTime = localRiseTime(t, abs(tractorSpeedMps), ...
    0.90 * max(abs(targetFinal), eps));
settlingTime = localSettlingTime(t, targetSpeedMps, ...
    tractorSpeedMps, 0.08);
lateTrackingRmse = sqrt(mean(trackingError(late).^2));
lateVehicleCv = std(tractorSpeedMps(late)) / ...
    max(abs(mean(tractorSpeedMps(late))), 1e-6);
axleSpeedMismatch = abs(frontSpeedFinal - rearSpeedFinal) / ...
    max(max(abs([frontSpeedFinal rearSpeedFinal])), 1e-6);
axleTorqueMismatch = abs(frontTorqueRms - rearTorqueRms) / ...
    max(max(abs([frontTorqueRms rearTorqueRms])), 1e-6);
axleFlowMismatch = abs(frontFlowRms - rearFlowRms) / ...
    max(max(abs([frontFlowRms rearFlowRms])), 1e-9);
pressureRipple = std(loopHighPressure(late)) / ...
    max(abs(mean(loopHighPressure(late))), 1e-6);
pumpRange = max(pumpDispValue) - min(pumpDispValue);
pumpSaturationFraction = mean(pumpDispValue <= 10.5 | ...
    pumpDispValue >= 56.5);
errorPumpCorrelation = localAbsCorrelation( ...
    targetSpeedMps(tracking) - tractorSpeedMps(tracking), ...
    pumpDispValue(tracking));
pressureTorqueCorrelation = localAbsCorrelation( ...
    loopHighPressure(tracking), abs(pumpTorqueValue(tracking)));

metrics = struct( ...
    "requested_profile_max_mps", max(targetVectorKph) / 3.6, ...
    "requested_profile_final_mps", targetVectorKph(end) / 3.6, ...
    "requested_engine_speed_rpm", double(scenario.engine_speed_rpm), ...
    "requested_implement_depth_cm", double(scenario.implement_depth_cm), ...
    "requested_soil_cohesion_kpa", ...
        double(scenario.soil_cohesion_kpa), ...
    "requested_tire_inflation_kpa", ...
        double(scenario.tire_inflation_kpa), ...
    "final_target_speed_mps", targetFinal, ...
    "final_tractor_speed_mps", vehicleFinal, ...
    "tracking_rmse_mps", trackingRmse, ...
    "tracking_mae_mps", trackingMae, ...
    "tracking_normalized_rmse", trackingNrmse, ...
    "tracking_r2", trackingR2, ...
    "maximum_absolute_tracking_error_mps", ...
        max(abs(trackingError(tracking))), ...
    "late_tracking_rmse_mps", lateTrackingRmse, ...
    "final_tracking_relative_error", ...
        abs(vehicleFinal - targetFinal) / max(abs(targetFinal), 0.5), ...
    "final_engine_speed_rpm", engineFinal, ...
    "final_pump_displacement_cm3_rev", pumpDispFinal, ...
    "final_implement_depth_cm", median(implementDepthValue(late)), ...
    "minimum_tractor_speed_mps", min(tractorSpeedMps), ...
    "maximum_loop_pressure_bar", pressureMax, ...
    "late_pressure_ripple_fraction", pressureRipple, ...
    "late_mean_input_power_kw", lateInputPower, ...
    "late_mean_output_power_kw", lateOutputPower, ...
    "late_transmission_loss_kw", lossPowerKw, ...
    "late_energy_efficiency", efficiency, ...
    "front_motor_speed_rpm", frontSpeedFinal, ...
    "rear_motor_speed_rpm", rearSpeedFinal, ...
    "front_motor_torque_rms_nm", frontTorqueRms, ...
    "rear_motor_torque_rms_nm", rearTorqueRms, ...
    "front_motor_flow_rms_m3_s", frontFlowRms, ...
    "rear_motor_flow_rms_m3_s", rearFlowRms, ...
    "axle_speed_relative_mismatch", axleSpeedMismatch, ...
    "axle_torque_relative_mismatch", axleTorqueMismatch, ...
    "axle_flow_relative_mismatch", axleFlowMismatch, ...
    "cold_start_rise_time_s", riseTime, ...
    "final_command_settling_time_s", settlingTime, ...
    "late_vehicle_speed_cv", lateVehicleCv, ...
    "negative_vehicle_speed_fraction", mean(tractorSpeedMps < -0.02), ...
    "pump_displacement_range_cm3_rev", pumpRange, ...
    "pump_saturation_fraction", pumpSaturationFraction, ...
    "error_to_pump_abs_correlation", errorPumpCorrelation, ...
    "pressure_to_pump_torque_abs_correlation", ...
        pressureTorqueCorrelation, ...
    "finite_fraction", mean(isfinite([signals.speed_control, ...
        signals.hydraulic_state, signals.drivetrain_effort, ...
        signals.adapter_auxiliary]), "all"));
end

function series = localSeries(root, tokens)
value = root;
for index = 1:numel(tokens)
    value = localField(value, tokens(index));
end
assert(isa(value, "timeseries"), "SimuVerity:F90:XFLUID07:SignalType", ...
    "Native signal %s is not a timeseries.", strjoin(tokens, "."));
data = squeeze(double(value.Data));
if size(data, 2) > 1
    data = data(:,1);
end
series = struct("time", double(value.Time(:)), "data", data(:));
end

function value = localField(parent, requested)
names = string(fieldnames(parent));
target = localNorm(requested);
normal = arrayfun(@localNorm, names);
match = find(normal == target, 1);
if isempty(match)
    match = find(contains(normal, target) | contains(target, normal), 1);
end
assert(~isempty(match), "SimuVerity:F90:XFLUID07:NativeFieldMissing", ...
    "Native field %s was not found among [%s].", ...
    requested, strjoin(names, ", "));
value = parent.(char(names(match)));
end

function value = localNorm(text)
value = lower(regexprep(string(text), "[^a-zA-Z0-9]", ""));
end

function values = localInterp(series, time)
[uniqueTime, uniqueIndex] = unique(series.time, "stable");
uniqueData = series.data(uniqueIndex);
if numel(uniqueTime) == 1
    values = repmat(uniqueData, numel(time), 1);
else
    values = interp1(uniqueTime, uniqueData, time, "linear", "extrap");
end
values = double(values(:));
end

function rise = localRiseTime(time, values, threshold)
hit = find(values >= threshold, 1, "first");
if isempty(hit)
    rise = time(end);
else
    rise = time(hit);
end
end

function settling = localSettlingTime(time, target, measured, toleranceFraction)
finalTarget = median(target(time >= max(time(end) - 15, 0.8 * time(end))));
start = find(target >= 0.95 * max(finalTarget, eps), 1, "first");
if isempty(start)
    settling = time(end);
    return;
end
tolerance = toleranceFraction * max(abs(finalTarget), 0.5);
outside = find(abs(measured(start:end) - target(start:end)) > tolerance);
if isempty(outside)
    settling = 0;
else
    lastOutside = start + outside(end) - 1;
    if lastOutside >= numel(time)
        settling = time(end) - time(start);
    else
        settling = time(lastOutside + 1) - time(start);
    end
end
end

function value = localAbsCorrelation(left, right)
left = double(left(:));
right = double(right(:));
valid = isfinite(left) & isfinite(right);
left = left(valid);
right = right(valid);
if numel(left) < 5 || std(left) <= eps || std(right) <= eps
    value = 0;
    return;
end
matrix = corrcoef(left, right);
value = abs(matrix(1,2));
end

function values = localNumericValues(signals)
values = [signals.time_s(:); signals.speed_control(:); ...
    signals.hydraulic_state(:); signals.drivetrain_effort(:); ...
    signals.adapter_auxiliary(:)];
end

function audit = localStaticAudit(model)
blocks = string(find_system(model, "FollowLinks", "on", ...
    "LookUnderMasks", "all", "Type", "Block"));
text = lower(blocks);
audit = struct;
audit.block_count = numel(blocks);
audit.hydrostatic_cvt_count = sum(contains(text, "hydrostatic cvt"));
audit.pump_path_count = sum(contains(text, "pump"));
audit.motor_path_count = sum(contains(text, "motor"));
audit.pressure_protection_count = sum(contains(text, "relief") | ...
    contains(text, "check valve"));
audit.pipe_path_count = sum(contains(text, "pipe"));
audit.tire_path_count = sum(contains(text, "tire"));
audit.implement_path_count = sum(contains(text, "implement"));
audit.vehicle_body_path_count = sum(contains(text, "vehicle body") | ...
    contains(text, "tractor body"));
audit.target_velocity_count = sum(contains(text, "target velocity"));
audit.speed_feedback_count = sum(contains(text, "tractor vel"));
audit.cvt_controller_count = sum(contains(text, "cvt control"));
audit.pump_displacement_command_count = ...
    sum(contains(text, "pump displacement"));
audit.front_drive_signature = any(contains(text, "front motor")) && ...
    any(contains(text, "front axle"));
audit.rear_drive_signature = any(contains(text, "rear motor")) && ...
    any(contains(text, "rear axle"));
audit.causal_hydro_mechanical_signature = ...
    audit.hydrostatic_cvt_count >= 1 && ...
    audit.pump_path_count >= 2 && audit.motor_path_count >= 2 && ...
    audit.pressure_protection_count >= 2 && ...
    audit.front_drive_signature && audit.rear_drive_signature && ...
    audit.tire_path_count >= 4 && audit.implement_path_count >= 1 && ...
    audit.vehicle_body_path_count >= 1;
audit.closed_loop_speed_control_signature = ...
    audit.target_velocity_count >= 1 && ...
    audit.speed_feedback_count >= 1 && ...
    audit.cvt_controller_count >= 1 && ...
    audit.pump_displacement_command_count >= 1 && ...
    audit.causal_hydro_mechanical_signature;
audit.required_products = ["Simulink", "Simscape", ...
    "Simscape Driveline", "Simscape Fluids"];
products = ver;
installed = string({products.Name});
audit.required_products_available = all(ismember( ...
    audit.required_products, installed));
end

function count = localValidCount(rows)
if isempty(rows) || ~isfield(rows, "valid")
    count = 0;
else
    count = sum([rows.valid]);
end
end

function row = localEmptyScenario
row = struct( ...
    "id", "", ...
    "requested_inputs", struct, ...
    "simulation_pass", false, ...
    "time_coverage_pass", false, ...
    "required_evidence_pass", false, ...
    "valid", false, ...
    "sample_count", 0, ...
    "end_time_s", 0, ...
    "metrics", struct, ...
    "error", struct);
end

function localRestoreInit(model, originalInit)
try
    if bdIsLoaded(model)
        set_param(model, "InitFcn", originalInit);
    end
catch
end
end

function localCloseModel(model)
try
    if bdIsLoaded(model)
        close_system(model, 0);
    end
catch
end
end

function localCloseProject(project)
try
    if ~isempty(project)
        close(project);
    end
catch
end
end

function payload = localError(ME)
payload = struct( ...
    "identifier", string(ME.identifier), ...
    "message", string(ME.message));
end

function value = localNow
value = string(datetime("now", "TimeZone", "Asia/Shanghai", ...
    "Format", "yyyy-MM-dd'T'HH:mm:ssXXX"));
end

function localWriteJson(path, payload)
text = jsonencode(payload, "PrettyPrint", true);
fid = fopen(path, "w", "n", "UTF-8");
assert(fid >= 0, "SimuVerity:F90:XFLUID07:Write", "Cannot write %s.", path);
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, "%s\n", text);
end
