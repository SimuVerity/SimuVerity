function evidence = f90_xmed05_extract_evidence_foundation(modelPath, outDir, scenarioIds)
%f90_xmed05_extract_evidence_foundation Extract score-free PACER evidence in one session.
arguments
    modelPath (1,1) string = ""
    outDir (1,1) string = ""
    scenarioIds string = strings(0, 1)
end
def = f90_xmed05_definition;
root = localProjectRoot;
official = jsondecode(fileread(def.official_scenarios));
scenarios = official.scenarios;
if iscell(scenarios), scenarios = [scenarios{:}]; end
if ~isempty(scenarioIds)
    available = string({scenarios.id});
    assert(all(ismember(scenarioIds, available)), ...
        "SimuVerity:F90:XMED05:ScenarioSubset", ...
        "Every requested scenario id must exist in official_scenarios.json.");
    scenarios = scenarios(ismember(available, scenarioIds));
end
generationRunId = string(getenv("SIMUVERITY_GENERATION_RUN_ID"));
assert(strlength(generationRunId) > 0, "SimuVerity:F90:XMED05:GenerationRunId", ...
    "SIMUVERITY_GENERATION_RUN_ID is required.");
if strlength(modelPath) == 0, modelPath = def.reference_model; end
assert(isfile(modelPath), "SimuVerity:F90:XMED05:ModelMissing", ...
    "Model is missing: %s", modelPath);
if strlength(outDir) == 0
    outDir = fullfile(tempdir, "SimuVerity", def.formal_id, generationRunId);
end
assert(~isfolder(outDir), "SimuVerity:F90:XMED05:OutputReuse", ...
    "Output directory already exists: %s", outDir);
mkdir(outDir);
cacheDir = string(getenv("SIMULINK_CACHE_FOLDER"));
codegenDir = string(getenv("SIMULINK_CODEGEN_FOLDER"));
assert(strlength(cacheDir) > 0 && strlength(codegenDir) > 0, ...
    "SimuVerity:F90:XMED05:Isolation", ...
    "SIMULINK_CACHE_FOLDER and SIMULINK_CODEGEN_FOLDER are required.");
Simulink.fileGenControl("set", "CacheFolder", cacheDir, ...
    "CodeGenFolder", codegenDir, "createDir", true);
set(groot, "defaultFigureVisible", "off");

wallClock = tic;
modelBindingBefore = localFilePresence(modelPath);
isReference = lower(strtrim(string(getenv("SIMUVERITY_EVALUATION_SUBJECT")))) == "reference";
libraryBindingBefore = "";
if isReference, libraryBindingBefore = localFilePresence(def.reference_library); end
evidence = localEmptyEvidence(def, modelPath, modelBindingBefore, ...
    isReference, generationRunId, cacheDir, codegenDir);
evidence.requested_scenarios = string({scenarios.id});
rows = repmat(localEmptyScenario, numel(scenarios), 1);
scenarioArtifacts = repmat(struct( ...
    "id", "", "CardiacEGM", struct, "PacingEvents", struct), ...
    numel(scenarios), 1);

oldPath = path;
oldDir = string(pwd);
restore = onCleanup(@() localRestore(oldPath, oldDir)); %#ok<NASGU>
model = "";
runtimeConfig = [];
oldConfig = struct;
fatal = [];
try
    if isReference
        addpath(def.reference_root, "-begin");
        addpath(fullfile(def.reference_root, "Lib"), "-begin");
        addpath(fullfile(def.reference_root, "src"), "-begin");
        addpath(fullfile(def.reference_root, "models"), "-begin");
        cd(def.reference_root);
        localLoadToBase(fullfile(def.reference_root, "N3Cfg.mat"));
        localLoadToBase(fullfile(def.reference_root, "N3Data.mat"));
        localApplyScenario(scenarios(1), true, def.reference_root);
        load_system(def.reference_library);
        load_system(def.reference_model);
        model = "CLSfixed";
    else
        [modelDir, modelStem] = fileparts(modelPath);
        addpath(modelDir, "-begin");
        load_system(modelPath);
        model = string(modelStem);
    end
    evidence.load_pass = true;
    runtimeConfig = getActiveConfigSet(model);
    if isa(runtimeConfig, "Simulink.ConfigSetRef")
        runtimeConfig = getRefConfigSet(runtimeConfig);
    end
    oldConfig = localCaptureConfig(runtimeConfig);
    configCleanup = onCleanup( ...
        @() localRestoreConfig(runtimeConfig, oldConfig)); %#ok<NASGU>
    set_param(runtimeConfig, ...
        "ReturnWorkspaceOutputs", "on", "LimitDataPoints", "off");
    set_param(model, "SimulationMode", "normal");
    evidence.static_audit = localStaticAudit(model);
    if isReference, localAttachReferenceAdapter(model); end
    localApplyScenario(scenarios(1), isReference, def.reference_root);
    set_param(runtimeConfig, "StopTime", ...
        string(scenarios(1).SimulationDuration_ms));
    set_param(model, "SimulationCommand", "update");
    evidence.update_pass = true;
    feval(model, [], [], [], "compile");
    feval(model, [], [], [], "term");
    evidence.compile_pass = true;
    evidence.compile_method = "direct model compile and term";

    for index = 1:numel(scenarios)
        scenario = scenarios(index);
        rows(index).id = string(scenario.id);
        rows(index).class = string(scenario.class);
        rows(index).requested_inputs = struct( ...
            "RhythmCondition", double(scenario.RhythmCondition), ...
            "SimulationDuration_ms", double(scenario.SimulationDuration_ms));
        scenarioArtifacts(index).id = string(scenario.id);
        try
            if isReference && index > 1
                % PACER parameter packs contain variable-size Stateflow
                % parameters. Reload the untouched model inside the same
                % persistent MATLAB process so each pack establishes its
                % declared dimensions before update/compile.
                close_system(model, 0);
                if bdIsLoaded("Libs"), close_system("Libs", 0); end
                localApplyScenario(scenario, true, def.reference_root);
                load_system(def.reference_library);
                load_system(def.reference_model);
                runtimeConfig = getActiveConfigSet(model);
                if isa(runtimeConfig, "Simulink.ConfigSetRef")
                    runtimeConfig = getRefConfigSet(runtimeConfig);
                end
                set_param(runtimeConfig, ...
                    "ReturnWorkspaceOutputs", "on", ...
                    "LimitDataPoints", "off");
                set_param(model, "SimulationMode", "normal");
                localAttachReferenceAdapter(model);
                set_param(runtimeConfig, "StopTime", ...
                    string(scenario.SimulationDuration_ms));
                set_param(model, "SimulationCommand", "update");
            else
                localApplyScenario(scenario, isReference, def.reference_root);
            end
            set_param(runtimeConfig, "StopTime", ...
                string(scenario.SimulationDuration_ms));
            localClearOutputs;
            simulationClock = tic;
            simOut = sim(model);
            rows(index).simulation_wall_clock_s = toc(simulationClock);
            if isReference
                signals = localReferenceSignals(simOut);
            else
                signals = localCandidateSignals(simOut);
            end
            rows(index).simulation_pass = true;
            rows(index).sample_counts = struct( ...
                "CardiacEGM", numel(signals.CardiacEGM.time), ...
                "PacingEvents", numel(signals.PacingEvents.time));
            rows(index).end_time_ms = min( ...
                signals.CardiacEGM.time(end), signals.PacingEvents.time(end));
            rows(index).time_coverage_pass = localTimeCoverage( ...
                signals, double(scenario.SimulationDuration_ms));
            rows(index).required_evidence_pass = localSignalsValid(signals);
            rows(index).valid = rows(index).time_coverage_pass && ...
                rows(index).required_evidence_pass;
            [rows(index).metrics, rows(index).profiles] = ...
                localMetrics(signals, scenario);
            scenarioArtifacts(index) = struct( ...
                "id", string(scenario.id), ...
                "CardiacEGM", signals.CardiacEGM, ...
                "PacingEvents", signals.PacingEvents);
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
    if isReference && bdIsLoaded("Libs"), close_system("Libs", 0); end
catch ME
    evidence.model_close_error = localError(ME);
end
evidence.reference_binding_preserved = ...
    (~isReference) || localFilePresence(modelPath) == modelBindingBefore;
evidence.library_binding_preserved = ...
    (~isReference) || localFilePresence(def.reference_library) == libraryBindingBefore;
evidence.finished_at = localNow;
evidence.runtime.wall_clock_s = toc(wallClock);
evidencePath = fullfile(outDir, "evidence.json");
localWriteJson(evidencePath, evidence);
if ~isempty(fatal), rethrow(fatal); end
end

function evidence = localEmptyEvidence(def, modelPath, modelBinding, ...
        isReference, generationRunId, cacheDir, codegenDir)
evidence = struct;
evidence.schema = "simuverity.f90-xmed05-evidence.v1";
evidence.task_id = def.formal_id;
evidence.generation_run_id = generationRunId;
evidence.model_path = modelPath;
evidence.model_file_presence = modelBinding;
evidence.reference_subject = logical(isReference);
evidence.adapter = localTernary(isReference, ...
    "absolute_parameter_packs_headless_gui_bypass_unsaved_event_taps", ...
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
evidence.library_binding_preserved = false;
evidence.started_at = localNow;
evidence.runtime = struct( ...
    "matlab_start_count", 1, "generation_run_id", generationRunId, ...
    "one_session_all_scenarios", true, ...
    "matlab_release", string(version("-release")), ...
    "matlab_prefdir", string(prefdir), ...
    "appdata", string(getenv("APPDATA")), ...
    "temp", string(getenv("TEMP")), ...
    "cache", cacheDir, "codegen", codegenDir, ...
    "mcp_port", string(getenv("SIMUVERITY_MCP_PORT")));
end

function row = localEmptyScenario
row = struct( ...
    "id", "", "class", "", "requested_inputs", struct, ...
    "simulation_pass", false, "simulation_wall_clock_s", 0, ...
    "sample_counts", struct, "end_time_ms", 0, ...
    "time_coverage_pass", false, ...
    "required_evidence_pass", false, "valid", false, ...
    "metrics", struct, "profiles", struct, "error", struct);
end

function value = localCaptureConfig(config)
value = struct( ...
    "ReturnWorkspaceOutputs", get_param(config, "ReturnWorkspaceOutputs"), ...
    "LimitDataPoints", get_param(config, "LimitDataPoints"), ...
    "StopTime", get_param(config, "StopTime"));
end

function localRestoreConfig(config, value)
try
    set_param(config, ...
        "ReturnWorkspaceOutputs", value.ReturnWorkspaceOutputs, ...
        "LimitDataPoints", value.LimitDataPoints, ...
        "StopTime", value.StopTime);
catch
end
end

function localApplyScenario(scenario, isReference, referenceRoot)
assignin("base", "RhythmCondition", double(scenario.RhythmCondition));
assignin("base", "SimulationDuration_ms", ...
    double(scenario.SimulationDuration_ms));
if isReference
    localLoadReferencePack(referenceRoot, ...
        string(scenario.reference_parameter_pack));
    if isfield(scenario, "reference_overrides")
        localApplyReferenceOverrides(scenario.reference_overrides);
    end
end
end

function names = localLoadToBase(pathValue)
value = load(pathValue);
names = localAssignToBase(value);
end

function localLoadReferencePack(referenceRoot, relativePath)
pack = load(fullfile(referenceRoot, relativePath));
localAssignToBase(pack);
end

function localApplyReferenceOverrides(overrides)
pp = evalin("base", "pp");
if isfield(overrides, "pp_indices_1based")
    indices = double(overrides.pp_indices_1based(:)).';
    values = double(overrides.pp_values(:)).';
    assert(numel(indices) == numel(values), ...
        "SimuVerity:F90:XMED05:ParameterOverride", ...
        "pp index and value counts must match.");
    pp(indices) = values;
end
if isfield(overrides, "path_slots_1based")
    slots = double(overrides.path_slots_1based(:)).';
    values = double(overrides.pp_values(:)).';
    pPath = evalin("base", "pPath");
    ppPath = evalin("base", "ppPath");
    pRange = evalin("base", "pRange");
    pPathValues = double(overrides.pPath_values(:)).';
    ppPathRows = double(overrides.ppPath_rows);
    pRangeRows = double(overrides.pRange_rows);
    assert(numel(slots) == numel(values) && ...
        numel(slots) == numel(pPathValues), ...
        "SimuVerity:F90:XMED05:PathOverride", ...
        "Path override slot and value counts must match.");
    nodeCount = numel(evalin("base", "pNode"));
    pPath(slots) = pPathValues;
    pp(nodeCount + slots) = values;
    ppPath(slots, :) = ppPathRows;
    pRange(nodeCount + slots, :) = pRangeRows;
    assignin("base", "pPath", pPath);
    assignin("base", "ppPath", ppPath);
    assignin("base", "pRange", pRange);
end
assignin("base", "pp", pp);
end

function names = localAssignToBase(value)
names = string(fieldnames(value));
for index = 1:numel(names)
    assignin("base", char(names(index)), value.(char(names(index))));
end
end

function localAttachReferenceAdapter(model)
guiBlocks = find_system(model, "LookUnderMasks", "all", ...
    "FollowLinks", "on", "BlockType", "S-Function", ...
    "FunctionName", "SaveTrace_sfcn");
assert(numel(guiBlocks) == 1, "SimuVerity:F90:XMED05:SaveTraceLocator", ...
    "Expected exactly one SaveTrace_sfcn block.");
set_param(guiBlocks{1}, "Commented", "on");
fileBlocks = find_system(model, "SearchDepth", 1, "BlockType", "ToFile");
for index = 1:numel(fileBlocks)
    set_param(fileBlocks{index}, "Commented", "on");
end
localAttachTagMux(model, ...
    ["Aegm1", "Vegm1"], ...
    "F90_XMED05_EGMMux", "F90_XMED05_EGMSink", ...
    "F90_XMED05_EGMTap", [2070 640 2075 690]);
localAttachTagMux(model, ...
    ["Aget1", "Vget1", "AP", "VP", "AS", "VS", "AP1", "VP1"], ...
    "F90_XMED05_EventMux", "F90_XMED05_EventSink", ...
    "F90_XMED05_EventTap", [2070 720 2075 900]);
end

function localAttachTagMux(model, tags, muxName, sinkName, variableName, position)
mux = model + "/" + muxName;
sink = model + "/" + sinkName;
add_block("simulink/Signal Routing/Mux", mux, ...
    "Inputs", string(numel(tags)), "Position", position);
midY = 0.5 * (position(2) + position(4));
sinkPosition = [position(3) + 60, midY - 15, ...
    position(3) + 220, midY + 15];
add_block("simulink/Sinks/To Workspace", sink, ...
    "VariableName", variableName, "SaveFormat", "Timeseries", ...
    "MaxDataPoints", "inf", ...
    "Position", sinkPosition);
muxPorts = get_param(mux, "PortHandles");
for index = 1:numel(tags)
    candidates = find_system(model, "SearchDepth", 1, ...
        "BlockType", "From", "GotoTag", tags(index));
    assert(~isempty(candidates), "SimuVerity:F90:XMED05:SignalLocator", ...
        "No top-level From block found for %s.", tags(index));
    sourcePorts = get_param(candidates{1}, "PortHandles");
    add_line(model, sourcePorts.Outport(1), muxPorts.Inport(index), ...
        "autorouting", "on");
end
sinkPorts = get_param(sink, "PortHandles");
add_line(model, muxPorts.Outport(1), sinkPorts.Inport(1), ...
    "autorouting", "on");
end

function audit = localStaticAudit(model)
blocks = find_system(model, "LookUnderMasks", "all", ...
    "FollowLinks", "on", "Type", "Block");
try
    charts = find_system(model, "LookUnderMasks", "all", ...
        "FollowLinks", "on", "SFBlockType", "Chart");
catch
    charts = {};
end
audit = struct;
audit.block_count = numel(blocks);
audit.stateflow_chart_count = numel(charts);
audit.inport_count = numel(find_system(model, "LookUnderMasks", "all", ...
    "FollowLinks", "on", "BlockType", "Inport"));
audit.outport_count = numel(find_system(model, "LookUnderMasks", "all", ...
    "FollowLinks", "on", "BlockType", "Outport"));
audit.routing_block_count = numel(find_system(model, "LookUnderMasks", "all", ...
    "FollowLinks", "on", "Regexp", "on", ...
    "BlockType", "From|Goto|Mux|Demux"));
audit.minimum_hybrid_closed_loop_signature = ...
    audit.block_count >= 50 && audit.stateflow_chart_count >= 3 && ...
    audit.routing_block_count >= 10;
end

function signals = localReferenceSignals(simOut)
signals = struct( ...
    "CardiacEGM", localSignal( ...
        localGetOutput(simOut, "F90_XMED05_EGMTap"), 2), ...
    "PacingEvents", localSignal( ...
        localGetOutput(simOut, "F90_XMED05_EventTap"), 8));
end

function signals = localCandidateSignals(simOut)
signals = struct( ...
    "CardiacEGM", localSignal(simuverity_public_output_compatibility( ...
        simOut, "CardiacEGM", 2, AllowBaseWorkspace=true), 2), ...
    "PacingEvents", localSignal(simuverity_public_output_compatibility( ...
        simOut, "PacingEvents", 8, AllowBaseWorkspace=true), 8));
end

function value = localGetOutput(simOut, name)
try
    value = simOut.get(name);
catch
    value = evalin("base", name);
end
end

function signal = localSignal(value, channels)
assert(isa(value, "timeseries"), "SimuVerity:F90:XMED05:Timeseries", ...
    "Required output must be a MATLAB Timeseries.");
time = double(value.Time(:));
data = squeeze(double(value.Data));
if isvector(data)
    data = data(:);
elseif size(data, 1) ~= numel(time) && size(data, 2) == numel(time)
    data = data.';
end
assert(size(data, 1) == numel(time) && size(data, 2) == channels, ...
    "SimuVerity:F90:XMED05:TimeseriesShape", ...
    "Expected %d channels.", channels);
assert(all(diff(time) >= 0), "SimuVerity:F90:XMED05:TimeOrder", ...
    "Timeseries time must be monotone.");
signal = struct("time", time, "data", data);
end

function pass = localTimeCoverage(signals, duration)
pass = signals.CardiacEGM.time(1) <= 0.5 && ...
    signals.PacingEvents.time(1) <= 0.5 && ...
    signals.CardiacEGM.time(end) >= duration - 0.5 && ...
    signals.PacingEvents.time(end) >= duration - 0.5;
end

function pass = localSignalsValid(signals)
pass = numel(signals.CardiacEGM.time) >= 100 && ...
    numel(signals.PacingEvents.time) >= 100 && ...
    all(isfinite(signals.CardiacEGM.data), "all") && ...
    all(isfinite(signals.PacingEvents.data), "all") && ...
    std(signals.CardiacEGM.data(:, 1)) > 1e-8 && ...
    std(signals.CardiacEGM.data(:, 2)) > 1e-8;
end

function [metrics, profiles] = localMetrics(signals, scenario)
time = signals.PacingEvents.time;
events = interp1(signals.PacingEvents.time, ...
    signals.PacingEvents.data, time, "previous", "extrap");
egm = interp1(signals.CardiacEGM.time, ...
    signals.CardiacEGM.data, time, "linear", "extrap");
names = ["atrial_detected", "ventricular_detected", ...
    "atrial_pace", "ventricular_pace", ...
    "atrial_sensed", "ventricular_sensed", ...
    "atrial_delivered", "ventricular_delivered"];
eventTimes = struct;
eventCounts = struct;
intervals = struct;
for index = 1:numel(names)
    thisTimes = localEventTimes(time, events(:, index));
    eventTimes.(names(index)) = thisTimes;
    eventCounts.(names(index)) = numel(thisTimes);
    intervals.(names(index)) = localIntervalStats(thisTimes);
end
atrialEffective = sort([ ...
    eventTimes.atrial_sensed(:); eventTimes.atrial_pace(:)]);
ventricularEffective = sort([ ...
    eventTimes.ventricular_sensed(:); eventTimes.ventricular_pace(:)]);
atrialStats = localIntervalStats(atrialEffective);
ventricularStats = localIntervalStats(ventricularEffective);
[avAssociation, avDelay] = localFollowFraction( ...
    atrialEffective, ventricularEffective, 40, 500);
[atrialDelivery, ~] = localFollowFraction( ...
    eventTimes.atrial_pace, eventTimes.atrial_delivered, 0, 5);
[ventricularDelivery, ~] = localFollowFraction( ...
    eventTimes.ventricular_pace, eventTimes.ventricular_delivered, 0, 5);
[atrialCapture, atrialCaptureDelay] = localFollowFraction( ...
    eventTimes.atrial_delivered, eventTimes.atrial_detected, 5, 600);
[ventricularCapture, ventricularCaptureDelay] = localFollowFraction( ...
    eventTimes.ventricular_delivered, eventTimes.ventricular_detected, 5, 600);
metrics = struct;
metrics.all_values_finite = ...
    all(isfinite([events(:); egm(:)]));
metrics.event_counts = eventCounts;
metrics.event_times_ms = eventTimes;
metrics.event_intervals_ms = intervals;
metrics.atrial_effective_intervals_ms = atrialStats;
metrics.ventricular_effective_intervals_ms = ventricularStats;
metrics.atrial_effective_rate_bpm = localRate(atrialStats.median);
metrics.ventricular_effective_rate_bpm = localRate(ventricularStats.median);
metrics.av_association_fraction = avAssociation;
metrics.av_delay_median_ms = avDelay;
metrics.atrial_command_delivery_fraction = atrialDelivery;
metrics.ventricular_command_delivery_fraction = ventricularDelivery;
metrics.atrial_capture_fraction = atrialCapture;
metrics.ventricular_capture_fraction = ventricularCapture;
metrics.atrial_capture_delay_median_ms = atrialCaptureDelay;
metrics.ventricular_capture_delay_median_ms = ventricularCaptureDelay;
metrics.atrial_egm_std = std(egm(:, 1));
metrics.ventricular_egm_std = std(egm(:, 2));
metrics.atrial_egm_range = max(egm(:, 1)) - min(egm(:, 1));
metrics.ventricular_egm_range = max(egm(:, 2)) - min(egm(:, 2));
metrics.event_pulse_duty_fraction = mean(events > 0.5, 1);
metrics.simultaneous_pace_fraction = mean( ...
    events(:, 3) > 0.5 & events(:, 4) > 0.5);
metrics.scenario_duration_ms = double(scenario.SimulationDuration_ms);
profiles = struct;
profiles.egm = localProfile(egm, 400);
profiles.events = localEventProfile(time, events, 200);
profiles.signature = [ ...
    cell2mat(struct2cell(eventCounts)).', ...
    metrics.atrial_effective_rate_bpm, ...
    metrics.ventricular_effective_rate_bpm, ...
    metrics.atrial_egm_std, metrics.ventricular_egm_std, ...
    metrics.av_association_fraction, ...
    metrics.atrial_capture_fraction, metrics.ventricular_capture_fraction];
end

function times = localEventTimes(time, value)
active = value(:) > 0.5;
indices = find(diff([false; active]) > 0);
times = time(indices).';
end

function stats = localIntervalStats(times)
delta = diff(double(times(:)));
if isempty(delta)
    stats = struct("count", 0, "minimum", inf, ...
        "median", inf, "maximum", inf, "cv", inf);
    return;
end
stats = struct("count", numel(delta), ...
    "minimum", min(delta), "median", median(delta), ...
    "maximum", max(delta), ...
    "cv", std(delta) / max(mean(delta), 1e-9));
end

function rate = localRate(interval)
if ~isfinite(interval) || interval <= 0
    rate = 0;
else
    rate = 60000 / interval;
end
end

function [fraction, medianDelay] = localFollowFraction( ...
        sourceTimes, targetTimes, minimumDelay, maximumDelay)
sourceTimes = double(sourceTimes(:));
targetTimes = double(targetTimes(:));
if isempty(sourceTimes)
    fraction = 1;
    medianDelay = 0;
    return;
end
delays = nan(size(sourceTimes));
for index = 1:numel(sourceTimes)
    candidates = targetTimes - sourceTimes(index);
    candidates = candidates(candidates >= minimumDelay & ...
        candidates <= maximumDelay);
    if ~isempty(candidates), delays(index) = min(candidates); end
end
valid = isfinite(delays);
fraction = mean(valid);
if any(valid), medianDelay = median(delays(valid)); else, medianDelay = inf; end
end

function profile = localProfile(data, count)
source = linspace(0, 1, size(data, 1)).';
target = linspace(0, 1, count).';
profile = interp1(source, data, target, "linear");
end

function profile = localEventProfile(time, events, count)
edges = linspace(time(1), time(end) + eps(time(end)), count + 1);
profile = zeros(count, size(events, 2));
active = events > 0.5;
rising = diff([false(1, size(active, 2)); active], 1, 1) > 0;
for bin = 1:count
    selected = time >= edges(bin) & time < edges(bin + 1);
    profile(bin, :) = sum(rising(selected, :), 1);
end
end

function localClearOutputs
names = ["F90_XMED05_EGMTap", "F90_XMED05_EventTap", ...
    "CardiacEGM", "PacingEvents"];
for index = 1:numel(names)
    evalin("base", "clear " + names(index));
end
end

function binding = localFilePresence(pathValue)
assert(isfile(pathValue), "SimuVerity:FileMissing", "Required file is missing: %s", pathValue);
binding = "present";
end

function value = localError(ME)
value = struct("identifier", string(ME.identifier), ...
    "message", string(ME.message), ...
    "stack", string({ME.stack.name}));
end

function value = localNow
value = string(datetime("now", "TimeZone", "Asia/Shanghai", ...
    "Format", "yyyy-MM-dd'T'HH:mm:ssXXX"));
end

function localWriteJson(pathValue, value)
fid = fopen(pathValue, "w", "n", "UTF-8");
assert(fid >= 0, "SimuVerity:F90:XMED05:JsonOpen", "Could not open JSON output.");
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, "%s\n", jsonencode(value, PrettyPrint=true));
end

function value = localTernary(condition, yesValue, noValue)
if condition, value = yesValue; else, value = noValue; end
end

function root = localProjectRoot
root = fileparts(mfilename("fullpath"));
for level = 1:4, root = fileparts(root); end
end

function localRestore(oldPath, oldDir)
try, path(oldPath); catch, end
try, cd(oldDir); catch, end
end
