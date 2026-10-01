function evidence = f90_xcomm03_extract_evidence(modelPath, outDir)
%F90_XCOMM03_EXTRACT_EVIDENCE Extract all official scenarios in one session.
arguments
    modelPath (1,1) string = ""
    outDir (1,1) string = ""
end

def = f90_xcomm03_definition;
root = localProjectRoot;
generationRunId = string(getenv("SIMUVERITY_GENERATION_RUN_ID"));
assert(strlength(generationRunId) > 0, "SimuVerity:F90:XCOMM03:GenerationRunId", ...
    "SIMUVERITY_GENERATION_RUN_ID is required.");
if strlength(modelPath) == 0, modelPath = def.reference_model; end
assert(isfile(modelPath), "SimuVerity:F90:XCOMM03:ModelMissing", ...
    "Model under evaluation is missing: %s", modelPath);
if strlength(outDir) == 0
    outDir = fullfile(root, "results", "cross_domain", ...
        "simuverity_public", def.formal_id, "fixed_evidence", generationRunId);
end
if ~isfolder(outDir), mkdir(outDir); end
evidencePath = fullfile(outDir, "evidence.json");
assert(~isfile(evidencePath), "SimuVerity:F90:XCOMM03:OutputReuse", ...
    "Evidence already exists for GenerationRunId %s.", generationRunId);

localConfigureIsolation;
modelPresence = localFilePresence(modelPath);
evaluationSubject = lower(strtrim(string(getenv( ...
    "SIMUVERITY_EVALUATION_SUBJECT"))));
if strlength(evaluationSubject) == 0, evaluationSubject = "candidate"; end
assert(any(evaluationSubject == ["candidate", "reference"]), ...
    "SimuVerity:F90:XCOMM03:EvaluationSubject", ...
    "SIMUVERITY_EVALUATION_SUBJECT must be candidate or reference.");
isReference = evaluationSubject == "reference" && ...
    modelPresence == def.reference_file_presence;
if evaluationSubject == "reference"
    assert(isReference, "SimuVerity:F90:XCOMM03:ReferenceIdentity", ...
        "Reference-subject model file presence differs from the task binding.");
end
[~, model] = fileparts(modelPath);
pathBefore = path;
pathCleanup = onCleanup(@() path(pathBefore)); %#ok<NASGU>
addpath(def.reference_root);

evidence = struct;
evidence.schema = "simuverity.f90-xcomm03-evidence.v1";
evidence.task_id = def.formal_id;
evidence.generation_run_id = generationRunId;
evidence.model_path = modelPath;
evidence.model_file_presence = modelPresence;
evidence.reference_subject = logical(isReference);
evidence.adapter = ternary(isReference, ...
    "reference_native_stap_outputs", "public_timeseries_contract");
evidence.reference_substantive_modifications = 0;
evidence.extraction_only = true;
evidence.contains_score_decisions = false;
evidence.load_pass = false;
evidence.update_pass = false;
evidence.compile_pass = false;
evidence.scenarios = struct([]);
evidence.static_audit = struct;
evidence.errors = struct([]);
evidence.model_closed_without_save = false;
evidence.reference_binding_preserved = false;
evidence.started_at = localNow;
evidence.runtime = struct( ...
    "matlab_start_count", 1, ...
    "generation_run_id", generationRunId, ...
    "one_session_all_scenarios", true);

fatal = [];
try
    load_system(modelPath);
    evidence.load_pass = true;
    set_param(model, "ReturnWorkspaceOutputs", "on", ...
        "LimitDataPoints", "off");
    if isReference
        localInstallReferenceAdapter(model);
    end

    localApplyInputs(def.scenarios(1), isReference);
    set_param(model, "SimulationCommand", "update");
    evidence.update_pass = true;
    feval(model, [], [], [], "compile");
    feval(model, [], [], [], "term");
    evidence.compile_pass = true;
    evidence.static_audit = localStaticAudit(model);

    rows = repmat(localEmptyRow, 0, 1);
    for index = 1:numel(def.scenarios)
        scenario = def.scenarios(index);
        row = localEmptyRow;
        row.id = string(scenario.id);
        row.requested_inputs = scenario;
        try
            localApplyInputs(scenario, isReference);
            localClearPublicOutputs(isReference);
            stopTime = localStopTime(isReference, model);
            in = Simulink.SimulationInput(model);
            in = in.setModelParameter( ...
                "StartTime", "0", ...
                "StopTime", num2str(stopTime, 17), ...
                "SignalLogging", "on", ...
                "SignalLoggingName", "logsout", ...
                "ReturnWorkspaceOutputs", "on", ...
                "LimitDataPoints", "off");
            out = sim(in);
            row.simulation_pass = true;
            row = localCollectRow(row, out, scenario, isReference);
        catch ME
            row.error = localError(ME);
        end
        rows(end + 1, 1) = row; %#ok<AGROW>
    end
    evidence.scenarios = rows;
catch ME
    fatal = ME;
    evidence.errors = localError(ME);
    try, feval(model, [], [], [], "term"); catch, end
end

try
    if bdIsLoaded(model)
        close_system(model, 0);
        evidence.model_closed_without_save = true;
    end
catch ME
    evidence.model_close_error = localError(ME);
end
evidence.reference_binding_preserved = ...
    (~isReference) || localFilePresence(modelPath) == def.reference_file_presence;
evidence.finished_at = localNow;
localWriteJson(evidencePath, evidence);
if ~isempty(fatal), rethrow(fatal); end
end

function localInstallReferenceAdapter(model)
% Visualization sinks are disabled only in memory because their desktop
% viewers are not part of the radar signal path and fail in headless mode.
visualization = model + "/Visualization";
assert(getSimulinkBlockHandle(visualization, false) > 0, ...
    "SimuVerity:F90:XCOMM03:VisualizationLocator");
set_param(visualization, "Commented", "on");

stap = model + "/STAP";
handles = get_param(stap, "PortHandles");
ports = [1, 3, 4];
names = ["f90_xcomm03_pre", "f90_xcomm03_post", ...
    "f90_xcomm03_weights"];
for index = 1:numel(ports)
    port = handles.Outport(ports(index));
    assert(port > 0, "SimuVerity:F90:XCOMM03:NativePort", ...
        "Required STAP output port %d is missing.", ports(index));
    set_param(port, ...
        "DataLogging", "on", ...
        "DataLoggingNameMode", "Custom", ...
        "DataLoggingName", names(index));
end
end

function localApplyInputs(scenario, isReference)
names = ["TargetPosition_m", "TargetVelocity_mps", "TargetRCS_m2", ...
    "JammerPosition_m", "ClutterPowerScale"];
for name = names
    assignin("base", name, scenario.(name));
end
if ~isReference, return, end

helperslexSTAPParam;
p = evalin("base", "paramSTAP");
p.target1Pos = double(scenario.TargetPosition_m(:));
p.target1Vel = double(scenario.TargetVelocity_mps(:));
p.target1Rcs = double(scenario.TargetRCS_m2);
p.jammerPos = double(scenario.JammerPosition_m(:));
p.clutterTxERP = p.clutterTxERP * double(scenario.ClutterPowerScale);
location = global2localcoord(p.target1Pos, "rs", p.radarPos);
p.target1AzAngle = location(1);
p.target1ElAngle = location(2);
p.target1Range = location(3);
radial = radialspeed(p.target1Pos, p.target1Vel, ...
    p.radarPos, p.radarVel);
p.target1Dop = 2 * speed2dop(radial, p.propSpeed / p.fc);
assignin("base", "paramSTAP", p);
end

function stopTime = localStopTime(isReference, model)
if isReference
    p = evalin("base", "paramSTAP");
    stopTime = 20 / double(p.prf);
else
    value = str2double(get_param(model, "StopTime"));
    if isfinite(value) && value > 0
        stopTime = value;
    else
        stopTime = 20 / (physconst("LightSpeed") / (2 * 5000));
    end
end
end

function row = localCollectRow(row, out, scenario, isReference)
if isReference
    pre = out.logsout.getElement("f90_xcomm03_pre").Values;
    post = out.logsout.getElement("f90_xcomm03_post").Values;
    weights = out.logsout.getElement("f90_xcomm03_weights").Values;
else
    pre = localRequiredTimeseries(out, "ReceivedRangeResponse");
    post = localRequiredTimeseries(out, "SuppressedRangeResponse");
    weights = localRequiredTimeseries(out, "AdaptiveWeights");
end

[preFrames, time] = localComplexFrames(pre, 1200, ...
    "ReceivedRangeResponse");
[postFrames, postTime] = localComplexFrames(post, 200, ...
    "SuppressedRangeResponse");
[weightFrames, weightTime] = localComplexFrames(weights, 60, ...
    "AdaptiveWeights");
assert(numel(time) == numel(postTime) && ...
    numel(time) == numel(weightTime) && ...
    max(abs(time - postTime)) <= 1e-12 && ...
    max(abs(time - weightTime)) <= 1e-12, ...
    "SimuVerity:F90:XCOMM03:OutputTimeAlignment", ...
    "The three required Timeseries must have the same Time vector.");
assert(numel(time) >= 2 && time(end) > time(1), ...
    "SimuVerity:F90:XCOMM03:OutputCoverage", ...
    "At least two coherent-processing output samples are required.");

frameCount = numel(time);
prePower = zeros(frameCount, 200);
for frame = 1:frameCount
    matrix = reshape(preFrames(frame, :), 200, 6);
    prePower(frame, :) = mean(abs(matrix).^2, 2).';
end
postPower = abs(postFrames).^2;

radarPosition = [0; 0; 1000];
targetPosition = double(scenario.TargetPosition_m(:));
targetRange = norm(targetPosition - radarPosition);
rangeAxis = (0:199) * 25;
summary = localSummary( ...
    prePower, postPower, weightFrames, rangeAxis, targetRange);

row.valid = true;
row.time_s = time;
row.truth = struct( ...
    "target_range_m", targetRange, ...
    "target_bin_1based", round(targetRange / 25) + 1);
row.profiles = struct( ...
    "range_axis_m", rangeAxis, ...
    "received_range_power", prePower, ...
    "suppressed_range_power", postPower, ...
    "adaptive_weights_real", real(weightFrames), ...
    "adaptive_weights_imag", imag(weightFrames));
row.summary = summary;
end

function summary = localSummary( ...
        prePower, postPower, weights, rangeAxis, targetRange)
epsValue = 1e-18;
late = max(1, size(postPower, 1) - 1):size(postPower, 1);
pre = mean(prePower(late, :), 1);
post = mean(postPower(late, :), 1);
[peakPower, peakBin] = max(post);
targetBin = max(1, min(200, round(targetRange / 25) + 1));
band = max(1, targetBin - 1):min(200, targetBin + 1);
searchBand = max(1, targetBin - 4):min(200, targetBin + 4);
[~, localOffset] = max(post(searchBand));
localPeakBin = searchBand(localOffset);
targetPower = max(post(band));
localPeakPower = max(post(searchBand));
exclude = true(1, 200);
exclude(max(1, targetBin - 3):min(200, targetBin + 3)) = false;
exclude(1:5) = false;
backgroundPost = median(post(exclude));
backgroundPre = median(pre(exclude));
targetPre = max(pre(band));
framePeakBins = zeros(size(postPower, 1), 1);
frameLocalPeakBins = zeros(size(postPower, 1), 1);
frameProminence = zeros(size(postPower, 1), 1);
for frame = 1:size(postPower, 1)
    [~, framePeakBins(frame)] = max(postPower(frame, :));
    [~, localOffset] = max(postPower(frame, searchBand));
    frameLocalPeakBins(frame) = searchBand(localOffset);
    localTarget = max(postPower(frame, band));
    frameProminence(frame) = 10 * log10( ...
        max(localTarget, epsValue) / ...
        max(median(postPower(frame, exclude)), epsValue));
end
weightNorm = vecnorm(weights, 2, 2);
if size(weights, 1) >= 2
    weightChange = vecnorm(diff(weights, 1, 1), 2, 2) ./ ...
        max(weightNorm(2:end), epsValue);
else
    weightChange = Inf;
end
summary = struct( ...
    "target_range_m", targetRange, ...
    "target_bin_1based", targetBin, ...
    "global_peak_bin_1based", peakBin, ...
    "global_peak_range_m", rangeAxis(peakBin), ...
    "global_peak_error_m", abs(rangeAxis(peakBin) - targetRange), ...
    "local_target_peak_range_m", rangeAxis(localPeakBin), ...
    "local_target_peak_error_m", ...
        abs(rangeAxis(localPeakBin) - targetRange), ...
    "target_prominence_db", 10 * log10( ...
        max(targetPower, epsValue) / max(backgroundPost, epsValue)), ...
    "non_target_suppression_db", 10 * log10( ...
        max(backgroundPre, epsValue) / max(backgroundPost, epsValue)), ...
    "target_path_gain_db", 10 * log10( ...
        max(targetPower, epsValue) / max(targetPre, epsValue)), ...
    "target_to_global_peak_ratio", targetPower / max(peakPower, epsValue), ...
    "target_to_local_peak_ratio", ...
        targetPower / max(localPeakPower, epsValue), ...
    "frame_peak_range_spread_m", ...
        25 * (max(framePeakBins) - min(framePeakBins)), ...
    "late_local_peak_spread_m", ...
        25 * (max(frameLocalPeakBins(late)) - ...
        min(frameLocalPeakBins(late))), ...
    "late_frame_prominence_spread_db", ...
        max(frameProminence(late)) - min(frameProminence(late)), ...
    "weight_norm_max", max(weightNorm), ...
    "weight_norm_min", min(weightNorm), ...
    "weight_change_median", median(weightChange, "omitnan"), ...
    "received_background_power", backgroundPre, ...
    "suppressed_background_power", backgroundPost, ...
    "all_values_finite", ...
        all(isfinite(prePower), "all") && ...
        all(isfinite(postPower), "all") && ...
        all(isfinite(real(weights)), "all") && ...
        all(isfinite(imag(weights)), "all"));
end

function value = localRequiredTimeseries(out, name)
value = simuverity_public_output_compatibility( ...
    out,string(name),[],AllowBaseWorkspace=true);
end

function [frames, time] = localComplexFrames(value, channels, name)
time = double(value.Time(:));
data = double(value.Data);
assert(numel(time) >= 2 && all(isfinite(time)), ...
    "SimuVerity:F90:XCOMM03:TimeseriesTime", "%s has invalid time.", name);
assert(~isreal(data) && any(abs(imag(data(:))) > 1e-14), ...
    "SimuVerity:F90:XCOMM03:ComplexContract", ...
    "%s must preserve complex data.", name);
if size(data, ndims(data)) == numel(time)
    frames = reshape(data, [], numel(time)).';
elseif size(data, 1) == numel(time)
    frames = reshape(data, numel(time), []);
else
    error("SimuVerity:F90:XCOMM03:TimeseriesShape", ...
        "%s has no data dimension matching its Time vector.", name);
end
assert(size(frames, 2) == channels, ...
    "SimuVerity:F90:XCOMM03:TimeseriesChannels", ...
    "%s must contain exactly %d complex values per sample.", ...
    name, channels);
assert(all(isfinite(real(frames)), "all") && ...
    all(isfinite(imag(frames)), "all"), ...
    "SimuVerity:F90:XCOMM03:TimeseriesFinite", ...
    "%s contains nonfinite values.", name);
end

function audit = localStaticAudit(model)
blocks = string(find_system(model, "LookUnderMasks", "all", ...
    "FollowLinks", "on", "Type", "Block"));
signature = strings(size(blocks));
for index = 1:numel(blocks)
    signature(index) = lower(join([ ...
        localGet(blocks(index), "Name"), ...
        localGet(blocks(index), "MaskType"), ...
        localGet(blocks(index), "SourceBlock"), ...
        localGet(blocks(index), "ReferenceBlock"), ...
        localGet(blocks(index), "BlockType")], " "));
end
role = struct;
role.transmitter = any(contains(signature, "transmitter"));
role.propagation = any(contains(signature, ...
    ["free space", "freespace", "two-way path"]));
role.target = any(contains(signature, "target"));
role.jammer = any(contains(signature, "jammer"));
role.clutter = any(contains(signature, "clutter"));
role.receive_array = any(contains(signature, ...
    ["receive array", "collector", "sensor array"]));
role.adaptive_processor = any(contains(signature, ...
    ["adpca", "space-time", "stap", "adaptive pulse canceller"]));
role.pulse_buffer = any(contains(signature, ...
    ["buffer", "matrix to cube", "matrixcube"]));

top = string(find_system(model, "SearchDepth", 1, "Type", "Block"));
top = top(top ~= model);
processor = "";
receiver = "";
for index = 1:numel(top)
    own = lower(join([localGet(top(index), "Name"), ...
        localGet(top(index), "SourceBlock"), ...
        localGet(top(index), "MaskType"), ...
        localGet(top(index), "BlockType")], " "));
    isProcessor = any(contains(own, ...
        ["adpca", "space-time", "stap", "adaptive pulse canceller"]));
    if ~isProcessor && localGet(top(index), "BlockType") == "SubSystem"
        nested = string(find_system(top(index), ...
            "LookUnderMasks", "all", "FollowLinks", "on", ...
            "Type", "Block"));
        nestedSignature = strings(size(nested));
        for nestedIndex = 1:numel(nested)
            nestedSignature(nestedIndex) = lower(join([ ...
                localGet(nested(nestedIndex), "Name"), ...
                localGet(nested(nestedIndex), "SourceBlock"), ...
                localGet(nested(nestedIndex), "MaskType")], " "));
        end
        isProcessor = any(contains(nestedSignature, ...
            ["adpca", "space-time", "stap", ...
            "adaptive pulse canceller"]), "all");
    end
    if strlength(processor) == 0 && isProcessor
        processor = top(index);
    end
    if strlength(receiver) == 0 && contains(own, "receiver")
        receiver = top(index);
    end
end
connected = strlength(processor) > 0 && strlength(receiver) > 0 && ...
    localDirectedReachable(receiver, processor);
audit = struct( ...
    "roles", role, ...
    "receiver_to_adaptive_path", connected, ...
    "processor_top", processor, ...
    "receiver_top", receiver, ...
    "core_path_qualified", ...
        all(structfun(@logical, role)) && connected);
end

function pass = localDirectedReachable(source, target)
pass = false;
sourceHandle = getSimulinkBlockHandle(source, false);
targetHandle = getSimulinkBlockHandle(target, false);
if sourceHandle <= 0 || targetHandle <= 0, return, end
queue = sourceHandle;
visited = zeros(0, 1);
while ~isempty(queue)
    current = queue(1);
    queue(1) = [];
    if current == targetHandle, pass = true; return, end
    if any(visited == current), continue, end
    visited(end + 1, 1) = current; %#ok<AGROW>
    try, connectivity = get_param(current, "PortConnectivity");
    catch, connectivity = struct([]);
    end
    for index = 1:numel(connectivity)
        neighbors = double(connectivity(index).DstBlock(:));
        neighbors = neighbors(isfinite(neighbors) & neighbors > 0);
        queue = [queue; neighbors]; %#ok<AGROW>
    end
end
end

function value = localGet(block, parameter)
value = "";
try, value = string(get_param(block, parameter)); catch, end
end

function localClearPublicOutputs(isReference)
if isReference, return, end
evalin("base", ...
    "clear ReceivedRangeResponse SuppressedRangeResponse AdaptiveWeights");
end

function row = localEmptyRow
row = struct( ...
    "id", "", ...
    "requested_inputs", struct, ...
    "simulation_pass", false, ...
    "valid", false, ...
    "time_s", [], ...
    "truth", struct, ...
    "profiles", struct, ...
    "summary", struct, ...
    "error", struct);
end

function localConfigureIsolation
cacheRoot = string(getenv("SIMULINK_CACHE_FOLDER"));
codegenRoot = string(getenv("SIMULINK_CODEGEN_FOLDER"));
assert(strlength(cacheRoot) > 0 && strlength(codegenRoot) > 0, ...
    "SimuVerity:F90:XCOMM03:Isolation", ...
    "SIMULINK_CACHE_FOLDER and SIMULINK_CODEGEN_FOLDER are required.");
if ~isfolder(cacheRoot), mkdir(cacheRoot); end
if ~isfolder(codegenRoot), mkdir(codegenRoot); end
Simulink.fileGenControl("set", ...
    "CacheFolder", cacheRoot, ...
    "CodeGenFolder", codegenRoot, ...
    "createDir", true);
set(groot, "defaultFigureVisible", "off");
end

function value = localFilePresence(path)
assert(isfile(path), "SimuVerity:FileMissing", "Required file is missing: %s", path);
value = "present";
end

function value = localNow
value = string(datetime("now", "TimeZone", "local", ...
    "Format", "yyyy-MM-dd'T'HH:mm:ssXXX"));
end

function out = localError(ME)
out = struct( ...
    "identifier", string(ME.identifier), ...
    "message", string(ME.message));
end

function localWriteJson(path, value)
fid = fopen(path, "w");
assert(fid >= 0, "SimuVerity:F90:XCOMM03:WriteJson", ...
    "Cannot write evidence output: %s", path);
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fwrite(fid, jsonencode(value, PrettyPrint=true), "char");
end

function root = localProjectRoot
root = fileparts(mfilename("fullpath"));
for level = 1:4, root = fileparts(root); end
end

function value = ternary(test, a, b)
if test, value = a; else, value = b; end
end
