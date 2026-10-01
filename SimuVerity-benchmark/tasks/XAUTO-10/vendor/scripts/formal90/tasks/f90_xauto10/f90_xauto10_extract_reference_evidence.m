function result = f90_xauto10_extract_reference_evidence(modelPath, outputDir, evaluationMode)
% Extract fixed multi-scenario evidence for F90-XAUTO-10. Scoring is offline.

repo = localProjectRoot();
taskDir = string(getenv("SIMUVERITY_TASK_ROOT"));
official = jsondecode(fileread(simuverity_official_scenarios_path()));
expectedSourceBinding = "present";
assert(nargin >= 1 && strlength(string(modelPath)) > 0, ...
    "SimuVerity:F90:XAUTO10:ModelRequired", "Public extraction requires an explicit model path.");
sourceModel = string(modelPath);
if nargin < 3 || strlength(string(evaluationMode)) == 0, evaluationMode = "reference"; end
scoringRunId = string(getenv("SIMUVERITY_SCORING_RUN_ID"));
if strlength(scoringRunId) == 0
    scoringRunId = "f90_xauto10_manual_" + string(datetime("now", "Format", "yyyyMMdd'T'HHmmss"));
end
if nargin < 2 || strlength(string(outputDir)) == 0
    outputDir = fullfile(tempdir, "SimuVerity", "F90-XAUTO-10", scoringRunId);
end
assert(~isfolder(outputDir), "SimuVerity:F90:XAUTO10:OutputExists", ...
    "Fresh evidence output already exists: %s", outputDir);
mkdir(outputDir);
diary(fullfile(outputDir, "extractor.log"));
cleanupDiary = onCleanup(@() diary("off")); %#ok<NASGU>
evidencePath = fullfile(outputDir, "evidence.json");

modelPath = string(modelPath);
sourcePresenceBefore = localFilePresence(modelPath);
isReference = lower(strtrim(string(getenv("SIMUVERITY_EVALUATION_SUBJECT")))) == "reference";
evidence = struct( ...
    "schema", "simuverity.f90-xauto10-evidence.v1", ...
    "task_id", "F90-XAUTO-10", ...
    "scoring_run_id", scoringRunId, ...
    "evaluation_subject", string(evaluationMode), ...
    "model_file_presence_before", sourcePresenceBefore, ...
    "reference_direct_golden", isReference, ...
    "runtime_changes", "Normal mode, scenario inputs, non-truncating logs, isolated cache/codegen, and evaluator-only evidence resampling", ...
    "load_pass", false, "update_pass", false, "compile_pass", false, ...
    "simulate_pass", false, "all_official_evidence_valid", false, ...
    "static_audit", struct(), "behavior_audit", struct(), ...
    "scenario_count", numel(official.scenarios), "scenarios", struct([]), ...
    "EVIDENCE_COMPLETE", false, "contains_score_decisions", false, ...
    "failure", "");
localWriteJson(evidencePath, evidence);

[modelDir, model, ~] = fileparts(modelPath);
restoredefaultpath;
closureHelperRoot = string(getenv( ...
    "SIMUVERITY_CANDIDATE_CLOSURE_HELPER_ROOT"));
if strlength(closureHelperRoot) > 0
    assert(isfolder(closureHelperRoot), ...
        "SimuVerity:F90:XAUTO10:CandidateClosureHelperMissing");
    addpath(closureHelperRoot, "-begin");
    simuverity_reload_candidate_dependencies();
end
addpath(modelDir, "-begin");
pathCleanup = onCleanup(@() localRemovePath(modelDir)); %#ok<NASGU>
scratchRoot = fullfile(outputDir, "runtime_scratch");
mkdir(scratchRoot);
cacheRoot = fullfile(scratchRoot, "cache");
codegenRoot = fullfile(scratchRoot, "codegen");
mkdir(cacheRoot); mkdir(codegenRoot);
Simulink.fileGenControl("set", "CacheFolder", cacheRoot, ...
    "CodeGenFolder", codegenRoot, "createDir", true);

try
    if isReference
        assert(strcmpi(localFilePresence(modelPath), expectedSourceBinding), ...
            "SimuVerity:F90:XAUTO10:ReferenceIdentity", "Pinned reference model file binding differs.");
    end
    load_system(modelPath);
    cleanupModel = onCleanup(@() localClose(model)); %#ok<NASGU>
    evidence.load_pass = true;
    set_param(model, "SimulationMode", "normal", ...
        "ReturnWorkspaceOutputs", "on", "LimitDataPoints", "off");
    toWs = find_system(model, "LookUnderMasks", "all", "BlockType", "ToWorkspace");
    for index = 1:numel(toWs), set_param(toWs{index}, "MaxDataPoints", "inf"); end
    set_param(model, "SimulationCommand", "update");
    evidence.update_pass = true;
    feval(model, [], [], [], "compile");
    feval(model, [], [], [], "term");
    evidence.compile_pass = true;
    evidence.static_audit = localStaticAudit(model, isReference);
    localWriteJson(evidencePath, evidence);

    rows = cell(1, numel(official.scenarios));
    suiteTimer = tic;
    for index = 1:numel(official.scenarios)
        scenario = official.scenarios(index);
        scenarioTimer = tic;
        out = localRunScenario(model, scenario, isReference, official.simulation.duration_seconds);
        if isReference
            signals = localReadReference(out, scenario, official.simulation);
        else
            signals = localReadCandidate(out, scenario, official.simulation);
        end
        contract = localOutputContract(signals, official.simulation.duration_seconds);
        assert(all(structfun(@logical, contract)), "SimuVerity:F90:XAUTO10:OutputContract", ...
            "Scenario %s violates the public output contract.", scenario.id);
        row = struct();
        row.id = string(scenario.id);
        row.inputs = rmfield(scenario, "id");
        row.time_s = signals.time_s;
        row.vehicle_motion_state = signals.vehicle_motion_state;
        row.wheel_slip_state = signals.wheel_slip_state;
        row.rear_wheel_command_state = signals.rear_wheel_command_state;
        row.output_contract = contract;
        row.metrics = localScenarioMetrics(signals);
        row.wall_seconds = toc(scenarioTimer);
        row.valid = true;
        rows{index} = row;
    end
    rows = [rows{:}];
    evidence.scenarios = rows;
    evidence.suite_wall_seconds = toc(suiteTimer);
    evidence.simulate_pass = true;
    evidence.all_official_evidence_valid = all([rows.valid]);
    evidence.behavior_audit = localBehaviorAudit(rows);
    assert(evidence.behavior_audit.all_three_axes_effective, ...
        "SimuVerity:F90:XAUTO10:InterventionAxes", "One or more required intervention axes are ineffective.");
    assert(evidence.behavior_audit.finite_operating_envelope, ...
        "SimuVerity:F90:XAUTO10:OperatingEnvelope", "A official condition enters an invalid slip or motion envelope.");
    evidence.model_file_presence_after = localFilePresence(modelPath);
    evidence.model_binding_preserved = evidence.model_file_presence_after == evidence.model_file_presence_before;
    assert(evidence.model_binding_preserved, "SimuVerity:F90:XAUTO10:ModelModified", ...
        "The evaluated model file changed during extraction.");
    evidence.EVIDENCE_COMPLETE = true;
    localWriteJson(evidencePath, evidence);
    completeEvidence = evidence; %#ok<NASGU>
    save(fullfile(outputDir, "evidence_complete.mat"), "completeEvidence", "-v7");
    result = evidence;
catch ME
    evidence.failure = string(getReport(ME, "extended", "hyperlinks", "off"));
    if isfile(modelPath)
        evidence.model_file_presence_after = localFilePresence(modelPath);
        evidence.model_binding_preserved = evidence.model_file_presence_after == evidence.model_file_presence_before;
    end
    evidence.EVIDENCE_COMPLETE = false;
    localWriteJson(evidencePath, evidence);
    localWriteJson(fullfile(outputDir, "failure_receipt.json"), evidence);
    rethrow(ME);
end
end

function out = localRunScenario(model, scenario, isReference, durationSeconds)
in = Simulink.SimulationInput(model);
in = in.setModelParameter("StopTime", num2str(durationSeconds, 17), ...
    "SimulationMode", "normal", "ReturnWorkspaceOutputs", "on", ...
    "SignalLogging", "on", "LimitDataPoints", "off");
if isReference
    in = in.setBlockParameter(model + "/steering angle (Degrees)", ...
        "Value", num2str(scenario.steering_angle_deg, 17));
    in = in.setBlockParameter(model + "/torque at rear left wheel (Nm)", ...
        "Value", num2str(scenario.rear_left_torque_nm, 17));
    in = in.setBlockParameter(model + "/torque at rear right wheel (Nm)", ...
        "Value", num2str(scenario.rear_right_torque_nm, 17));
else
    in = in.setVariable("steering_angle_deg", double(scenario.steering_angle_deg));
    in = in.setVariable("rear_left_torque_nm", double(scenario.rear_left_torque_nm));
    in = in.setVariable("rear_right_torque_nm", double(scenario.rear_right_torque_nm));
end
out = sim(in);
end

function signals = localReadReference(out, scenario, simulation)
grid = (0:double(simulation.evidence_grid_step_seconds):double(simulation.duration_seconds)).';
vx = localSeries(out, "vxout1", 1, grid, true);
vy = localSeries(out, "vyout1", 1, grid, true);
ax = localSeries(out, "axout1", 1, grid, true);
ay = localSeries(out, "ayout1", 1, grid, true);
yawRate = localSeries(out, "simout5", 1, grid, true);
yawAccel = localSeries(out, "yawout1", 1, grid, true);
desiredYaw = localSeries(out, "simout3", 1, grid, true);
longSlip = localSeries(out, "s_l_out", 4, grid, true);
latSlip = localSeries(out, "s_s_out", 4, grid, true);
combinedSlip = localSeries(out, "s_r_out", 4, grid, true);
commands = repmat([double(scenario.steering_angle_deg), ...
    double(scenario.rear_left_torque_nm), double(scenario.rear_right_torque_nm)], numel(grid), 1);
signals = struct("time_s", grid, ...
    "vehicle_motion_state", [vx vy ax ay yawRate yawAccel desiredYaw], ...
    "wheel_slip_state", [longSlip latSlip combinedSlip], ...
    "rear_wheel_command_state", commands);
end

function signals = localReadCandidate(out, scenario, simulation)
durationSeconds = double(simulation.duration_seconds);
grid = (0:double(simulation.evidence_grid_step_seconds):durationSeconds).';
vehicle = localSeries(out, "vehicle_motion_state", 7, grid, false);
slip = localSeries(out, "wheel_slip_state", 12, grid, false);
commands = localSeries(out, "rear_wheel_command_state", 3, grid, false);
assert(max(abs(commands(:,1) - double(scenario.steering_angle_deg))) <= 1e-6, ...
    "SimuVerity:F90:XAUTO10:SteeringCommand", "Logged steering command does not match the scenario input.");
assert(max(abs(commands(:,2) - double(scenario.rear_left_torque_nm))) <= 1e-6, ...
    "SimuVerity:F90:XAUTO10:LeftTorqueCommand", "Logged left torque does not match the scenario input.");
assert(max(abs(commands(:,3) - double(scenario.rear_right_torque_nm))) <= 1e-6, ...
    "SimuVerity:F90:XAUTO10:RightTorqueCommand", "Logged right torque does not match the scenario input.");
signals = struct("time_s", grid, "vehicle_motion_state", vehicle, ...
    "wheel_slip_state", slip, "rear_wheel_command_state", commands);
end

function dataGrid = localSeries(out, name, expectedWidth, grid, allowSingleSample)
try
    value = out.get(name);
catch
    error("SimuVerity:F90:XAUTO10:MissingOutput", "Required output %s is absent.", name);
end
if isa(value, "timeseries")
    t = double(value.Time(:));
    data = squeeze(double(value.Data));
elseif isstruct(value) && isfield(value, "time") && isfield(value, "signals")
    t = double(value.time(:));
    data = squeeze(double(value.signals.values));
else
    error("SimuVerity:F90:XAUTO10:OutputType", "Output %s is not a supported Timeseries.", name);
end
if isvector(data), data = data(:); end
if size(data,1) ~= numel(t) && size(data,2) == numel(t), data = data.'; end
assert(size(data,1) == numel(t) && size(data,2) == expectedWidth, ...
    "SimuVerity:F90:XAUTO10:OutputShape", "Output %s has an invalid data shape.", name);
assert(all(isfinite(t)) && all(isfinite(data(:))), ...
    "SimuVerity:F90:XAUTO10:NonfiniteOutput", "Output %s contains NaN or Inf.", name);
if numel(t) == 1 && allowSingleSample
    dataGrid = repmat(data(1,:), numel(grid), 1);
    return
end
assert(numel(t) >= 10 && all(diff(t) > 0) && t(1) <= 0.01 && t(end) >= grid(end) - 0.01, ...
    "SimuVerity:F90:XAUTO10:OutputCoverage", "Output %s does not cover the full run.", name);
[uniqueTime, uniqueIndex] = unique(t, "stable");
dataGrid = interp1(uniqueTime, data(uniqueIndex,:), grid, "linear", "extrap");
assert(all(isfinite(dataGrid(:))), "SimuVerity:F90:XAUTO10:Resample", ...
    "Output %s is nonfinite after evidence resampling.", name);
end

function contract = localOutputContract(signals, durationSeconds)
contract = struct( ...
    "time_strictly_increasing", all(diff(signals.time_s) > 0), ...
    "full_time_coverage", signals.time_s(1) <= 1e-12 && signals.time_s(end) >= durationSeconds - 1e-12, ...
    "vehicle_width_7", size(signals.vehicle_motion_state, 2) == 7, ...
    "wheel_slip_width_12", size(signals.wheel_slip_state, 2) == 12, ...
    "command_width_3", size(signals.rear_wheel_command_state, 2) == 3, ...
    "finite_vehicle", all(isfinite(signals.vehicle_motion_state(:))), ...
    "finite_wheel_slip", all(isfinite(signals.wheel_slip_state(:))), ...
    "finite_commands", all(isfinite(signals.rear_wheel_command_state(:))));
end

function metrics = localScenarioMetrics(signals)
vehicle = signals.vehicle_motion_state;
slip = signals.wheel_slip_state;
metrics = struct( ...
    "vehicle_rms", sqrt(mean(vehicle.^2, 1)), ...
    "vehicle_peak_abs", max(abs(vehicle), [], 1), ...
    "vehicle_final", vehicle(end,:), ...
    "wheel_slip_rms", sqrt(mean(slip.^2, 1)), ...
    "wheel_slip_peak_abs", max(abs(slip), [], 1), ...
    "wheel_slip_final", slip(end,:));
end

function audit = localBehaviorAudit(rows)
low = rows(1); high = rows(2); moderate = rows(3); large = rows(4);
leftBias = rows(5); rightBias = rows(6);
symTorqueDelta = abs(high.metrics.vehicle_final(1) - low.metrics.vehicle_final(1));
steeringYawDelta = abs(moderate.metrics.vehicle_final(5) - high.metrics.vehicle_final(5));
steeringLateralDelta = abs(moderate.metrics.vehicle_final(2) - high.metrics.vehicle_final(2));
largerSteerDelta = abs(large.metrics.vehicle_final(5) - moderate.metrics.vehicle_final(5));
differentialYawSeparation = abs(leftBias.metrics.vehicle_final(5) - rightBias.metrics.vehicle_final(5));
differentialRearSlipSeparation = max(abs( ...
    leftBias.metrics.wheel_slip_final(3:4) - rightBias.metrics.wheel_slip_final(3:4)));
allSlip = vertcat(rows.wheel_slip_state);
allVehicle = vertcat(rows.vehicle_motion_state);
audit = struct( ...
    "symmetric_torque_longitudinal_final_delta", symTorqueDelta, ...
    "steering_yaw_final_delta", steeringYawDelta, ...
    "steering_lateral_velocity_final_delta", steeringLateralDelta, ...
    "larger_steering_incremental_yaw_delta", largerSteerDelta, ...
    "mirrored_differential_yaw_final_separation", differentialYawSeparation, ...
    "mirrored_differential_rear_slip_final_separation", differentialRearSlipSeparation, ...
    "symmetric_torque_axis_effective", symTorqueDelta > 1e-4, ...
    "steering_axis_effective", (steeringYawDelta > 1e-4 || steeringLateralDelta > 1e-4), ...
    "differential_torque_axis_effective", (differentialYawSeparation > 1e-4 || differentialRearSlipSeparation > 1e-4), ...
    "maximum_absolute_slip", max(abs(allSlip(:))), ...
    "maximum_absolute_yaw_rate", max(abs(allVehicle(:,5))), ...
    "minimum_longitudinal_velocity", min(allVehicle(:,1)));
audit.all_three_axes_effective = audit.symmetric_torque_axis_effective && ...
    audit.steering_axis_effective && audit.differential_torque_axis_effective;
audit.finite_operating_envelope = audit.maximum_absolute_slip < 100 && ...
    audit.maximum_absolute_yaw_rate < 10 && audit.minimum_longitudinal_velocity > 0;
end

function audit = localStaticAudit(model, isReference)
blocks = find_system(model, "LookUnderMasks", "all", "FollowLinks", "on", "Type", "Block");
systems = find_system(model, "LookUnderMasks", "all", "FollowLinks", "on", "Type", "BlockDiagram");
audit = struct("block_count", numel(blocks), "system_count", numel(systems), ...
    "reference_open_loop_topology", isReference, "closed_loop_claimed", false);
if isReference
    audit.root_pi_controller_commented = string(get_param(model + "/PI Controller", "Commented")) == "on";
    audit.root_lookup_table_commented = string(get_param(model + "/Lookup table1", "Commented")) == "on";
    assert(audit.root_pi_controller_commented && audit.root_lookup_table_commented, ...
        "SimuVerity:F90:XAUTO10:InactiveBoundary", "An excluded source branch is active.");
end
end

function localWriteJson(path, value)
fid = fopen(path, "w", "n", "UTF-8");
assert(fid >= 0, "SimuVerity:F90:XAUTO10:Write", "Cannot open %s.", path);
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, "%s\n", jsonencode(value, "PrettyPrint", true));
end

function summary = localFilePresence(path)
assert(isfile(path), "SimuVerity:FileMissing", "Required file is missing: %s", path);
summary = "present";
end

function root = localProjectRoot()
root = string(fileparts(mfilename("fullpath")));
for index = 1:4, root = string(fileparts(root)); end
end

function localRemovePath(path)
try, rmpath(path); catch, end
end

function localClose(model)
try
    if bdIsLoaded(model), close_system(model, 0); end
catch
end
end
