function evidence = f90_xmech02_extract_evidence(modelPath, outDir)
%F90_XMECH02_EXTRACT_EVIDENCE Run scenarios and save score-free evidence.
%
% This file contains no group weights, score thresholds, or total formula.
% The exact-file binding direct golden uses its native logs; every other model must
% implement the standardized public Timeseries contract.
arguments
    modelPath (1,1) string
    outDir (1,1) string
end
extractionWall = tic;

root = localProjectRoot;
taskRoot = string(getenv("SIMUVERITY_TASK_ROOT"));
officialPath = simuverity_official_scenarios_path();
official = jsondecode(fileread(officialPath));
assert(isfile(modelPath), "SimuVerity:F90:XMECH02:ModelMissing", ...
    "Model under score is missing: %s", modelPath);
if ~isfolder(outDir), mkdir(outDir); end

addpath(fullfile(root, "scripts", "xp9"));
modelPresence = lower(string(xp9_file_presence_file(modelPath)));
referencePresence = "present";
evaluationSubject = localEvaluationSubject;
if evaluationSubject == "reference"
    assert(modelPresence == referencePresence, "SimuVerity:F90:XMECH02:ReferenceSubjectIdentity", ...
        "Reference evaluation requires the exact task-bound model.");
end
isDirectReference = evaluationSubject == "reference" && modelPresence == referencePresence;
[~, model] = fileparts(modelPath);

evidence = struct;
evidence.schema = "simuverity.f90-xmech02-evidence.v1";
evidence.formal_id = "F90-XMECH-02";
evidence.design_revision = "wind-turbine-direct-golden-static";
evidence.scenario_contract_id = ...
    string(official.scenario_contract_id);
evidence.official_scenarios_file_presence = lower(string( ...
    xp9_file_presence_file(officialPath)));
evidence.model_path = modelPath;
evidence.model_file_presence = modelPresence;
evidence.adapter = "standard_public_outputs";
if isDirectReference
    evidence.adapter = "reference_native";
end
evidence.reference_subject = logical(isDirectReference);
evidence.load_pass = false;
evidence.update_pass = false;
evidence.compile_pass = false;
evidence.scenarios = repmat(localEmptyScenarioRow, ...
    numel(official.scenarios), 1);
evidence.static_audit = struct;
evidence.errors = struct;
evidence.extraction_only = true;
% Canonical Unified dispatcher field.  Keep the task-local source field
% below because the current offline scorer validates it explicitly.
evidence.contains_score_decisions = false;
evidence.contains_score_or_threshold_decisions = false;
evidence.started_at = localNow;
evidence.runtime_identity = localRuntimeIdentity;
evidence.fast_restart = struct( ...
    "requested", false, ...
    "enabled", false, ...
    "used_for_scenarios", false, ...
    "enable_error", struct);

cacheDir = string(getenv("SIMULINK_CACHE_FOLDER"));
codegenDir = string(getenv("SIMULINK_CODEGEN_FOLDER"));
assert(strlength(cacheDir) > 0 && strlength(codegenDir) > 0, ...
    "SimuVerity:F90:XMECH02:Isolation", ...
    "Isolated Simulink cache and codegen folders are required.");
Simulink.fileGenControl("set", "CacheFolder", cacheDir, ...
    "CodeGenFolder", codegenDir, "createDir", true);
set(groot, "defaultFigureVisible", "off");

project = [];
sourceRoot = "";
if isDirectReference
    runtimeRoot = string(getenv("SIMUVERITY_RUNTIME_SUBMISSION_BUNDLE"));
    sourceRoot = fullfile(runtimeRoot, "Simscape-Wind-Turbine");
end
sourceBindingBefore = "";
sourceBindingAfter = "";
sourceAssetsBefore = false;
sourceAssetsAfter = false;
sourceTreeCleanBefore = false;
sourceTreeCleanAfter = false;
scenarioArtifacts = repmat(struct("id", "", "outputs", struct), ...
    numel(official.scenarios), 1);
rows = evidence.scenarios;
fastRestartEnabled = false;

try
    if isDirectReference
        [verifiedPath, sourceTreeCleanBefore] = f90_xmech02_build_reference;
        verifiedPath = string(verifiedPath);
        assert(localSamePath(verifiedPath, modelPath, root), ...
            "SimuVerity:F90:XMECH02:DirectReferencePath", ...
            "Exact binding matched but the registered direct-golden path differs.");
        sourceBindingBefore = lower(string(xp9_file_presence_file(modelPath)));
        sourceAssetsBefore = sourceTreeCleanBefore;
        project = openProject(fullfile(sourceRoot, "Wind_Turbine.prj"));
    end

    load_system(modelPath);
    evidence.load_pass = true;
    if isDirectReference
        % R2025a exposes the pinned configuration's native To Workspace
        % variables through SimulationOutput when single-output mode is on.
        % This is the same route verified by the read-only source smoke.
        set_param(model, "ReturnWorkspaceOutputs", "on");
        localSelectDetailedConfiguration(model);
        localValidateDetailedConfiguration(model);
        localEnableReferenceLogging(model);
    else
        set_param(model, "ReturnWorkspaceOutputs", "on");
        localApplyScenario(model, official.scenarios(1), false);
    end

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
            try, feval(model, [], [], [], "term"); catch, end
        end
    end

    evidence.static_audit = localStaticAudit(model, isDirectReference);
    if ~isDirectReference
        % Candidate scenarios share one compiled model.  Without Fast
        % Restart, every official scenario recompiles the same Simscape
        % network even though only the public wind histories change.
        % That made this evaluator many times slower than the Agent's
        % ordinary simulation and, on long runs, could exhaust the MATLAB
        % process before evidence was written.
        evidence.fast_restart.requested = true;
        try
            set_param(model, "FastRestart", "on");
            fastRestartEnabled = true;
            evidence.fast_restart.enabled = true;
            evidence.fast_restart.used_for_scenarios = true;
        catch ME
            % Fast Restart is an execution optimization, not a candidate
            % qualification rule.  Models that do not support it retain
            % the original one-simulation-at-a-time behavior.
            evidence.fast_restart.enable_error = localError(ME);
        end
    end
    for index = 1:numel(official.scenarios)
        scenario = official.scenarios(index);
        row = localEmptyScenarioRow;
        row.id = string(scenario.id);
        row.class = string(scenario.class);
        row.requested_inputs = struct( ...
            "time_s", double(scenario.time_s(:))', ...
            "wind_speed_mps", double(scenario.wind_speed_mps(:))', ...
            "wind_direction_deg", ...
                double(scenario.wind_direction_deg(:))');
        row.static_audit = evidence.static_audit;
        scenarioArtifacts(index).id = row.id;
        scenarioWall = tic;
        fprintf("F90_XMECH02_SCENARIO_START index=%d id=%s fast_restart=%d\n", ...
            index, row.id, fastRestartEnabled);
        try
            localApplyScenario(model, scenario, isDirectReference);
            if isDirectReference
                localClearReferenceOutputs;
                simInput = Simulink.SimulationInput(model);
                simInput = simInput.setModelParameter( ...
                    "StopTime", string(double(scenario.time_s(end))), ...
                    "ReturnWorkspaceOutputs", "on");
                simOut = sim(simInput);
                outputs = localReferenceOutputs(simOut);
            else
                simInput = localCandidateSimulationInput(model, scenario);
                simInput = simInput.setModelParameter( ...
                    "StopTime", string(double(scenario.time_s(end))), ...
                    "ReturnWorkspaceOutputs", "on");
                simOut = sim(simInput);
                outputs = localPublicOutputs(simOut);
            end
            row = localScenarioMetrics(row, outputs, scenario);
            scenarioArtifacts(index).outputs = outputs;
        catch ME
            row.valid = false;
            row.simulation_pass = false;
            row.error = localError(ME);
            if index == 1 && (startsWith(string(ME.identifier), ...
                    "SimuVerity:F90:XMECH02:Output") || startsWith( ...
                    string(ME.identifier), ...
                    "SimuVerity:F90:XMECH02:ReferenceLogContract"))
                row.simulation_wall_seconds = toc(scenarioWall);
                rethrow(ME);
            end
        end
        row.simulation_wall_seconds = toc(scenarioWall);
        fprintf("F90_XMECH02_SCENARIO_FINISH index=%d id=%s valid=%d wall_s=%.3f\n", ...
            index, row.id, row.valid, row.simulation_wall_seconds);
        rows(index) = row;
    end
    evidence.scenarios = rows;
catch ME
    evidence.errors.setup_or_extraction = localError(ME);
end

if fastRestartEnabled
    try
        set_param(model, "FastRestart", "off");
    catch ME
        evidence.errors.fast_restart_shutdown = localError(ME);
    end
end

modelClosed = localCloseModel(model);
tapLibrariesClosed = localCloseReferenceTapLibraries;
projectClosed = localCloseProject(project);
if isDirectReference
    sourceBindingAfter = lower(string(xp9_file_presence_file(modelPath)));
    try
        [~, sourceTreeCleanAfter] = f90_xmech02_build_reference;
        sourceAssetsAfter = sourceTreeCleanAfter;
    catch ME
        evidence.errors.reference_after = localError(ME);
    end
    evidence.direct_reference_integrity = struct( ...
        "expected_file_presence", referencePresence, ...
        "before_file_presence", sourceBindingBefore, ...
        "after_file_presence", sourceBindingAfter, ...
        "source_binding_preserved", ...
            sourceBindingBefore == referencePresence && ...
            sourceBindingAfter == referencePresence, ...
        "required_assets_preserved", ...
            sourceAssetsBefore && sourceAssetsAfter, ...
        "tracked_tree_clean_before", sourceTreeCleanBefore, ...
        "tracked_tree_clean_after", sourceTreeCleanAfter, ...
        "model_closed", modelClosed, ...
        "tap_libraries_closed_without_save", tapLibrariesClosed, ...
        "project_closed", projectClosed, ...
        "model_saved", false, ...
        "core_modified", false, ...
        "substantive_adjustments", 0);
end

rawPath = fullfile(outDir, "raw_evidence.mat");
save(rawPath, "scenarioArtifacts", "-v7.3");
evidence.raw_artifact = struct( ...
    "path", string(rawPath), ...
    "file_presence", lower(string(xp9_file_presence_file(rawPath))), ...
    "format", "MAT-v7.3", ...
    "variable", "scenarioArtifacts");
evidence.finished_at = localNow;
evidence.total_wall_seconds = toc(extractionWall);
localWriteJson(fullfile(outDir, "evidence.json"), evidence);
fprintf("F90_XMECH02_EVIDENCE adapter=%s scenarios=%d out=%s\n", ...
    evidence.adapter, numel(evidence.scenarios), outDir);
end

function localSelectDetailedConfiguration(model)
assert(model == "Wind_Turbine", "SimuVerity:F90:XMECH02:ReferenceModelName", ...
    "The registered direct golden must load as Wind_Turbine.");
assert(evalin("base", "exist('WT_Configs','var') == 1"), ...
    "SimuVerity:F90:XMECH02:ReferenceWorkspace", ...
    "The pinned project did not initialize WT_Configs.");
evalin("base", ...
    "Select_Turbine_Systems('H_Pitch S_Yaw Ge Gn Segments', WT_Configs);");
end

function localValidateDetailedConfiguration(model)
paths = [ ...
    model + "/Blade Load"
    model + "/Nacelle/Geartrain"
    model + "/Nacelle/Generator"
    model + "/Nacelle/Hub Axis"
    model + "/Turbine Input"
    model + "/Main Controller"
    model + "/Nacelle/Pitch System"
    model + "/Pitch Controller"
    model + "/Nacelle/Yaw System"];
expected = [ ...
    "Segments"
    "Ideal"
    "Full"
    "Rotate"
    "Wind"
    "Wind_Input"
    "Hydraulic"
    "PI_on_AoA"
    "Servomotor"];
for index = 1:numel(paths)
    actual = string(get_param(paths(index), "OverrideUsingVariant"));
    assert(actual == expected(index), ...
        "SimuVerity:F90:XMECH02:DetailedConfiguration", ...
        "Detailed configuration mismatch at %s: %s", ...
        paths(index), actual);
end
yaw = model + "/Yaw Controller";
source = localParam(yaw, "SourceBlock");
if strlength(source) == 0
    source = localParam(yaw, "ReferenceBlock");
end
assert(endsWith(replace(source, "\", "/"), ...
        "Yaw_Controller_Lib/Speed Limit"), ...
    "SimuVerity:F90:XMECH02:YawControllerReference", ...
    "Yaw Controller is not linked to the required fixed Speed Limit implementation.");
end

function localEnableReferenceLogging(model)
% The official scopes record actuator 1 only, although the active
% hydraulic-pitch and servomotor-yaw variants contain three and four
% distinct connected physical actuators. Mark those existing force/torque
% output lines for unsaved external logging.
blocks = string(find_system(model, "LookUnderMasks", "all", ...
    "FollowLinks", "on", "MatchFilter", ...
    @Simulink.match.activeVariants, "Type", "Block"));
sources = strings(size(blocks));
for index = 1:numel(blocks)
    sources(index) = replace(localParam(blocks(index), ...
        "SourceBlock"), "\", "/");
end
pitch = blocks(endsWith(sources, ...
    "Hydraulic_Actuator_Lib/Actuator_1"));
yaw = blocks(endsWith(sources, "Yaw_Motor_Lib/Yaw Motor"));
if isempty(pitch) || isempty(yaw)
    % Subsystem-reference internals are opaque to find_system from the
    % harness model in R2025a. Configure the exact linked library sources
    % in memory; the changes are never saved.
    load_system("Pitch_Actuation_Lib");
    load_system("Yaw_Actuation_Lib");
    set_param("Pitch_Actuation_Lib", "Lock", "off");
    set_param("Yaw_Actuation_Lib", "Lock", "off");
    pitch = [ ...
        "Pitch_Actuation_Lib/Hydraulic/Actuator_1"
        "Pitch_Actuation_Lib/Hydraulic/Actuator_2"
        "Pitch_Actuation_Lib/Hydraulic/Actuator_3"];
    yaw = [ ...
        "Yaw_Actuation_Lib/Servomotor/Yaw Motor 1"
        "Yaw_Actuation_Lib/Servomotor/Yaw Motor 2"
        "Yaw_Actuation_Lib/Servomotor/Yaw Motor 3"
        "Yaw_Actuation_Lib/Servomotor/Yaw Motor 4"];
end
pitch = localSortActuatorBlocks(pitch, "Actuator_");
yaw = localSortActuatorBlocks(yaw, "Yaw Motor ");
assert(numel(pitch) == 3, "SimuVerity:F90:XMECH02:PitchTapLocator", ...
    "Expected three active hydraulic pitch actuators, found %d.", ...
    numel(pitch));
assert(numel(yaw) == 4, "SimuVerity:F90:XMECH02:YawTapLocator", ...
    "Expected four active electric yaw motors, found %d.", numel(yaw));

set_param(model, "SignalLogging", "on", ...
    "SignalLoggingName", "logsout", ...
    "SignalLoggingSaveFormat", "Dataset");
for index = 1:numel(pitch)
    localMarkOutputForLogging(pitch(index), 3, ...
        "f90_xmech02_pitch_force_" + index);
end
for index = 1:numel(yaw)
    localMarkOutputForLogging(yaw(index), 3, ...
        "f90_xmech02_yaw_torque_" + index);
end
end

function blocks = localSortActuatorBlocks(blocks, prefix)
number = zeros(size(blocks));
for index = 1:numel(blocks)
    [~, name] = fileparts(blocks(index));
    number(index) = str2double(extractAfter(string(name), prefix));
end
assert(all(isfinite(number)), "SimuVerity:F90:XMECH02:TapName", ...
    "Physical actuator names do not expose stable numeric identities.");
[~, order] = sort(number);
blocks = blocks(order);
end

function localMarkOutputForLogging(block, portIndex, logName)
ports = get_param(block, "PortHandles");
assert(numel(ports.Outport) >= portIndex, ...
    "SimuVerity:F90:XMECH02:TapPort", ...
    "Required physical output is missing at %s#out:%d.", ...
    block, portIndex);
line = get_param(ports.Outport(portIndex), "Line");
assert(line > 0, "SimuVerity:F90:XMECH02:TapLine", ...
    "Required physical output is not connected at %s#out:%d.", ...
    block, portIndex);
set_param(ports.Outport(portIndex), "DataLogging", "on", ...
    "DataLoggingNameMode", "Custom", ...
    "DataLoggingName", logName);
end

function audit = localStaticAudit(model, isDirectReference)
if isDirectReference
    audit = struct( ...
        "three_blade_aerodynamic_path", true, ...
        "hydraulic_pitch_path_count", 3, ...
        "electric_yaw_path_count", 4, ...
        "drivetrain_generator_grid_path", true, ...
        "measured_pitch_feedback", true, ...
        "measured_yaw_feedback", true, ...
        "basis", "exact pinned configuration and real physical ports");
    return;
end
blocks = string(find_system(model, "LookUnderMasks", "all", ...
    "FollowLinks", "on", "Type", "Block"));
description = lower(blocks);
for index = 1:numel(blocks)
    description(index) = lower(blocks(index) + " " + ...
        localParam(blocks(index), "ReferenceBlock") + " " + ...
        localParam(blocks(index), "SourceBlock") + " " + ...
        localParam(blocks(index), "MaskType"));
end
pitchPhysical = contains(description, "pitch") & ...
    (contains(description, "hydraulic") | contains(description, "cylinder"));
yawPhysical = contains(description, "yaw") & ...
    (contains(description, "motor") | contains(description, "gear"));
audit = struct( ...
    "three_blade_aerodynamic_path", ...
        nnz(contains(description, "blade") & ...
        (contains(description, "aero") | contains(description, "lift") | ...
        contains(description, "drag"))) >= 3, ...
    "hydraulic_pitch_path_count", min(3, nnz(pitchPhysical)), ...
    "electric_yaw_path_count", min(4, nnz(yawPhysical)), ...
    "drivetrain_generator_grid_path", ...
        any(contains(description, "gear")) && ...
        any(contains(description, "generator")) && ...
        any(contains(description, "grid")), ...
    "measured_pitch_feedback", ...
        any(contains(description, "pitch") & ...
        (contains(description, "sensor") | contains(description, "measure"))), ...
    "measured_yaw_feedback", ...
        any(contains(description, "yaw") & ...
        (contains(description, "sensor") | contains(description, "measure"))), ...
    "basis", ...
        "generic connected-model inventory; behavior is cross-checked by physical efforts and delayed responses");
end

function localApplyScenario(model, scenario, isDirectReference)
time = double(scenario.time_s(:));
speed = double(scenario.wind_speed_mps(:));
direction = double(scenario.wind_direction_deg(:));
assert(numel(time) == numel(speed) && numel(time) == numel(direction) && ...
    time(1) == 0 && all(diff(time) > 0), ...
    "SimuVerity:F90:XMECH02:ScenarioShape", ...
    "Official wind profiles must have equal lengths and increasing time.");
assignin("base", "wind_time_s", time);
assignin("base", "wind_speed_mps", speed);
assignin("base", "wind_direction_deg", direction);
if isDirectReference
    windBlock = model + "/Turbine Input/Wind/Wind Input";
    [~, ~, ~, groupNames] = signalbuilder(windBlock);
    assert(~isempty(groupNames), "SimuVerity:F90:XMECH02:WindInput", ...
        "The source wind interface has no Signal Builder group.");
    group = 1;
    signalbuilder(windBlock, "set", 1, group, time, speed);
    signalbuilder(windBlock, "set", 2, group, time, direction);
    signalbuilder(windBlock, "activegroup", group);
end
set_param(model, "StopTime", string(time(end)));
end

function simInput = localCandidateSimulationInput(model, scenario)
% Bind each official public-input profile to this simulation explicitly.
% This keeps scenario changes tunable while Fast Restart holds the compiled
% Simscape network and prevents a stale base-workspace profile from being
% reused across simulations.
simInput = Simulink.SimulationInput(model);
simInput = simInput.setVariable("wind_time_s", ...
    double(scenario.time_s(:)));
simInput = simInput.setVariable("wind_speed_mps", ...
    double(scenario.wind_speed_mps(:)));
simInput = simInput.setVariable("wind_direction_deg", ...
    double(scenario.wind_direction_deg(:)));
end

function localClearReferenceOutputs
names = [ ...
    "Wind_Turbine_Wind_DATA1"
    "Blade_Pitch_DATA"
    "Pitch_Actuator_Force_DATA"
    "Nacelle_Yaw_DATA"
    "Yaw_Actuator_Torque_DATA1"
    "Generator_Speed_DATA"
    "Geartrain_Input_Torque_DATA"
    "Generator_Power_DATA"];
for name = names'
    evalin("base", "clear " + name);
end
end

function simOut = localSimReferenceInBase(model, stopTime)
% The upstream subsystem-reference To Workspace blocks write into the
% base workspace on R2025a when the model's native single-output setting is
% preserved.  Match the official example's no-output sim call.
assignin("base", "f90_xmech02_model_name", char(model));
assignin("base", "f90_xmech02_stop_time", char(string(stopTime)));
cleanup = onCleanup(@() evalin("base", ...
    "clear f90_xmech02_model_name f90_xmech02_stop_time " + ...
    "f90_xmech02_simout")); %#ok<NASGU>
evalin("base", ...
    "set_param(f90_xmech02_model_name, " + ...
    "'StopTime', f90_xmech02_stop_time, " + ...
    "'ReturnWorkspaceOutputs', 'off'); " + ...
    "sim(f90_xmech02_model_name);");
simOut = [];
end

function outputs = localReferenceOutputs(simOut)
wind = localSeries(localGet(simOut, "Wind_Turbine_Wind_DATA1"));
pitch = localSeries(localGet(simOut, "Blade_Pitch_DATA"));
yaw = localSeries(localGet(simOut, "Nacelle_Yaw_DATA"));
speed = localSeries(localGet(simOut, "Generator_Speed_DATA"));
driveTorque = localSeries(localGet(simOut, "Geartrain_Input_Torque_DATA"));
power = localSeries(localGet(simOut, "Generator_Power_DATA"));

hydraulic = localLoggedActuatorMatrix(simOut, ...
    "f90_xmech02_pitch_force_", 3, pitch.time);
yawTorque = localLoggedActuatorMatrix(simOut, ...
    "f90_xmech02_yaw_torque_", 4, yaw.time);
logWidths = [size(wind.data, 2), size(pitch.data, 2), 3, ...
    size(yaw.data, 2), 4, size(speed.data, 2), ...
    size(driveTorque.data, 2), size(power.data, 2)];
assert(logWidths(1) >= 2 && logWidths(2) >= 2 && ...
    size(yaw.data, 2) >= 2 && size(speed.data, 2) >= 2 && ...
    size(driveTorque.data, 2) >= 1 && size(power.data, 2) >= 1, ...
    "SimuVerity:F90:XMECH02:ReferenceLogContract", ...
    "Pinned direct-golden log widths are [%s], expected at least [2 2 3 2 4 2 1 1].", ...
    strjoin(string(logWidths), " "));

t = wind.time;
yawMeasured = localInterp(yaw, t, 1);
outputs = struct;
outputs.wind_response = localOutput(t, ...
    [wind.data(:, 1:2), yawMeasured]);
outputs.pitch_response = localOutput(pitch.time, ...
    [pitch.data(:, 2), pitch.data(:, 1)]);
outputs.hydraulic_effort = hydraulic;
outputs.yaw_response = localOutput(yaw.time, ...
    [yaw.data(:, 2), yaw.data(:, 1), yawTorque.data]);
outputs.drivetrain_response = localOutput(speed.time, ...
    [speed.data(:, 1) * (2*pi/60), speed.data(:, 2), ...
    localInterp(driveTorque, speed.time, 1)]);
outputs.generation_response = localOutput(power.time, power.data(:, 1));
end

function matrix = localLoggedActuatorMatrix(simOut, prefix, count, time)
logs = localGet(simOut, "logsout");
assert(isa(logs, "Simulink.SimulationData.Dataset"), ...
    "SimuVerity:F90:XMECH02:TapDataset", ...
    "Reference measurement taps did not return a Dataset.");
data = zeros(numel(time), count);
for index = 1:count
    name = prefix + index;
    element = logs.getElement(char(name));
    assert(~isempty(element), "SimuVerity:F90:XMECH02:TapMissing", ...
        "Reference measurement tap is missing: %s", name);
    series = localSeries(element);
    assert(size(series.data, 2) == 1, ...
        "SimuVerity:F90:XMECH02:TapWidth", ...
        "Reference measurement tap must be scalar: %s", name);
    data(:, index) = localInterp(series, time, 1);
end
matrix = localOutput(time, data);
end

function outputs = localPublicOutputs(simOut)
names = [ ...
    "wind_response"
    "pitch_response"
    "hydraulic_effort"
    "yaw_response"
    "drivetrain_response"
    "generation_response"];
channels = [3 2 3 6 3 1];
outputs = struct;
for index = 1:numel(names)
    series = localSeries(simuverity_public_output_compatibility( ...
        simOut,names(index),channels(index),AllowBaseWorkspace=true));
    assert(size(series.data, 2) == channels(index), ...
        "SimuVerity:F90:XMECH02:PublicOutputChannels", ...
        "%s must contain exactly %d channels.", ...
        names(index), channels(index));
    outputs.(names(index)) = series;
end
end

function row = localScenarioMetrics(row, outputs, scenario)
names = [ ...
    "wind_response"
    "pitch_response"
    "hydraulic_effort"
    "yaw_response"
    "drivetrain_response"
    "generation_response"];
requiredChannels = [3 2 3 6 3 1];
complete = true;
finiteCount = 0;
valueCount = 0;
minimumSamples = inf;
requestedEnd = double(scenario.time_s(end));
for index = 1:numel(names)
    series = outputs.(names(index));
    complete = complete && size(series.data, 2) == ...
        requiredChannels(index) && numel(series.time) >= 2 && ...
        series.time(1) <= max(1e-6, requestedEnd * 1e-3) && ...
        series.time(end) >= requestedEnd - max(1e-6, requestedEnd * 1e-3);
    finiteCount = finiteCount + nnz(isfinite(series.data));
    valueCount = valueCount + numel(series.data);
    minimumSamples = min(minimumSamples, numel(series.time));
end

t = outputs.wind_response.time;
wind = outputs.wind_response.data;
pitch = localInterp(outputs.pitch_response, t, 1:2);
hydraulic = localInterp(outputs.hydraulic_effort, t, 1:3);
yaw = localInterp(outputs.yaw_response, t, 1:6);
drive = localInterp(outputs.drivetrain_response, t, 1:3);
power = localInterp(outputs.generation_response, t, 1);
targetSpeed = interp1(double(scenario.time_s(:)), ...
    double(scenario.wind_speed_mps(:)), t, "linear", "extrap");
targetDirection = interp1(double(scenario.time_s(:)), ...
    double(scenario.wind_direction_deg(:)), t, "linear", "extrap");
eventTime = localEventTime(scenario);
post = t >= eventTime;
final = t >= t(1) + 0.85 * (t(end) - t(1));
pre = t < eventTime;
if nnz(pre) < 2, pre = t <= t(1) + 0.15 * (t(end)-t(1)); end
if nnz(post) < 2, post = true(size(t)); end
if nnz(final) < 2, final = t >= t(max(1, end-1)); end

yawError = localWrap180(targetDirection - wind(:, 3));
pitchError = pitch(:, 1) - pitch(:, 2);
hydraulicRanges = localColumnRanges(hydraulic);
yawTorqueRanges = localColumnRanges(yaw(:, 3:6));
rotorCv = localCv(drive(final, 1));
powerCv = localCv(power(final, 1));

metrics = struct;
metrics.wind_speed_binding_rmse_mps = localRmse(wind(:, 1)-targetSpeed);
metrics.wind_direction_binding_rmse_deg = ...
    localRmse(localWrap180(wind(:, 2)-targetDirection));
metrics.pitch_tracking_rmse_deg = localRmse(pitchError);
metrics.pitch_post_event_peak_abs_error_deg = ...
    max(abs(pitchError(post)));
metrics.pitch_final_abs_error_deg = mean(abs(pitchError(final)));
metrics.pitch_measurement_range_deg = ...
    max(pitch(:, 2))-min(pitch(:, 2));
metrics.hydraulic_force_active_channels = ...
    localActiveChannelCount(hydraulic);
metrics.hydraulic_force_range_n = max(hydraulicRanges);
metrics.hydraulic_force_channel_balance = ...
    localChannelBalance(hydraulicRanges);
metrics.yaw_initial_abs_error_deg = mean(abs(yawError(pre)));
metrics.yaw_post_event_peak_abs_error_deg = max(abs(yawError(post)));
metrics.yaw_final_abs_error_deg = mean(abs(yawError(final)));
metrics.yaw_error_reduction_fraction = localReduction( ...
    metrics.yaw_post_event_peak_abs_error_deg, ...
    metrics.yaw_final_abs_error_deg);
metrics.yaw_tracking_rmse_deg = localRmse(yaw(:, 1)-yaw(:, 2));
metrics.yaw_signed_response_deg = ...
    mean(yaw(final, 2)) - mean(yaw(pre, 2));
metrics.yaw_motor_active_channels = ...
    localActiveChannelCount(yaw(:, 3:6));
metrics.yaw_motor_torque_range_nm = max(yawTorqueRanges);
metrics.yaw_motor_channel_balance = ...
    localChannelBalance(yawTorqueRanges);
metrics.rotor_speed_range_rad_s = ...
    max(drive(:, 1))-min(drive(:, 1));
metrics.generator_speed_range_rpm = ...
    max(drive(:, 2))-min(drive(:, 2));
metrics.drivetrain_torque_range_nm = ...
    max(drive(:, 3))-min(drive(:, 3));
metrics.generator_power_range_w = ...
    max(power(:, 1))-min(power(:, 1));
metrics.generator_energy_abs_j = trapz(t, abs(power(:, 1)));
powerScale = max(max(abs(power(:, 1))), 1);
metrics.power_nonzero_fraction = ...
    mean(abs(power(:, 1)) > powerScale * 1e-4);
metrics.pitch_command_copy_rmse_deg = localRmse(pitchError);
metrics.yaw_command_copy_rmse_deg = localRmse(yaw(:, 1)-yaw(:, 2));
windEvent = hypot(targetSpeed-targetSpeed(1), ...
    localWrap180(targetDirection-targetDirection(1)));
metrics.wind_to_torque_lag_s = ...
    localResponseLag(t, windEvent, abs(drive(:, 3)));
metrics.torque_to_power_lag_s = ...
    localResponseLag(t, abs(drive(:, 3)), abs(power(:, 1)));
metrics.pitch_effort_to_motion_lag_s = ...
    localResponseLag(t, max(abs(hydraulic), [], 2), pitch(:, 2));
metrics.yaw_effort_to_motion_lag_s = ...
    localResponseLag(t, max(abs(yaw(:, 3:6)), [], 2), yaw(:, 2));
metrics.steady_rotor_speed_cv = rotorCv;
metrics.steady_power_cv = powerCv;
metrics.finite_fraction = finiteCount / max(valueCount, 1);

row.metrics = metrics;
row.samples = minimumSamples;
row.time_start_s = t(1);
row.time_end_s = t(end);
row.duration_s = t(end)-t(1);
row.scenario_applied = true;
row.simulation_pass = true;
row.output_contract_pass = complete;
row.finite_pass = finiteCount == valueCount;
row.valid = row.simulation_pass && row.output_contract_pass && ...
    row.finite_pass;
row.error = struct;
end

function value = localGet(simOut, name)
value = [];
try, value = simOut.get(name); catch, end
if isempty(value)
    try
        if evalin("base", "exist('" + name + "','var') == 1")
            value = evalin("base", name);
        end
    catch
    end
end
if isempty(value)
    try
        loaded = string(find_system("type", "block_diagram"));
        for model = loaded'
            workspace = get_param(model, "ModelWorkspace");
            if workspace.hasVariable(char(name))
                value = workspace.getVariable(char(name));
                break;
            end
        end
    catch
    end
end
assert(~isempty(value), "SimuVerity:F90:XMECH02:OutputMissing", ...
    "Required simulation output is missing: %s", name);
end

function series = localSeries(value)
if isa(value, "Simulink.SimulationData.Signal")
    value = value.Values;
end
if isa(value, "timeseries")
    time = double(value.Time(:));
    data = double(value.Data);
elseif isstruct(value) && isfield(value, "time") && ...
        isfield(value, "signals")
    time = double(value.time(:));
    if numel(value.signals) == 1
        data = double(value.signals.values);
    else
        data = [];
        for index = 1:numel(value.signals)
            data = [data, double(value.signals(index).values)]; %#ok<AGROW>
        end
    end
elseif isstruct(value) && isfield(value, "Time") && isfield(value, "Data")
    time = double(value.Time(:));
    data = double(value.Data);
else
    error("SimuVerity:F90:XMECH02:OutputType", ...
        "Required output is not a Timeseries-compatible value.");
end
data = squeeze(data);
if isvector(data), data = data(:); end
assert(size(data, 1) == numel(time), "SimuVerity:F90:XMECH02:OutputTime", ...
    "Output time and data lengths differ.");
[time, keep] = unique(time, "stable");
data = data(keep, :);
series = localOutput(time, data);
end

function series = localOutput(time, data)
series = struct("time", double(time(:)), "data", double(data));
end

function data = localInterp(series, time, columns)
data = interp1(series.time, series.data(:, columns), ...
    time, "linear", "extrap");
end

function value = localRmse(error)
error = double(error(:));
value = sqrt(mean(error.^2));
end

function value = localReduction(peakValue, finalValue)
value = max(0, min(1, 1-finalValue/max(peakValue, 1e-12)));
end

function values = localColumnRanges(data)
values = max(data, [], 1)-min(data, [], 1);
end

function count = localActiveChannelCount(data)
ranges = localColumnRanges(data);
scale = max(max(abs(data), [], 1), 1);
count = nnz(ranges > scale*1e-8);
end

function value = localChannelBalance(ranges)
if isempty(ranges) || max(ranges) <= 0
    value = 0;
else
    value = min(ranges)/max(ranges);
end
end

function value = localCv(data)
data = double(data(:));
value = std(data)/max(abs(mean(data)), max(std(data)*1e-6, 1e-12));
end

function value = localResponseLag(time, input, response)
inputIndex = localFirstChange(input);
responseIndex = localFirstChange(response);
if isempty(inputIndex) || isempty(responseIndex)
    value = 0;
else
    value = double(time(responseIndex)-time(inputIndex));
end
end

function index = localFirstChange(data)
data = double(data(:));
baselineCount = max(2, min(numel(data), ceil(0.1*numel(data))));
baseline = mean(data(1:baselineCount));
span = max(data)-min(data);
if ~isfinite(span) || span <= 1e-12
    index = [];
    return;
end
index = find(abs(data-baseline) >= 0.05*span, 1, "first");
end

function time = localEventTime(scenario)
values = [double(scenario.wind_speed_mps(:)), ...
    double(scenario.wind_direction_deg(:))];
change = find(any(abs(diff(values, 1, 1)) > 0, 2), 1, "last") + 1;
if isempty(change), change = 2; end
time = double(scenario.time_s(change));
end

function value = localWrap180(value)
value = mod(double(value)+180, 360)-180;
end

function row = localEmptyScenarioRow
row = struct( ...
    "id", "", ...
    "class", "", ...
    "requested_inputs", struct, ...
    "input_file_presence", "", ...
    "valid", false, ...
    "simulation_pass", false, ...
    "output_contract_pass", false, ...
    "finite_pass", false, ...
    "scenario_applied", false, ...
    "samples", 0, ...
    "time_start_s", 0, ...
    "time_end_s", 0, ...
    "duration_s", 0, ...
    "simulation_wall_seconds", 0, ...
    "metrics", struct, ...
    "static_audit", struct, ...
    "error", struct);
end

function identity = localRuntimeIdentity
identity = struct( ...
    "generation_run_id", string(getenv("SIMUVERITY_GENERATION_RUN_ID")), ...
    "mcp_port", string(getenv("SIMUVERITY_MCP_PORT")), ...
    "matlab_release", string(version("-release")), ...
    "matlab_prefdir", string(getenv("MATLAB_PREFDIR")), ...
    "appdata", string(getenv("APPDATA")), ...
    "temp", string(getenv("TEMP")), ...
    "cache", string(getenv("SIMULINK_CACHE_FOLDER")), ...
    "codegen", string(getenv("SIMULINK_CODEGEN_FOLDER")));
end

function value = localParam(block, name)
value = "";
try, value = string(get_param(block, name)); catch, end
end

function subject = localEvaluationSubject
subject = lower(strtrim(string(getenv("SIMUVERITY_EVALUATION_SUBJECT"))));
if strlength(subject) == 0, subject = "candidate"; end
assert(any(subject == ["candidate", "reference"]), ...
    "SimuVerity:F90:XMECH02:EvaluationSubject", ...
    "SIMUVERITY_EVALUATION_SUBJECT must be candidate or reference.");
end

function closed = localCloseModel(model)
closed = true;
try
    if bdIsLoaded(model), close_system(model, 0); end
catch
    closed = false;
end
end

function closed = localCloseReferenceTapLibraries
closed = true;
libraries = ["Pitch_Actuation_Lib", "Yaw_Actuation_Lib"];
for library = libraries
    try
        if bdIsLoaded(library), close_system(library, 0); end
    catch
        closed = false;
    end
end
end

function closed = localCloseProject(project)
closed = true;
try
    if ~isempty(project), close(project); end
catch
    try
        active = currentProject;
        if ~isempty(active), close(active); end
    catch
        closed = false;
    end
end
end

function value = localSamePath(left, right, root)
left = localCanonicalPath(left, root);
right = localCanonicalPath(right, root);
value = strcmpi(char(left), char(right));
end

function path = localCanonicalPath(path, root)
path = string(path);
if ~isfile(path) && ~isfolder(path)
    candidate = fullfile(root, path);
    if isfile(candidate) || isfolder(candidate)
        path = candidate;
    end
elseif ~localIsAbsolute(path)
    path = fullfile(root, path);
end
path = string(java.io.File(char(path)).getCanonicalPath());
end

function value = localIsAbsolute(path)
path = char(string(path));
value = ~isempty(regexp(path, ...
    '^(?:[A-Za-z]:[\\/]|\\\\|//)', 'once'));
end

function value = localError(error)
value = struct( ...
    "identifier", string(error.identifier), ...
    "message", string(error.message), ...
    "report", string(getReport(error, "extended", ...
        "hyperlinks", "off")));
end

function value = localNow
value = string(datetime("now", "TimeZone", "local", ...
    "Format", "yyyy-MM-dd'T'HH:mm:ssXXX"));
end

function localWriteJson(path, value)
fid = fopen(path, "w", "n", "UTF-8");
assert(fid >= 0, "SimuVerity:F90:XMECH02:EvidenceWrite", ...
    "Cannot write evidence JSON.");
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fwrite(fid, jsonencode(value, PrettyPrint=true), "char");
end

function root = localProjectRoot
root = fileparts(mfilename("fullpath"));
for level = 1:4
    root = fileparts(root);
end
end
