function evidence = f90_xmech05_extract_evidence(modelPath, outDir)
%F90_XMECH05_EXTRACT_EVIDENCE One-session multiscenario evidence extraction.
arguments
    modelPath (1,1) string
    outDir (1,1) string
end

definition = f90_xmech05_definition;
official = jsondecode(fileread(definition.runner.official_scenarios));
if ~isfolder(outDir), mkdir(outDir); end
assert(isfile(modelPath), "SimuVerity:F90:XMECH05:ModelMissing", ...
    "Model does not exist: %s", modelPath);

generationRunId = string(getenv("SIMUVERITY_GENERATION_RUN_ID"));
bindingBefore = localFilePresence(modelPath);
evaluationSubject = lower(strtrim(string(getenv( ...
    "SIMUVERITY_EVALUATION_SUBJECT"))));
if strlength(evaluationSubject) == 0, evaluationSubject = "candidate"; end
assert(any(evaluationSubject == ["candidate", "reference"]), ...
    "SimuVerity:F90:XMECH05:EvaluationSubject", ...
    "SIMUVERITY_EVALUATION_SUBJECT must be candidate or reference.");
referencePresence = lower(strtrim(string("present")));
assert(referencePresence == "present", ...
    "SimuVerity:F90:XMECH05:ReferencePresence", ...
    "Task-bound reference file presence is missing or invalid.");
[modelDir, modelName] = fileparts(modelPath);
oldDir = pwd;
oldPath = path;
cleanup = onCleanup(@() localRestore(oldDir, oldPath)); %#ok<NASGU>
cd(modelDir);

isReference = evaluationSubject == "reference" && bindingBefore == referencePresence;
if evaluationSubject == "reference"
    assert(isReference, "SimuVerity:F90:XMECH05:ReferenceIdentity", ...
        "Reference-subject model file presence differs from the task binding.");
end
supportDir = fullfile(modelDir, "ForkliftSupport");
if isfolder(supportDir)
    addpath(fullfile(supportDir, "Scripts"));
    addpath(fullfile(supportDir, "Data"));
    addpath(fullfile(supportDir, "Geometries"));
end

load_system(modelPath);
mdl = string(modelName);
closeCleanup = onCleanup(@() close_system(mdl, 0)); %#ok<NASGU>
structure = localStructureProfile(mdl);

evidence = struct;
evidence.schema = "simuverity.f90-xmech05-evidence.v1";
evidence.task_id = "F90-XMECH-05";
evidence.generation_run_id = generationRunId;
evidence.extraction_only = true;
evidence.created_at = localNow;
evidence.model_path = string(modelPath);
evidence.model_file_presence_before = bindingBefore;
evidence.reference_adapter = isReference;
evidence.runtime = struct( ...
    "matlab_release", string(version("-release")), ...
    "matlab_prefdir", string(getenv("MATLAB_PREFDIR")), ...
    "mcp_port", string(getenv("SIMUVERITY_MCP_PORT")));
evidence.integration = struct( ...
    "load_pass", true, "update_pass", false, ...
    "compile_pass", false, "simulate_pass", false);
evidence.structure = structure;
evidence.required_scenario_count = numel(official.scenarios);
evidence.scenarios = struct([]);
evidence.errors = struct([]);

try
    if isReference
        localEnableReferenceLogging(mdl);
        mws = get_param(mdl, "ModelWorkspace");
        baseline = struct( ...
            "box", mws.getVariable("box"), ...
            "wheel", mws.getVariable("wheel"), ...
            "bump", mws.getVariable("bump"));
    else
        baseline = struct;
    end

    set_param(mdl, "SimulationCommand", "update");
    evidence.integration.update_pass = true;

    scenarios = official.scenarios;
    rows = repmat(localEmptyScenario, numel(scenarios), 1);
    for index = 1:numel(scenarios)
        sc = scenarios(index);
        rows(index).id = string(sc.id);
        rows(index).class = string(sc.class);
        rows(index).inputs = struct( ...
            "PayloadMass_kg", double(sc.PayloadMass_kg), ...
            "WheelFrictionScale", double(sc.WheelFrictionScale), ...
            "BumpRadius_m", double(sc.BumpRadius_m));
        try
            if isReference
                localApplyReferenceScenario(mws, baseline, sc);
            else
                assignin("base", "PayloadMass_kg", double(sc.PayloadMass_kg));
                assignin("base", "WheelFrictionScale", ...
                    double(sc.WheelFrictionScale));
                assignin("base", "BumpRadius_m", double(sc.BumpRadius_m));
            end

            simIn = Simulink.SimulationInput(mdl);
            simIn = simIn.setModelParameter( ...
                "StopTime", string(official.simulation.stop_time_s), ...
                "ReturnWorkspaceOutputs", "on");
            if isReference
                simIn = simIn.setModelParameter( ...
                    "SignalLogging", "on", ...
                    "SignalLoggingName", "logsoutForklift", ...
                    "SimscapeLogType", "all", ...
                    "SimscapeLogName", "simlogForklift", ...
                    "SimscapeLogLimitData", "off");
            end

            tic;
            simOut = sim(simIn);
            rows(index).simulation_seconds = toc;
            if isReference
                signals = localReferenceSignals(simOut);
            else
                signals = localSubmissionSignals(simOut);
            end
            rows(index).signals = localCompactSignals(signals);
            rows(index).metrics = localMetrics(signals);
            rows(index).valid = localSignalsValid(signals, ...
                double(official.simulation.stop_time_s));
            rows(index).status = "PASS";
        catch ME
            rows(index).valid = false;
            rows(index).status = "FAIL";
            rows(index).error = localError(ME);
        end
    end
    evidence.scenarios = rows;
    evidence.integration.compile_pass = any([rows.valid]);
    evidence.integration.simulate_pass = all([rows.valid]);
catch ME
    evidence.errors = localError(ME);
end

if isempty(evidence.scenarios) || ~isfield(evidence.scenarios, "valid")
    evidence.valid_scenario_count = 0;
else
    evidence.valid_scenario_count = sum([evidence.scenarios.valid]);
end
evidence.all_scenarios_valid = ...
    evidence.valid_scenario_count == evidence.required_scenario_count;
evidence.model_file_presence_after = localFilePresence(modelPath);
evidence.reference_binding_preserved = ...
    evidence.model_file_presence_after == evidence.model_file_presence_before;
evidence.model_closed_without_save = true;
evidence.pass = evidence.integration.load_pass && ...
    evidence.integration.update_pass && ...
    evidence.integration.compile_pass && ...
    evidence.integration.simulate_pass && ...
    evidence.all_scenarios_valid && ...
    evidence.reference_binding_preserved;
evidence.evidence_complete = evidence.pass;

localWriteJson(fullfile(outDir, "evidence.json"), evidence);
fprintf("F90-XMECH-05 evidence: valid=%d/%d pass=%d\n", ...
    evidence.valid_scenario_count, evidence.required_scenario_count, ...
    evidence.pass);
end

function row = localEmptyScenario
row = struct( ...
    "id", "", "class", "", "inputs", struct, ...
    "simulation_seconds", NaN, "status", "NOT_RUN", ...
    "valid", false, "signals", struct, ...
    "metrics", struct, "error", struct);
end

function localApplyReferenceScenario(mws, baseline, sc)
box = baseline.box;
box.mass = double(sc.PayloadMass_kg);
wheel = baseline.wheel;
scale = double(sc.WheelFrictionScale);
wheel.contact.staticFriction = ...
    baseline.wheel.contact.staticFriction * scale;
wheel.contact.dynamicFriction = ...
    baseline.wheel.contact.dynamicFriction * scale;
bump = baseline.bump;
bump.radius = double(sc.BumpRadius_m);
mws.assignin("box", box);
mws.assignin("wheel", wheel);
mws.assignin("bump", bump);
end

function localEnableReferenceLogging(mdl)
editor = mdl + "/Control/Signal Editor";
if getSimulinkBlockHandle(editor) > 0
    ports = get_param(editor, "PortHandles");
    for k = 1:numel(ports.Outport)
        line = get_param(ports.Outport(k), "Line");
        if line > 0
            try
                original = string(get_param(line, "Name"));
                if strlength(original) == 0
                    original = "control_" + k;
                end
                set_param(line, "DataLogging", "on", ...
                    "DataLoggingNameMode", "Custom", ...
                    "DataLoggingName", "F90_CMD_" + ...
                    upper(matlab.lang.makeValidName(original)));
            catch
            end
        end
    end
end

selector = mdl + "/Scopes/Bus" + newline + "Selector";
if getSimulinkBlockHandle(selector) > 0
    ports = get_param(selector, "PortHandles");
    for k = 1:numel(ports.Outport)
        line = get_param(ports.Outport(k), "Line");
        if line > 0
            try
                set_param(line, "DataLogging", "on");
            catch
            end
        end
    end
end
end

function signals = localReferenceSignals(simOut)
names = string(simOut.who);
assert(any(names == "simlogForklift"), ...
    "SimuVerity:F90:XMECH05:ReferenceSimlogMissing", ...
    "Reference simulation did not return simlogForklift.");
root = simOut.get("simlogForklift");

[t, chassisX] = localNodeSeries(root, ...
    ["Forklift","x6_DOF_Joint","Px","p"]);
[~, chassisY] = localNodeSeries(root, ...
    ["Forklift","x6_DOF_Joint","Py","p"]);
[~, chassisZ] = localNodeSeries(root, ...
    ["Forklift","x6_DOF_Joint","Pz","p"]);
[~, chassisQ] = localNodeSeries(root, ...
    ["Forklift","x6_DOF_Joint","S","Q"]);
[~, payloadX] = localNodeSeries(root, ...
    ["Warehouse","x6_DOF_Joint_Box","Px","p"]);
[~, payloadY] = localNodeSeries(root, ...
    ["Warehouse","x6_DOF_Joint_Box","Py","p"]);
[~, payloadZ] = localNodeSeries(root, ...
    ["Warehouse","x6_DOF_Joint_Box","Pz","p"]);
[~, payloadQ] = localNodeSeries(root, ...
    ["Warehouse","x6_DOF_Joint_Box","S","Q"]);
[~, lift] = localNodeSeries(root, ...
    ["Forklift","Masts","Lift_Mechanism", ...
    "Left_Lift_Cylinder","Prismatic_Joint","Pz","p"]);
[~, tilt] = localNodeSeries(root, ...
    ["Forklift","Masts","Tilt_Mechanism", ...
    "Left_Tilt_Cylinder","Prismatic_Joint","Pz","p"]);
[~, fork] = localNodeSeries(root, ...
    ["Forklift","Prismatic_Joint_Fork_to_Outer","Pz","p"]);

signals = struct;
signals.time = t;
signals.vehicle_pose = [ ...
    chassisX, localInterpRoot(root, t, ...
    ["Forklift","x6_DOF_Joint","Py","p"]), ...
    localInterpRoot(root, t, ...
    ["Forklift","x6_DOF_Joint","Pz","p"]), ...
    localFitRows(chassisQ, numel(t))];
signals.payload_pose = [ ...
    localInterp(t, payloadX, t), ...
    localInterpRoot(root, t, ...
    ["Warehouse","x6_DOF_Joint_Box","Py","p"]), ...
    localInterpRoot(root, t, ...
    ["Warehouse","x6_DOF_Joint_Box","Pz","p"]), ...
    localFitRows(payloadQ, numel(t))];
signals.actuator_state = [ ...
    localInterpRoot(root, t, ...
    ["Forklift","Masts","Lift_Mechanism", ...
    "Left_Lift_Cylinder","Prismatic_Joint","Pz","p"]), ...
    localInterpRoot(root, t, ...
    ["Forklift","Masts","Tilt_Mechanism", ...
    "Left_Tilt_Cylinder","Prismatic_Joint","Pz","p"]), ...
    localInterpRoot(root, t, ...
    ["Forklift","Prismatic_Joint_Fork_to_Outer","Pz","p"])];
signals.wheel_contact = localReferenceWheelLogs(simOut, t);
signals.native_auxiliary = struct( ...
    "lift_source_range", localRange(lift), ...
    "tilt_source_range", localRange(tilt), ...
    "fork_source_range", localRange(fork), ...
    "payload_source_x_range", localRange(payloadX), ...
    "payload_source_y_range", localRange(payloadY), ...
    "payload_source_z_range", localRange(payloadZ));
end

function values = localReferenceWheelLogs(simOut, targetTime)
assert(any(string(simOut.who) == "logsoutForklift"), ...
    "SimuVerity:F90:XMECH05:ReferenceWheelLogsMissing", ...
    "Reference simulation did not return logsoutForklift.");
logs = simOut.get("logsoutForklift");
keys = ["nomalforcewheellf","nomalforcewheellr", ...
    "nomalforcewheelrf","nomalforcewheelrr", ...
    "frictionalforcewheellf","frictionalforcewheellr", ...
    "frictionalforcewheelrf","frictionalforcewheelrr"];
values = nan(numel(targetTime), numel(keys));
for k = 1:logs.numElements
    el = logs.get(k);
    key = lower(regexprep(string(el.Name), "[^a-zA-Z0-9]", ""));
    index = find(keys == key, 1);
    if isempty(index), continue; end
    [t, y] = localTimeData(el.Values);
    values(:, index) = localInterp(t, y, targetTime);
end
assert(all(any(isfinite(values), 1)), ...
    "SimuVerity:F90:XMECH05:ReferenceWheelChannels", ...
    "One or more native wheel-contact channels are absent.");
end

function signals = localSubmissionSignals(simOut)
required = ["vehicle_pose","payload_pose","actuator_state","wheel_contact"];
widths = [7, 7, 3, 8];
data = cell(size(required));
for k = 1:numel(required)
    value = simuverity_public_output_compatibility( ...
        simOut, required(k), widths(k), AllowBaseWorkspace=true);
    [t, y] = localTimeData(value);
    data{k} = struct("time", t, "values", y);
end
signals = struct;
signals.time = data{1}.time;
signals.vehicle_pose = localFitChannels(data{1}, signals.time, 7);
signals.payload_pose = localFitChannels(data{2}, signals.time, 7);
signals.actuator_state = localFitChannels(data{3}, signals.time, 3);
signals.wheel_contact = localFitChannels(data{4}, signals.time, 8);
signals.native_auxiliary = struct;
end

function values = localFitChannels(item, targetTime, count)
values = localInterp(item.time, item.values, targetTime);
assert(size(values, 2) == count, ...
    "SimuVerity:F90:XMECH05:RequiredLogChannels", ...
    "Expected %d channels, found %d.", count, size(values, 2));
end

function compact = localCompactSignals(signals)
count = numel(signals.time);
indices = unique(round(linspace(1, count, min(count, 401))));
compact = struct( ...
    "time_s", signals.time(indices), ...
    "vehicle_pose", signals.vehicle_pose(indices, :), ...
    "payload_pose", signals.payload_pose(indices, :), ...
    "actuator_state", signals.actuator_state(indices, :), ...
    "wheel_contact", signals.wheel_contact(indices, :), ...
    "native_auxiliary", signals.native_auxiliary);
end

function metrics = localMetrics(s)
t = s.time(:);
vehicle = s.vehicle_pose;
payload = s.payload_pose;
actuator = s.actuator_state;
forces = s.wheel_contact;

metrics = struct;
metrics.sample_count = numel(t);
metrics.time_start_s = t(1);
metrics.time_end_s = t(end);
metrics.finite_fraction = mean(isfinite([ ...
    vehicle, payload, actuator, forces]), "all");
metrics.chassis_axis_excursion_m = localRange(vehicle(:, 1:3), 1);
metrics.chassis_horizontal_excursion_m = hypot( ...
    localRange(vehicle(:, 1)), localRange(vehicle(:, 3)));
metrics.chassis_vertical_excursion_m = localRange(vehicle(:, 2));
metrics.payload_axis_excursion_m = localRange(payload(:, 1:3), 1);
metrics.payload_horizontal_excursion_m = hypot( ...
    localRange(payload(:, 1)), localRange(payload(:, 3)));
metrics.payload_vertical_excursion_m = localRange(payload(:, 2));
metrics.payload_net_displacement_m = norm( ...
    payload(end, 1:3) - payload(1, 1:3));
metrics.lift_extension_range_m = localRange(actuator(:, 1));
metrics.tilt_extension_range_m = localRange(actuator(:, 2));
metrics.fork_extension_range_m = localRange(actuator(:, 3));

vehicleQ = vehicle(:, 4:7);
payloadQ = payload(:, 4:7);
metrics.vehicle_quaternion_norm_error = ...
    mean(abs(vecnorm(vehicleQ, 2, 2) - 1), "omitnan");
metrics.payload_quaternion_norm_error = ...
    mean(abs(vecnorm(payloadQ, 2, 2) - 1), "omitnan");

normal = max(forces(:, 1:4), 0);
friction = abs(forces(:, 5:8));
totalNormal = sum(normal, 2);
metrics.mean_total_normal_force_N = mean(totalNormal, "omitnan");
metrics.peak_total_normal_force_N = max(totalNormal, [], "omitnan");
contactThreshold = max(10, 0.005 * ...
    median(totalNormal(totalNormal > 0), "omitnan"));
metrics.wheel_support_fraction = ...
    mean(normal > contactThreshold, 1, "omitnan");
metrics.all_wheels_support_fraction = ...
    mean(all(normal > contactThreshold, 2), "omitnan");
metrics.wheel_load_imbalance = mean(abs( ...
    (normal(:, 1) + normal(:, 2)) - ...
    (normal(:, 3) + normal(:, 4))) ./ ...
    max(totalNormal, eps), "omitnan");
metrics.friction_rms_N = sqrt(mean(friction .^ 2, "all", "omitnan"));
metrics.friction_peak_N = max(friction, [], "all", "omitnan");

metrics.chassis_final_speed_m_s = localFinalSpeed(t, vehicle(:, 1:3));
metrics.payload_final_speed_m_s = localFinalSpeed(t, payload(:, 1:3));
metrics.lift_final_speed_m_s = localFinalSpeed(t, actuator(:, 1));
metrics.payload_vehicle_motion_correlation = ...
    localMotionCorrelation(t, vehicle(:, [1 3]), payload(:, [1 3]));
metrics.payload_lift_correlation = ...
    localMotionCorrelation(t, actuator(:, 1), payload(:, 2));
metrics.event_times_s = struct( ...
    "lift_onset", localOnset(t, actuator(:, 1)), ...
    "payload_lift_onset", localOnset(t, payload(:, 2)), ...
    "obstacle_peak", localPeakTime(t, vehicle(:, 2)), ...
    "placement_settled", localSettledTime(t, payload(:, 1:3)));
end

function valid = localSignalsValid(s, stopTime)
valid = numel(s.time) >= 100 && s.time(1) <= 0.05 && ...
    s.time(end) >= stopTime - 0.05 && ...
    size(s.vehicle_pose, 2) == 7 && ...
    size(s.payload_pose, 2) == 7 && ...
    size(s.actuator_state, 2) == 3 && ...
    size(s.wheel_contact, 2) == 8 && ...
    all(isfinite([s.vehicle_pose, s.payload_pose, ...
    s.actuator_state, s.wheel_contact]), "all");
end

function value = localFinalSpeed(t, position)
window = t >= t(end) - min(1.0, 0.1 * (t(end) - t(1)));
tt = t(window);
yy = position(window, :);
if numel(tt) < 3
    value = Inf;
    return
end
velocity = diff(yy, 1, 1) ./ max(diff(tt), eps);
value = median(vecnorm(velocity, 2, 2), "omitnan");
end

function value = localMotionCorrelation(t, a, b)
a = localDerivative(t, a);
b = localDerivative(t, b);
a = vecnorm(a, 2, 2);
b = vecnorm(b, 2, 2);
keep = isfinite(a) & isfinite(b);
if sum(keep) < 10 || std(a(keep)) < eps || std(b(keep)) < eps
    value = 0;
else
    c = corrcoef(a(keep), b(keep));
    value = c(1, 2);
end
end

function d = localDerivative(t, y)
d = diff(y, 1, 1) ./ max(diff(t), eps);
end

function value = localOnset(t, y)
y = y(:);
span = localRange(y);
if span <= eps
    value = NaN;
    return
end
baseline = median(y(1:max(3, round(0.02 * numel(y)))), "omitnan");
index = find(abs(y - baseline) >= 0.1 * span, 1);
if isempty(index), value = NaN; else, value = t(index); end
end

function value = localRange(values, dimension)
if nargin < 2
    values = values(:);
    dimension = 1;
end
value = max(values, [], dimension, "omitnan") - ...
    min(values, [], dimension, "omitnan");
end

function value = localPeakTime(t, y)
baselineCount = max(3, round(0.02 * numel(y)));
baseline = median(y(1:baselineCount), "omitnan");
[~, index] = max(abs(y - baseline), [], "omitnan");
value = t(index);
end

function value = localSettledTime(t, position)
speed = [Inf; vecnorm(localDerivative(t, position), 2, 2)];
threshold = max(0.02, 0.02 * max(speed(isfinite(speed))));
settled = movmax(speed, max(3, round(0.5 / median(diff(t))))) < threshold;
indices = find(settled & t > 0.5 * t(end));
if isempty(indices), value = NaN; else, value = t(indices(1)); end
end

function [t, values] = localNodeSeries(root, ids)
node = root;
for k = 1:numel(ids)
    assert(node.hasChild(char(ids(k))), ...
        "SimuVerity:F90:XMECH05:SimscapePath", ...
        "Missing Simscape log node %s.", join(ids(1:k), "."));
    node = node.child(char(ids(k)));
end
s = node.series;
seriesTime = s.time;
t = double(seriesTime(:));
values = double(s.values(s.unit));
values = localFitRows(values, numel(t));
end

function values = localInterpRoot(root, targetTime, ids)
[t, values] = localNodeSeries(root, ids);
values = localInterp(t, values, targetTime);
end

function values = localFitRows(values, count)
values = squeeze(values);
if isvector(values)
    values = values(:);
elseif size(values, 1) ~= count && size(values, ndims(values)) == count
    order = [ndims(values), 1:(ndims(values) - 1)];
    values = permute(values, order);
end
values = reshape(values, count, []);
end

function values = localInterp(sourceTime, sourceValues, targetTime)
sourceTime = sourceTime(:);
sourceValues = localFitRows(sourceValues, numel(sourceTime));
if isequal(sourceTime, targetTime(:))
    values = sourceValues;
else
    [sourceTime, uniqueIndex] = unique(sourceTime, "stable");
    sourceValues = sourceValues(uniqueIndex, :);
    values = interp1(sourceTime, sourceValues, targetTime(:), ...
        "linear", "extrap");
end
end

function [t, y] = localTimeData(v)
t = double(v.Time(:));
y = localFitRows(double(v.Data), numel(t));
end

function profile = localStructureProfile(mdl)
blocks = find_system(mdl, "LookUnderMasks", "all", ...
    "FollowLinks", "on", "Type", "Block");
profile = struct;
profile.block_count = numel(blocks);
profile.subsystem_count = numel(find_system(mdl, ...
    "LookUnderMasks", "all", "FollowLinks", "on", ...
    "BlockType", "SubSystem"));
profile.reference_block_count = 0;
profile.joint_count = 0;
profile.solid_count = 0;
profile.spatial_contact_count = 0;
profile.actuation_or_converter_count = 0;
profile.hydraulic_component_count = 0;
profile.physical_port_count = 0;
profile.connected_physical_port_count = 0;

for k = 1:numel(blocks)
    block = blocks{k};
    descriptor = string(get_param(block, "Name"));
    try
        ref = string(get_param(block, "ReferenceBlock"));
        if strlength(ref) > 0
            descriptor = descriptor + " " + ref;
            profile.reference_block_count = ...
                profile.reference_block_count + 1;
        end
    catch
    end
    try
        descriptor = descriptor + " " + ...
            string(get_param(block, "MaskType"));
    catch
    end
    lowerDescriptor = regexprep(lower(descriptor), "\s+", " ");
    profile.joint_count = profile.joint_count + ...
        double(contains(lowerDescriptor, "joint"));
    profile.solid_count = profile.solid_count + ...
        double(contains(lowerDescriptor, "solid"));
    profile.spatial_contact_count = profile.spatial_contact_count + ...
        double(contains(lowerDescriptor, "spatial contact"));
    profile.actuation_or_converter_count = ...
        profile.actuation_or_converter_count + double( ...
        contains(lowerDescriptor, "simulink-ps") || ...
        contains(lowerDescriptor, "actuator"));
    profile.hydraulic_component_count = ...
        profile.hydraulic_component_count + double( ...
        contains(lowerDescriptor, "hydraulic") || ...
        contains(lowerDescriptor, "isothermal liquid"));
    try
        ports = get_param(block, "PortHandles");
        for field = ["LConn","RConn"]
            if isfield(ports, field)
                handles = ports.(field);
                profile.physical_port_count = ...
                    profile.physical_port_count + numel(handles);
                for h = handles(:)'
                    try
                        profile.connected_physical_port_count = ...
                            profile.connected_physical_port_count + ...
                            double(get_param(h, "Line") > 0);
                    catch
                    end
                end
            end
        end
    catch
    end
end
end

function value = localFilePresence(pathValue)
assert(isfile(pathValue), "SimuVerity:FileMissing", "Required file is missing: %s", pathValue);
value = "present";
end

function value = localError(ME)
value = struct( ...
    "identifier", string(ME.identifier), ...
    "message", string(ME.message), ...
    "stack", string({ME.stack.name}));
end

function value = localNow
value = string(datetime("now", "TimeZone", "Asia/Shanghai", ...
    "Format", "yyyy-MM-dd'T'HH:mm:ssXXX"));
end

function localWriteJson(pathValue, value)
fid = fopen(pathValue, "w", "n", "UTF-8");
assert(fid >= 0, "SimuVerity:F90:XMECH05:JsonOpen", ...
    "Cannot write evidence output: %s", pathValue);
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fwrite(fid, jsonencode(value, "PrettyPrint", true), "char");
end

function localRestore(oldDir, oldPath)
try, cd(oldDir); catch, end
path(oldPath);
end
