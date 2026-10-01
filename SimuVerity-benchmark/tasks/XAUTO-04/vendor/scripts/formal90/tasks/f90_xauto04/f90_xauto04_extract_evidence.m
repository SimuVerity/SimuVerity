function evidence = f90_xauto04_extract_evidence(modelPath, outDir)
%F90_XAUTO04_EXTRACT_EVIDENCE Extract score-free evidence in one session.
% The exact MathWorks source is observed through unsaved logging taps. Agent
% models are observed only through the four public Timeseries outputs.
arguments
    modelPath (1,1) string = ""
    outDir (1,1) string = ""
end

def = f90_xauto04_definition;
wallClock = tic;
root = localProjectRoot;
official = jsondecode(fileread(def.official_scenarios));
generationRunId = string(getenv("SIMUVERITY_GENERATION_RUN_ID"));
assert(strlength(generationRunId) > 0, "SimuVerity:F90:XAUTO04:GenerationRunId", ...
    "SIMUVERITY_GENERATION_RUN_ID is required.");
if strlength(modelPath) == 0, modelPath = def.reference_model; end
assert(isfile(modelPath), "SimuVerity:F90:XAUTO04:ModelMissing", ...
    "Model is missing: %s", modelPath);
if strlength(outDir) == 0
    outDir = fullfile(root, "results", "cross_domain", ...
        "simuverity_public", def.formal_id, "fixed_evidence", generationRunId);
end
assert(~isfolder(outDir), "SimuVerity:F90:XAUTO04:OutputReuse", ...
    "Output directory already exists: %s", outDir);
mkdir(outDir);

cacheDir = string(getenv("SIMULINK_CACHE_FOLDER"));
codegenDir = string(getenv("SIMULINK_CODEGEN_FOLDER"));
assert(strlength(cacheDir) > 0 && strlength(codegenDir) > 0, ...
    "SimuVerity:F90:XAUTO04:Isolation", ...
    "SIMULINK_CACHE_FOLDER and SIMULINK_CODEGEN_FOLDER are required.");
Simulink.fileGenControl("set", "CacheFolder", cacheDir, ...
    "CodeGenFolder", codegenDir, "createDir", true);
set(groot, "defaultFigureVisible", "off");

bindingBefore = localFilePresence(modelPath);
isReference = lower(strtrim(string(getenv("SIMUVERITY_EVALUATION_SUBJECT")))) == "reference";
evidence = localEmptyEvidence(def, modelPath, bindingBefore, isReference, ...
    generationRunId, cacheDir, codegenDir);
scenarioArtifacts = repmat(struct( ...
    "id", "", "time_s", [], "VehicleState", [], ...
    "WheelState", [], "BrakeState", [], "TireForceState", []), ...
    numel(official.scenarios), 1);
rows = repmat(localEmptyScenario, numel(official.scenarios), 1);

oldPath = path;
oldDir = string(pwd);
restore = onCleanup(@() localRestore(oldPath, oldDir)); %#ok<NASGU>
project = [];
model = "";
fatal = [];
try
    if isReference
        % The importer provides the full official BrakingTest project.  Its
        % location is evaluator-owned, so recover it from the exact model
        % being evaluated rather than the non-redistributed predecessor path.
        referenceProjectRoot = fileparts(fileparts(modelPath));
        project = openProject(referenceProjectRoot);
        % Project startup selects its bundled Work folder; restore the
        % evaluator-owned short cache paths before loading referenced models.
        Simulink.fileGenControl("set", "CacheFolder", cacheDir, ...
            "CodeGenFolder", codegenDir, "createDir", true);
        load_system(modelPath);
        model = "BTReferenceApplication";
    else
        [modelDir, modelStem] = fileparts(modelPath);
        addpath(modelDir, "-begin");
        load_system(modelPath);
        model = string(modelStem);
    end
    evidence.load_pass = true;
    modelCleanup = onCleanup(@() localCloseModel(model)); %#ok<NASGU>
    set_param(model, "ReturnWorkspaceOutputs", "on", ...
        "SignalLogging", "on", "LimitDataPoints", "off", ...
        "StopTime", string(official.simulation.stop_s));

    if isReference
        localDisableVisualization(model);
        localAttachReferenceTaps(model);
    end
    localApplyScenario(model, official.scenarios(1), isReference);
    evidence.static_audit = localStaticAudit(model, isReference);
    set_param(model, "SimulationCommand", "update");
    evidence.update_pass = true;
    evidence.compile_method = ...
        "accelerator-compatible SimulationCommand update";
    evidence.compile_pass = true;

    for index = 1:numel(official.scenarios)
        scenario = official.scenarios(index);
        rows(index).id = string(scenario.id);
        rows(index).class = string(scenario.class);
        rows(index).requested_inputs = localRequestedInputs(scenario);
        scenarioArtifacts(index).id = string(scenario.id);
        try
            localApplyScenario(model, scenario, isReference);
            localClearOutputVariables;
            simOut = sim(model, ...
                "StartTime", string(official.simulation.start_s), ...
                "StopTime", string(official.simulation.stop_s), ...
                "SimulationMode", string(official.simulation.simulation_mode), ...
                "ReturnWorkspaceOutputs", "on", ...
                "SignalLogging", "on", ...
                "LimitDataPoints", "off");
            if isReference
                signals = localReferenceSignals(simOut);
            else
                signals = localCandidateSignals(simOut);
            end
            rows(index).simulation_pass = true;
            rows(index).sample_count = numel(signals.time_s);
            rows(index).end_time_s = signals.time_s(end);
            rows(index).time_coverage_pass = ...
                signals.time_s(1) <= 0.05 && ...
                signals.time_s(end) >= double(official.simulation.stop_s) - 0.05;
            rows(index).required_evidence_pass = localSignalsValid(signals);
            rows(index).valid = rows(index).time_coverage_pass && ...
                rows(index).required_evidence_pass;
            rows(index).metrics = localMetrics(signals, scenario);
            scenarioArtifacts(index) = localArtifact(string(scenario.id), signals);
        catch ME
            rows(index).error = localError(ME);
        end
    end
    evidence.scenarios = rows;
    rawPath = fullfile(outDir, "raw_evidence.mat");
    save(rawPath, "scenarioArtifacts", "-v7.3");
    evidence.raw_artifact = struct( ...
        "path", string(rawPath), "format", "MAT-v7.3", ...
        "variable", "scenarioArtifacts");
catch ME
    fatal = ME;
    evidence.errors = localError(ME);
    try, feval(model, [], [], [], "term"); catch, end
end

try
    if strlength(model) > 0 && bdIsLoaded(model)
        close_system(model, 0);
        evidence.model_closed_without_save = true;
    end
catch ME
    evidence.model_close_error = localError(ME);
end
try
    if ~isempty(project), close(project); end
catch ME
    evidence.project_close_error = localError(ME);
end
evidence.reference_binding_preserved = ...
    (~isReference) || localFilePresence(modelPath) == bindingBefore;
evidence.finished_at = localNow;
evidence.runtime.wall_clock_s = toc(wallClock);
evidencePath = fullfile(outDir, "evidence.json");
localWriteJson(evidencePath, evidence);
if ~isempty(fatal), rethrow(fatal); end
end

function evidence = localEmptyEvidence(def, modelPath, modelBinding, ...
        isReference, generationRunId, cacheDir, codegenDir)
evidence = struct;
evidence.schema = "simuverity.f90-xauto04-evidence.v1";
evidence.task_id = def.formal_id;
evidence.generation_run_id = generationRunId;
evidence.model_path = modelPath;
evidence.model_file_presence = modelBinding;
evidence.reference_subject = logical(isReference);
evidence.adapter = localTernary(isReference, ...
    "native_vehicle_feedback_bus_unsaved_taps", ...
    "public_timeseries_contract");
evidence.reference_substantive_modifications = 0;
evidence.extraction_only = true;
evidence.contains_score_decisions = false;
evidence.load_pass = false;
evidence.update_pass = false;
evidence.compile_pass = false;
evidence.static_audit = struct;
evidence.scenarios = struct([]);
evidence.errors = struct;
evidence.model_closed_without_save = false;
evidence.reference_binding_preserved = false;
evidence.started_at = localNow;
evidence.runtime = struct( ...
    "matlab_start_count", 1, ...
    "generation_run_id", generationRunId, ...
    "one_session_all_scenarios", true, ...
    "matlab_release", string(version("-release")), ...
    "matlab_prefdir", string(getenv("MATLAB_PREFDIR")), ...
    "appdata", string(getenv("APPDATA")), ...
    "temp", string(getenv("TEMP")), ...
    "cache", cacheDir, ...
    "codegen", codegenDir, ...
    "mcp_port", string(getenv("SIMUVERITY_MCP_PORT")));
end

function localApplyScenario(model, scenario, isReference)
inputs = localRequestedInputs(scenario);
names = fieldnames(inputs);
for index = 1:numel(names)
    assignin("base", names{index}, inputs.(names{index}));
end
if ~isReference, return; end

generator = model + "/Straight Maneuver Reference Generator";
assert(getSimulinkBlockHandle(generator, false) > 0, ...
    "SimuVerity:F90:XAUTO04:ReferenceGenerator", ...
    "The native straight-maneuver reference generator is missing.");
set_param(generator, ...
    "xdot_r", localNumber(scenario.TargetSpeed_mps), ...
    "brakingParam", "Longitudinal displacement", ...
    "x_brake", localNumber(scenario.BrakeStartDistance_m), ...
    "ax_dec", localNumber(scenario.RequestedDeceleration_g));

environment = model + "/Environment/Road Track Friction";
patch = double(scenario.LowFrictionPatch_m(:).');
if logical(scenario.UseLowFrictionPatch)
    set_param(environment, ...
        "surface_popup", "Split friction coefficient scaling factor", ...
        "lambda_g", localNumber(scenario.RoadFrictionScaleHigh), ...
        "lambda_r", localNumber(scenario.RoadFrictionScaleLow), ...
        "r_x0", localNumber(patch(1)), ...
        "r_y0", localNumber(patch(2)), ...
        "r_xw", localNumber(patch(3)), ...
        "r_yw", localNumber(patch(4)));
else
    set_param(environment, ...
        "surface_popup", "Constant friction coefficient scaling factor", ...
        "lambda_g", localNumber(scenario.RoadFrictionScaleHigh));
end
end

function requested = localRequestedInputs(scenario)
requested = struct( ...
    "TargetSpeed_mps", double(scenario.TargetSpeed_mps), ...
    "BrakeStartDistance_m", double(scenario.BrakeStartDistance_m), ...
    "RequestedDeceleration_g", ...
        double(scenario.RequestedDeceleration_g), ...
    "RoadFrictionScaleHigh", double(scenario.RoadFrictionScaleHigh), ...
    "RoadFrictionScaleLow", double(scenario.RoadFrictionScaleLow), ...
    "UseLowFrictionPatch", logical(scenario.UseLowFrictionPatch), ...
    "LowFrictionPatch_m", double(scenario.LowFrictionPatch_m(:).'));
end

function localDisableVisualization(model)
paths = [
    model + "/Visualization/Vehicle XY Plotter"
    model + "/Visualization/Yaw Rate, Brake Pressure, Velocity, Lat Accel"
];
for index = 1:numel(paths)
    if getSimulinkBlockHandle(paths(index), false) > 0
        set_param(paths(index), "Commented", "on");
    end
end
end

function localAttachReferenceTaps(model)
vis = model + "/Visualization";
selector = vis + "/__F90_XAUTO04_EvidenceSelector";
assert(getSimulinkBlockHandle(selector, false) < 0, ...
    "SimuVerity:F90:XAUTO04:TapCollision", ...
    "The unsaved evidence-selector name already exists.");
elements = [
    "Body.InertFrm.Cg.Disp.X"
    "Body.InertFrm.Cg.Disp.Y"
    "Body.BdyFrm.Cg.Vel.xdot"
    "Body.BdyFrm.Cg.Vel.ydot"
    "Body.BdyFrm.Cg.Acc.ax"
    "Body.BdyFrm.Cg.Acc.ay"
    "Body.InertFrm.Cg.Ang.psi"
    "Body.BdyFrm.Cg.AngVel.r"
    "Wheels.TireFrame.Omega"
    "Wheels.TireFrame.Re"
    "Wheels.TireFrame.Kappa"
    "Cntrl.Brake.BrkPrsCmd"
    "Driveline.BrkPrs"
    "Cntrl.Brake.ABSFlag"
    "Wheels.TireFrame.Fx"
    "Wheels.TireFrame.Fy"
];
add_block("simulink/Signal Routing/Bus Selector", selector, ...
    "OutputSignals", strjoin(elements, ","), ...
    "Position", [1750, -200, 1755, 440]);
source = vis + "/Bus Element In2";
sourcePorts = get_param(source, "PortHandles");
selectorPorts = get_param(selector, "PortHandles");
add_line(vis, sourcePorts.Outport(1), selectorPorts.Inport(1), ...
    "autorouting", "on");
for index = 1:numel(elements)
    variable = sprintf("F90_XAUTO04_Tap_%02d", index);
    sink = vis + "/" + variable;
    y = -200 + 40 * (index - 1);
    add_block("simulink/Sinks/To Workspace", sink, ...
        "VariableName", variable, ...
        "SaveFormat", "Timeseries", ...
        "MaxDataPoints", "inf", ...
        "Position", [1840, y, 1950, y + 24]);
    sinkPorts = get_param(sink, "PortHandles");
    add_line(vis, selectorPorts.Outport(index), sinkPorts.Inport(1), ...
        "autorouting", "on");
end
end

function audit = localStaticAudit(model, isReference)
audit = struct;
audit.reference_exact_source = logical(isReference);
audit.active_abs_choice = "";
audit.active_vehicle_choice = "";
if isReference
    absPath = model + "/Controllers/Brake Pressure Control";
    vehiclePath = model + ...
        "/Passenger Vehicle/Body, Suspension, Wheels";
    audit.active_abs_choice = string( ...
        get_param(absPath, "LabelModeActiveChoice"));
    audit.active_vehicle_choice = string( ...
        get_param(vehiclePath, "LabelModeActiveChoice"));
    audit.active_four_channel_abs = ...
        audit.active_abs_choice == "2";
    audit.active_passveh14dof = ...
        audit.active_vehicle_choice == "3";
    audit.full_vehicle_mechanism = audit.active_passveh14dof;
    audit.closed_loop_four_channel_mechanism = ...
        audit.active_four_channel_abs;
    audit.spatial_friction_mechanism = ...
        getSimulinkBlockHandle(model + "/Environment", false) > 0;
else
    blocks = find_system(model, "LookUnderMasks", "all", ...
        "FollowLinks", "on", "Type", "Block");
    blockTypes = string(get_param(blocks, "BlockType"));
    names = lower(string(blocks));
    dynamicTypes = ismember(blockTypes, [ ...
        "Integrator", "DiscreteIntegrator", "StateSpace", ...
        "DiscreteStateSpace", "Memory", "UnitDelay"]);
    audit.dynamic_state_block_count = sum(dynamicTypes);
    audit.physical_network_block_count = sum(contains(names, [ ...
        "simscape", "body", "chassis", "suspension", ...
        "tire", "wheel", "vehicle"]));
    audit.brake_control_block_count = sum(contains(names, [ ...
        "brake", "abs", "slip", "pressure"]));
    audit.full_vehicle_mechanism = ...
        audit.dynamic_state_block_count >= 6 || ...
        audit.physical_network_block_count >= 8;
    audit.closed_loop_four_channel_mechanism = ...
        audit.brake_control_block_count >= 4;
    audit.spatial_friction_mechanism = ...
        any(contains(names, ["friction", "road", "surface", "tire"]));
end
audit.minimum_dynamic_vehicle_signature = ...
    audit.full_vehicle_mechanism;
audit.four_wheel_brake_signature = ...
    audit.closed_loop_four_channel_mechanism;
end

function signals = localReferenceSignals(simOut)
values = cell(16, 1);
for index = 1:16
    variable = sprintf("F90_XAUTO04_Tap_%02d", index);
    values{index} = localSimulationValue(simOut, variable);
    assert(isa(values{index}, "timeseries"), ...
        "SimuVerity:F90:XAUTO04:ReferenceTap", ...
        "Reference tap %s is not a Timeseries.", variable);
end
t = localCommonTime(values);
matrices = cell(16, 1);
widths = [1 1 1 1 1 1 1 1 4 4 4 4 4 4 4 4];
for index = 1:16
    matrices{index} = localResampleTimeseries(values{index}, ...
        widths(index), t);
end
signals = struct;
signals.time_s = t;
signals.VehicleState = [ ...
    matrices{1}, matrices{2}, matrices{3}, matrices{4}, ...
    9.80665 * matrices{5}, 9.80665 * matrices{6}, ...
    matrices{7}, matrices{8}];
signals.WheelState = [matrices{9}, matrices{10}, matrices{11}];
signals.BrakeState = [matrices{12}, matrices{13}, matrices{14}];
signals.TireForceState = [matrices{15}, matrices{16}];
end

function signals = localCandidateSignals(simOut)
names = ["VehicleState", "WheelState", "BrakeState", "TireForceState"];
widths = [8, 12, 12, 8];
values = cell(4, 1);
for index = 1:4
    values{index} = simuverity_public_output_compatibility( ...
        simOut,names(index),widths(index),AllowBaseWorkspace=true);
end
t = localCommonTime(values);
signals = struct;
signals.time_s = t;
for index = 1:4
    signals.(names(index)) = ...
        localResampleTimeseries(values{index}, widths(index), t);
end
end

function value = localSimulationValue(simOut, name)
value = [];
try
    if any(string(simOut.who) == name), value = simOut.get(name); end
catch
end
if isempty(value)
    try, value = evalin("base", name); catch, end
end
end

function t = localCommonTime(values)
starts = zeros(numel(values), 1);
ends = zeros(numel(values), 1);
for index = 1:numel(values)
    ti = double(values{index}.Time(:));
    assert(numel(ti) >= 2 && all(diff(ti) > 0), ...
        "SimuVerity:F90:XAUTO04:Timebase", ...
        "Every evidence Timeseries needs a strictly increasing timebase.");
    starts(index) = ti(1);
    ends(index) = ti(end);
end
first = max(starts);
last = min(ends);
assert(last > first + 1, "SimuVerity:F90:XAUTO04:CommonTime", ...
    "Required outputs do not share a useful common time interval.");
t = (first:0.01:last).';
if t(end) < last - 0.001, t(end + 1, 1) = last; end
end

function matrix = localResampleTimeseries(ts, width, targetTime)
sourceTime = double(ts.Time(:));
data = squeeze(double(ts.Data));
count = numel(sourceTime);
assert(numel(data) == count * width, ...
    "SimuVerity:F90:XAUTO04:ChannelWidth", ...
    "Expected %d channels over %d samples.", width, count);
if width == 1
    data = data(:);
elseif size(data, 1) == count
    data = reshape(data, count, width);
elseif size(data, ndims(data)) == count
    order = [ndims(data), 1:(ndims(data) - 1)];
    data = reshape(permute(data, order), count, width);
elseif size(data, 2) == count
    data = reshape(data.', count, width);
else
    error("SimuVerity:F90:XAUTO04:DataLayout", ...
        "Cannot identify the time dimension for a %d-channel signal.", width);
end
matrix = interp1(sourceTime, data, targetTime, "linear");
assert(all(isfinite(matrix), "all"), "SimuVerity:F90:XAUTO04:FiniteResample", ...
    "Resampled evidence contains non-finite values.");
end

function metrics = localMetrics(signals, scenario)
t = double(signals.time_s(:));
vehicle = double(signals.VehicleState);
wheel = double(signals.WheelState);
brake = double(signals.BrakeState);
forces = double(signals.TireForceState);
x = vehicle(:, 1);
y = vehicle(:, 2);
vx = vehicle(:, 3);
vy = vehicle(:, 4);
ax = vehicle(:, 5);
ay = vehicle(:, 6);
yaw = vehicle(:, 7);
yawRate = vehicle(:, 8);
omega = wheel(:, 1:4);
radius = wheel(:, 5:8);
kappa = wheel(:, 9:12);
commandPressure = brake(:, 1:4);
measuredPressure = brake(:, 5:8);
absFlag = brake(:, 9:12);
fx = forces(:, 1:4);
fy = forces(:, 5:8);

pressurePeak = max(abs(measuredPressure), [], 1);
pressureScale = max(max(pressurePeak), eps);
commandScale = max(max(abs(commandPressure), [], "all"), eps);
commandLevel = max(abs(commandPressure), [], 2);
measuredLevel = max(abs(measuredPressure), [], 2);
startDistance = double(scenario.BrakeStartDistance_m);
searchIndex = find(x >= 0.75 * startDistance & ...
    vx >= 0.50 * double(scenario.TargetSpeed_mps), 1);
if isempty(searchIndex)
    [~, searchIndex] = max(x);
end
baselineStart = max(1, searchIndex - 100);
commandBaseline = median(commandLevel(baselineStart:searchIndex));
measuredBaseline = median(measuredLevel(baselineStart:searchIndex));
commandPostPeak = max(commandLevel(searchIndex:end));
measuredPostPeak = max(measuredLevel(searchIndex:end));
commandThreshold = commandBaseline + ...
    0.05 * max(commandPostPeak - commandBaseline, 0);
measuredThreshold = measuredBaseline + ...
    0.05 * max(measuredPostPeak - measuredBaseline, 0);
commandIndex = find((1:numel(t)).' >= searchIndex & ...
    commandLevel >= commandThreshold & ...
    commandLevel > commandBaseline + 1e-6 * commandScale, 1);
pressureIndex = find((1:numel(t)).' >= searchIndex & ...
    measuredLevel >= measuredThreshold & ...
    measuredLevel > measuredBaseline + 1e-6 * pressureScale, 1);
if isempty(commandIndex), commandIndex = numel(t); end
if isempty(pressureIndex), pressureIndex = numel(t); end
onsetIndex = min(commandIndex, pressureIndex);
preStart = max(1, find(t <= t(onsetIndex) - 1.0, 1, "last"));
preIndices = preStart:max(preStart, onsetIndex - 1);
preSpeed = median(vx(preIndices));
stopIndex = find((1:numel(t)).' >= onsetIndex & vx <= 0.50, 1);
if isempty(stopIndex)
    stopIndex = numel(t);
    stopped = false;
else
    stopped = true;
end
analysisIndices = (onsetIndex:stopIndex).';
active = false(numel(t), 1);
active(analysisIndices) = abs(vx(analysisIndices)) > 2.0;
if ~any(active), active(analysisIndices) = true; end
activeKappa = abs(kappa(active, :));
wheelLinear = abs(omega .* radius);
lock = wheelLinear < 0.15 .* max(abs(vx), 0.5);
lockActive = lock(active, :);

onsetX = x(onsetIndex);
stopDistance = abs(x(stopIndex) - onsetX);
terminalSpeed = max(vx(stopIndex), 0);
speedReduction = max(0, min(1, ...
    (preSpeed - terminalSpeed) / max(preSpeed, 0.5)));
travelDistance = [0; cumsum(hypot(diff(x), diff(y)))];
distanceAfterOnset = travelDistance - travelDistance(onsetIndex);
measuredActive = measuredPressure(active, :);
commandActive = commandPressure(active, :);
pressureRange = max(measuredActive, [], 1) - ...
    min(measuredActive, [], 1);
pressureTransitions = zeros(1, 4);
pressureLevels = zeros(1, 4);
absCycles = zeros(1, 4);
for channel = 1:4
    dp = abs(diff(measuredActive(:, channel)));
    threshold = max(0.01 * pressureRange(channel), ...
        1e-5 * pressureScale);
    pressureTransitions(channel) = sum(dp > threshold);
    normalized = measuredActive(:, channel) / ...
        max(pressurePeak(channel), eps);
    pressureLevels(channel) = numel(unique(round(normalized, 2)));
    flag = absFlag(:, channel) > 0.5;
    absCycles(channel) = sum(diff(flag) > 0);
end
commandNormalized = commandActive ./ ...
    max(max(abs(commandActive), [], 1), 0.01 * commandScale);
measuredNormalized = measuredActive ./ ...
    max(max(abs(measuredActive), [], 1), 0.01 * pressureScale);
pressureTracking = sqrt(mean( ...
    (measuredNormalized - commandNormalized).^2, 1));
identicalPressureFraction = mean( ...
    (max(measuredActive, [], 2) - min(measuredActive, [], 2)) ...
    <= 0.002 * pressureScale);
wheelSpread = sqrt(mean(var(wheelLinear(active, :), 0, 2))) / ...
    max(mean(abs(vx(active))), 0.5);
forceActive = mean(any(abs(fx(active, :)) > 50, 2));
finiteVector = [t; vehicle(:); wheel(:); brake(:); forces(:)];

metrics = struct;
metrics.duration_s = t(end) - t(1);
metrics.prebrake_speed_mps = preSpeed;
metrics.target_speed_relative_error = ...
    abs(preSpeed - double(scenario.TargetSpeed_mps)) / ...
    max(double(scenario.TargetSpeed_mps), 1);
metrics.command_onset_s = t(commandIndex);
metrics.measured_pressure_onset_s = t(pressureIndex);
metrics.pressure_response_delay_s = ...
    max(0, t(pressureIndex) - t(commandIndex));
metrics.brake_start_position_m = x(commandIndex);
metrics.brake_start_relative_error = ...
    abs(x(commandIndex) - double(scenario.BrakeStartDistance_m)) / ...
    max(double(scenario.BrakeStartDistance_m), 1);
metrics.final_speed_mps = vx(stopIndex);
metrics.speed_reduction_fraction = speedReduction;
metrics.stopped = logical(stopped);
metrics.braking_elapsed_s = t(stopIndex) - t(onsetIndex);
metrics.braking_distance_m = stopDistance;
metrics.distance_travelled_after_onset_m = max(distanceAfterOnset);
metrics.peak_deceleration_mps2 = max(0, -min(ax(active)));
metrics.mean_deceleration_mps2 = max(0, ...
    (abs(preSpeed) - abs(vx(stopIndex))) / ...
    max(t(stopIndex) - t(onsetIndex), 0.01));
metrics.maximum_abs_lateral_displacement_m = ...
    max(abs(y(active) - y(onsetIndex)));
metrics.maximum_abs_yaw_rad = max(abs(yaw(active) - yaw(onsetIndex)));
metrics.maximum_abs_yaw_rate_rad_s = max(abs(yawRate(active)));
metrics.maximum_abs_lateral_speed_mps = max(abs(vy(active)));
metrics.maximum_abs_lateral_acceleration_mps2 = max(abs(ay(active)));
metrics.worst_abs_slip_p95 = max(localColumnPercentile(activeKappa, 0.95));
metrics.worst_abs_slip_peak = max(activeKappa, [], "all");
metrics.controlled_slip_fraction = mean( ...
    activeKappa >= 0.03 & activeKappa <= 0.35, "all");
metrics.lock_fraction_any_wheel = mean(any(lockActive, 2));
metrics.severe_lock_fraction_all_wheels = mean(lockActive, "all");
metrics.wheel_speed_cross_channel_spread = wheelSpread;
metrics.wheel_speed_identical_fraction = mean( ...
    max(wheelLinear(active, :), [], 2) - ...
    min(wheelLinear(active, :), [], 2) < 0.01);
metrics.brake_command_peak = max(abs(commandPressure), [], 1);
metrics.brake_pressure_peak = pressurePeak;
metrics.brake_pressure_range = pressureRange;
metrics.brake_pressure_levels_min = min(pressureLevels);
metrics.brake_pressure_transitions_min = min(pressureTransitions);
metrics.brake_pressure_tracking_nrmse_worst = max(pressureTracking);
metrics.brake_pressure_cross_channel_spread = ...
    sqrt(mean(var(measuredActive, 0, 2))) / max(mean(pressurePeak), eps);
metrics.identical_pressure_fraction = identicalPressureFraction;
metrics.abs_active_fraction_by_wheel = mean(absFlag(active, :) > 0.5, 1);
metrics.abs_cycles_by_wheel = absCycles;
metrics.abs_any_active_fraction = mean(any(absFlag(active, :) > 0.5, 2));
metrics.longitudinal_tire_force_peak_n = max(abs(fx), [], 1);
metrics.lateral_tire_force_peak_n = max(abs(fy), [], 1);
metrics.four_tire_force_active_fraction = forceActive;
metrics.force_cross_channel_spread = ...
    sqrt(mean(var(fx(active, :), 0, 2))) / ...
    max(mean(max(abs(fx(active, :)), [], 2)), 1);
metrics.all_values_finite = all(isfinite(finiteVector));
end

function values = localColumnPercentile(matrix, fraction)
matrix = sort(matrix, 1);
row = max(1, min(size(matrix, 1), ...
    ceil(fraction * size(matrix, 1))));
values = matrix(row, :);
end

function pass = localSignalsValid(signals)
n = numel(signals.time_s);
pass = n >= 100 && ...
    isequal(size(signals.VehicleState), [n, 8]) && ...
    isequal(size(signals.WheelState), [n, 12]) && ...
    isequal(size(signals.BrakeState), [n, 12]) && ...
    isequal(size(signals.TireForceState), [n, 8]) && ...
    all(diff(signals.time_s) > 0) && ...
    all(isfinite([signals.time_s; signals.VehicleState(:); ...
        signals.WheelState(:); signals.BrakeState(:); ...
        signals.TireForceState(:)]));
end

function artifact = localArtifact(id, signals)
artifact = struct( ...
    "id", id, ...
    "time_s", signals.time_s, ...
    "VehicleState", signals.VehicleState, ...
    "WheelState", signals.WheelState, ...
    "BrakeState", signals.BrakeState, ...
    "TireForceState", signals.TireForceState);
end

function row = localEmptyScenario
row = struct( ...
    "id", "", "class", "", "requested_inputs", struct, ...
    "simulation_pass", false, "sample_count", 0, ...
    "end_time_s", 0, "time_coverage_pass", false, ...
    "required_evidence_pass", false, "valid", false, ...
    "metrics", struct, "error", struct);
end

function localClearOutputVariables
names = [ ...
    "VehicleState", "WheelState", "BrakeState", "TireForceState", ...
    compose("F90_XAUTO04_Tap_%02d", 1:16)];
evalin("base", "clear " + strjoin(names, " "));
end

function text = localNumber(value)
text = string(num2str(double(value), "%.15g"));
end

function localCloseModel(model)
try
    if strlength(model) > 0 && bdIsLoaded(model), close_system(model, 0); end
catch
end
end

function localRestore(oldPath, oldDir)
try, path(oldPath); catch, end
try, cd(oldDir); catch, end
end

function value = localFilePresence(file)
assert(isfile(file), "SimuVerity:FileMissing", "Required file is missing: %s", file);
value = "present";
end

function value = localError(ME)
value = struct("identifier", string(ME.identifier), ...
    "message", string(ME.message));
end

function text = localNow
text = string(datetime("now", "TimeZone", "Asia/Shanghai", ...
    "Format", "yyyy-MM-dd'T'HH:mm:ssXXX"));
end

function localWriteJson(file, value)
fid = fopen(file, "w");
assert(fid >= 0, "SimuVerity:F90:XAUTO04:JsonWrite", ...
    "Could not open the JSON output file for writing.");
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, "%s\n", jsonencode(value, PrettyPrint=true));
end

function value = localTernary(condition, ifTrue, ifFalse)
if condition, value = ifTrue; else, value = ifFalse; end
end

function root = localProjectRoot
root = fileparts(mfilename("fullpath"));
for level = 1:4, root = fileparts(root); end
end
