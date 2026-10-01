function evidence = f90_xmech08_extract_evidence_core(modelPath, outDir)
%f90_xmech08_extract_evidence_core Extract all official evidence in one session.
arguments
    modelPath (1,1) string = ""
    outDir (1,1) string = ""
end

definition = f90_xmech08_definition;
root = localProjectRoot;
generationRunId = string(getenv("SIMUVERITY_GENERATION_RUN_ID"));
assert(strlength(generationRunId) > 0, "SimuVerity:F90:XMECH08:GenerationRunId", ...
    "SIMUVERITY_GENERATION_RUN_ID is required.");
if strlength(modelPath) == 0
    modelPath = string(definition.runner.reference_model);
end
assert(isfile(modelPath), "SimuVerity:F90:XMECH08:ModelMissing", ...
    "Model under evaluation is missing: %s", modelPath);
if strlength(outDir) == 0
    outDir = fullfile(root, "results", "cross_domain", ...
        "simuverity_public", "F90-XMECH-08", ...
        "fixed_evidence", generationRunId);
end
if ~isfolder(outDir), mkdir(outDir); end
evidencePath = fullfile(outDir, "evidence.json");
assert(~isfile(evidencePath), "SimuVerity:F90:XMECH08:OutputReuse", ...
    "Evidence already exists for GenerationRunId %s.", generationRunId);

localConfigureIsolation;
officialPath = string(definition.runner.official_scenarios);
official = jsondecode(fileread(officialPath));
modelPresence = localFilePresence(modelPath);
referencePresence = "present";
declaredReferencePresence = lower(strtrim(string( ...
    "present")));
if strlength(declaredReferencePresence) > 0
    assert(declaredReferencePresence == referencePresence, ...
        "SimuVerity:F90:XMECH08:ReferenceBinding", ...
        "Evaluator reference file presence differs from the task-bound reference.");
end
isReference = lower(strtrim(string(getenv("SIMUVERITY_EVALUATION_SUBJECT")))) == "reference";
[modelDir, model] = fileparts(modelPath);
projectDir = string(modelDir);
pathBefore = path;
referenceProjectRoot = "";
if isReference
    referenceProjectRoot = localInitializeReferenceProject(projectDir, model);
    addpath(referenceProjectRoot, ...
        fullfile(referenceProjectRoot, "Scripts_Data"), ...
        fullfile(referenceProjectRoot, "Workflows", "Optim"), "-begin");
end
pwdBefore = string(pwd);
cleanup = onCleanup(@() localCleanup(model, pwdBefore, pathBefore, ...
    isReference, referenceProjectRoot)); %#ok<NASGU>

evidence = struct;
evidence.schema = "simuverity.f90-xmech08-evidence.v1";
evidence.task_id = "F90-XMECH-08";
evidence.generation_run_id = generationRunId;
evidence.model_path = modelPath;
evidence.model_file_presence = modelPresence;
evidence.reference_subject = logical(isReference);
evidence.adapter = localTernary(isReference, ...
    "native_length_mapping_and_measured_xy_log", ...
    "public_timeseries_contract");
evidence.reference_substantive_modifications = 0;
evidence.extraction_only = true;
evidence.contains_score_decisions = false;
evidence.load_pass = false;
evidence.update_pass = false;
evidence.compile_pass = false;
evidence.simulate_pass = false;
evidence.scenarios = struct([]);
evidence.static_audit = struct;
evidence.source_profile = struct;
evidence.errors = struct([]);
evidence.model_closed_without_save = false;
evidence.reference_binding_preserved = false;
evidence.started_at = localNow;
evidence.runtime = struct( ...
    "matlab_start_count", 1, ...
    "generation_run_id", generationRunId, ...
    "one_session_all_scenarios", true, ...
    "evidence_is_current_after_success", true);

fatal = [];
try
    cd(modelDir);
    load_system(modelPath);
    evidence.load_pass = true;
    set_param(model, ...
        "SimulationMode", "normal", ...
        "ReturnWorkspaceOutputs", "on", ...
        "SignalLogging", "on", ...
        "LimitDataPoints", "off", ...
        "StopTime", "10");
    localAssignGeometry(official.scenarios(1), isReference);
    set_param(model, "SimulationCommand", "update");
    evidence.update_pass = true;
    feval(model, [], [], [], "compile");
    feval(model, [], [], [], "term");
    evidence.compile_pass = true;
    evidence.static_audit = localStaticAudit(model, isReference);
    evidence.source_profile = localSourceProfile(model);

    rows = repmat(localEmptyRow, 0, 1);
    for index = 1:numel(official.scenarios)
        scenario = official.scenarios(index);
        row = localEmptyRow;
        row.id = string(scenario.id);
        row.class = string(scenario.class);
        row.requested_inputs = struct( ...
            "CrankLength_m", double(scenario.CrankLength_m), ...
            "CouplerLength_m", double(scenario.CouplerLength_m));
        scenarioDir = fullfile(outDir, string(scenario.id));
        if ~isfolder(scenarioDir), mkdir(scenarioDir); end
        try
            localAssignGeometry(scenario, isReference);
            localClearPublicOutputs(isReference);
            simIn = Simulink.SimulationInput(model);
            simIn = simIn.setVariable("CrankLength_m", ...
                double(scenario.CrankLength_m));
            simIn = simIn.setVariable("CouplerLength_m", ...
                double(scenario.CouplerLength_m));
            if isReference
                simIn = simIn.setVariable("a", ...
                    double(scenario.CrankLength_m));
                simIn = simIn.setVariable("b", ...
                    double(scenario.CouplerLength_m));
                simIn = simIn.setVariable("c", 0.20);
                simIn = simIn.setVariable("d", 0.25);
                simIn = simIn.setVariable("h", 0.20);
            end
            simIn = simIn.setModelParameter( ...
                "SimulationMode", "normal", ...
                "ReturnWorkspaceOutputs", "on", ...
                "SignalLogging", "on", ...
                "LimitDataPoints", "off", ...
                "StopTime", "10");
            timer = tic;
            simOut = sim(simIn);
            row.wall_seconds = toc(timer);
            row.simulation_pass = true;
            signals = localCollectSignals(simOut, isReference);
            [row.metrics, row.trajectory] = ...
                localMetrics(signals, scenario);
            row.outputs_valid = localOutputsValid(row.metrics);
            artifact = fullfile(scenarioDir, "signals.mat");
            save(artifact, "-struct", "signals", "-v7");
            row.signal_artifact = localRelativePath(artifact, outDir);
            row.signal_file_presence = localFilePresence(artifact);
        catch ME
            row.error = localError(ME);
        end
        rows(end + 1, 1) = row; %#ok<AGROW>
    end
    evidence.scenarios = rows;
    evidence.simulate_pass = numel(rows) == numel(official.scenarios) && ...
        all([rows.simulation_pass]);
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
    (~isReference) || localFilePresence(modelPath) == referencePresence;
evidence.finished_at = localNow;
localWriteJson(evidencePath, evidence);
if ~isempty(fatal), rethrow(fatal); end
end

function localAssignGeometry(scenario, isReference)
crank = double(scenario.CrankLength_m);
coupler = double(scenario.CouplerLength_m);
assignin("base", "CrankLength_m", crank);
assignin("base", "CouplerLength_m", coupler);
if isReference
    assignin("base", "a", crank);
    assignin("base", "b", coupler);
    assignin("base", "c", 0.20);
    assignin("base", "d", 0.25);
    assignin("base", "h", 0.20);
end
end

function localClearPublicOutputs(isReference)
if isReference, return, end
for name = ["tip_trajectory", "drive_state"]
    evalin("base", "if exist('" + name + "','var'), clear " + name + "; end");
end
end

function signals = localCollectSignals(simOut, isReference)
signals = struct;
if isReference
    logs = localSimulationOutputValue(simOut, ...
        "logsout_sm_four_bar_optim");
    assert(isa(logs, "Simulink.SimulationData.Dataset"), ...
        "SimuVerity:F90:XMECH08:NativeLog", ...
        "The native xy_pos Dataset is missing.");
    item = logs.get("xy_pos");
    assert(~isempty(item), "SimuVerity:F90:XMECH08:NativeXY", ...
        "The native measured xy_pos signal is missing.");
    [time, xy] = localTimeseriesData(item.Values);
    signals.tip_time = time;
    signals.tip_xy = xy;
    signals.drive_time = time;
    signals.drive_state = [36 .* time, repmat(36, numel(time), 1)];
else
    tip = simuverity_public_output_compatibility( ...
        simOut, "tip_trajectory", 2, AllowBaseWorkspace=true);
    drive = simuverity_public_output_compatibility( ...
        simOut, "drive_state", 2, AllowBaseWorkspace=true);
    [signals.tip_time, signals.tip_xy] = localTimeseriesData(tip);
    [signals.drive_time, signals.drive_state] = ...
        localTimeseriesData(drive);
end
signals.tip_xy = localMatrix(signals.tip_xy);
signals.drive_state = localMatrix(signals.drive_state);
assert(size(signals.tip_xy, 2) == 2, ...
    "SimuVerity:F90:XMECH08:TipChannels", ...
    "tip_trajectory must contain exactly two channels.");
assert(size(signals.drive_state, 2) == 2, ...
    "SimuVerity:F90:XMECH08:DriveChannels", ...
    "drive_state must contain exactly two channels.");
end

function value = localSimulationOutputValue(simOut, name)
value = [];
try
    value = simOut.get(name);
catch
end
if isempty(value)
    try
        if evalin("base", "exist('" + name + "','var')") == 1
            value = evalin("base", name);
        end
    catch
    end
end
assert(~isempty(value), "SimuVerity:F90:XMECH08:RequiredOutput", ...
    "Required output %s is missing.", name);
end

function [time, data] = localTimeseriesData(value)
if isa(value, "Simulink.SimulationData.Signal")
    value = value.Values;
end
if isa(value, "timeseries")
    time = double(value.Time(:));
    data = squeeze(double(value.Data));
elseif istimetable(value)
    time = seconds(value.Properties.RowTimes - ...
        value.Properties.RowTimes(1));
    data = double(value.Variables);
elseif isstruct(value) && isfield(value, "time") && ...
        isfield(value, "signals")
    time = double(value.time(:));
    data = squeeze(double(value.signals.values));
else
    error("SimuVerity:F90:XMECH08:OutputType", ...
        "Required output is not a supported Timeseries representation.");
end
if isvector(data)
    data = data(:);
end
if size(data, 1) ~= numel(time) && size(data, 2) == numel(time)
    data = data.';
end
assert(size(data, 1) == numel(time), ...
    "SimuVerity:F90:XMECH08:OutputLength", ...
    "Output time and data lengths differ.");
end

function value = localMatrix(value)
value = squeeze(double(value));
if isvector(value), value = value(:); end
end

function [metrics, trajectory] = localMetrics(signals, scenario)
tipTime = double(signals.tip_time(:));
tip = double(signals.tip_xy);
driveTime = double(signals.drive_time(:));
drive = double(signals.drive_state);
[tipTime, uniqueTip] = unique(tipTime, "stable");
tip = tip(uniqueTip, :);
[driveTime, uniqueDrive] = unique(driveTime, "stable");
drive = drive(uniqueDrive, :);
phase = linspace(0, 1, 129)';
tipPhase = (tipTime - tipTime(1)) ./ max(tipTime(end) - tipTime(1), eps);
drivePhase = (driveTime - driveTime(1)) ./ ...
    max(driveTime(end) - driveTime(1), eps);
tipResampled = interp1(tipPhase, tip, phase, "linear", "extrap");
driveResampled = interp1(drivePhase, drive, phase, "linear", "extrap");
segments = diff(tipResampled, 1, 1);
segmentLength = sqrt(sum(segments.^2, 2));
speed = segmentLength ./ max(diff(phase) .* 10, eps);
allValues = [tip(:); drive(:)];
finiteFraction = nnz(isfinite(allValues)) / max(numel(allValues), 1);
pathLength = sum(segmentLength);
closure = norm(tipResampled(end, :) - tipResampled(1, :));
centred = tipResampled - mean(tipResampled, 1);
radiusRms = sqrt(mean(sum(centred.^2, 2)));
metrics = struct( ...
    "sample_count_tip", numel(tipTime), ...
    "sample_count_drive", numel(driveTime), ...
    "time_start_s", tipTime(1), ...
    "time_end_s", tipTime(end), ...
    "duration_s", tipTime(end) - tipTime(1), ...
    "finite_fraction", finiteFraction, ...
    "x_span_m", max(tipResampled(:, 1)) - min(tipResampled(:, 1)), ...
    "y_span_m", max(tipResampled(:, 2)) - min(tipResampled(:, 2)), ...
    "path_length_m", pathLength, ...
    "enclosed_area_m2", polyarea(tipResampled(:, 1), tipResampled(:, 2)), ...
    "closure_error_m", closure, ...
    "closure_error_fraction", closure / max(pathLength, eps), ...
    "radius_rms_m", radiusRms, ...
    "maximum_step_m", max(segmentLength), ...
    "median_step_m", median(segmentLength), ...
    "tip_speed_mean_m_s", mean(speed), ...
    "tip_speed_cv", std(speed) / max(abs(mean(speed)), eps), ...
    "drive_initial_angle_deg", driveResampled(1, 1), ...
    "drive_final_angle_deg", driveResampled(end, 1), ...
    "drive_angle_span_deg", ...
        max(driveResampled(:, 1)) - min(driveResampled(:, 1)), ...
    "drive_speed_mean_deg_s", mean(driveResampled(:, 2)), ...
    "drive_speed_cv", std(driveResampled(:, 2)) / ...
        max(abs(mean(driveResampled(:, 2))), eps), ...
    "requested_crank_length_m", double(scenario.CrankLength_m), ...
    "requested_coupler_length_m", double(scenario.CouplerLength_m));
trajectory = struct( ...
    "normalized_phase", phase, ...
    "tip_xy_m", tipResampled, ...
    "drive_state", driveResampled);
end

function valid = localOutputsValid(metrics)
valid = metrics.sample_count_tip >= 20 && ...
    metrics.sample_count_drive >= 20 && ...
    metrics.duration_s >= 9.9 && ...
    metrics.finite_fraction == 1 && ...
    metrics.x_span_m > 1e-3 && ...
    metrics.y_span_m > 1e-3 && ...
    metrics.path_length_m > 1e-2 && ...
    metrics.drive_angle_span_deg >= 350;
end

function audit = localStaticAudit(model, isReference)
blocks = find_system(model, "LookUnderMasks", "all", ...
    "FollowLinks", "on", "Type", "Block");
descriptors = strings(numel(blocks), 1);
for index = 1:numel(blocks)
    descriptors(index) = lower(localBlockDescriptor(blocks{index}));
end
audit = struct;
audit.block_count = numel(blocks);
audit.revolute_joint_count = nnz(contains(descriptors, "revolute joint"));
audit.rigid_solid_count = nnz(contains(descriptors, "solid"));
audit.world_frame_count = nnz(contains(descriptors, "world frame"));
audit.transform_sensor_count = nnz(contains(descriptors, "transform sensor"));
audit.simulink_ps_converter_count = ...
    nnz(contains(descriptors, "simulink-ps converter"));
audit.ps_simulink_converter_count = ...
    nnz(contains(descriptors, "ps-simulink converter"));
lineHandles = find_system(model, "FindAll", "on", "Type", "line");
connectionCount = 0;
for handle = reshape(lineHandles, 1, [])
    try
        if strcmpi(string(get_param(handle, "LineType")), "connection")
            connectionCount = connectionCount + 1;
        end
    catch
    end
end
audit.physical_connection_line_count = connectionCount;
audit.connected_four_bar_signature = ...
    audit.revolute_joint_count >= 4 && ...
    audit.rigid_solid_count >= 3 && ...
    audit.world_frame_count >= 1 && ...
    audit.physical_connection_line_count >= 8;
audit.physical_drive_signature = ...
    audit.simulink_ps_converter_count >= 1 && ...
    audit.revolute_joint_count >= 4;
audit.physical_tip_measurement_signature = ...
    audit.transform_sensor_count >= 1 && ...
    audit.ps_simulink_converter_count >= 1;
if ~isReference
    sinks = find_system(model, "LookUnderMasks", "all", ...
        "FollowLinks", "on", "BlockType", "ToWorkspace");
    names = strings(numel(sinks), 1);
    for index = 1:numel(sinks)
        names(index) = string(get_param(sinks{index}, "VariableName"));
    end
    audit.public_output_sink_count = ...
        nnz(ismember(["tip_trajectory", "drive_state"], names));
else
    audit.public_output_sink_count = 2;
end
end

function profile = localSourceProfile(model)
profile = struct;
profile.model_name = string(model);
profile.block_count = numel(find_system(model, ...
    "LookUnderMasks", "all", "FollowLinks", "on", "Type", "Block"));
profile.system_count = numel(find_system(model, ...
    "LookUnderMasks", "all", "FollowLinks", "on", ...
    "BlockType", "SubSystem"));
profile.solver = string(get_param(model, "Solver"));
profile.solver_type = string(get_param(model, "SolverType"));
profile.stop_time = string(get_param(model, "StopTime"));
profile.preload_callback = string(get_param(model, "PreLoadFcn"));
profile.postload_callback = string(get_param(model, "PostLoadFcn"));
profile.init_callback = string(get_param(model, "InitFcn"));
profile.causal_path = ...
    "angle command -> physical revolute input joint -> crank -> coupler " + ...
    "and rocker closed loop -> rigid tracer arm -> world-frame transform sensor";
profile.measured_output = ...
    "ground-frame x-y position of the tracer tip";
end

function value = localBlockDescriptor(block)
parts = strings(0, 1);
for parameter = ["ReferenceBlock", "SourceType", "MaskType", "BlockType"]
    try
        item = regexprep(string(get_param(block, parameter)), "\s+", " ");
        if strlength(item) > 0, parts(end + 1, 1) = item; end %#ok<AGROW>
    catch
    end
end
value = join(parts, " | ");
end

function row = localEmptyRow
row = struct( ...
    "id", "", ...
    "class", "", ...
    "requested_inputs", struct, ...
    "simulation_pass", false, ...
    "outputs_valid", false, ...
    "wall_seconds", NaN, ...
    "metrics", struct, ...
    "trajectory", struct, ...
    "signal_artifact", "", ...
    "signal_file_presence", "", ...
    "error", struct);
end

function relative = localRelativePath(pathValue, root)
relative = replace(string(pathValue), string(root) + filesep, "");
relative = replace(relative, "\", "/");
end

function localConfigureIsolation
cache = string(getenv("SIMULINK_CACHE_FOLDER"));
codegen = string(getenv("SIMULINK_CODEGEN_FOLDER"));
assert(strlength(cache) > 0 && strlength(codegen) > 0, ...
    "SimuVerity:F90:XMECH08:Isolation", ...
    "SIMULINK_CACHE_FOLDER and SIMULINK_CODEGEN_FOLDER are required.");
if ~isfolder(cache), mkdir(cache); end
if ~isfolder(codegen), mkdir(codegen); end
Simulink.fileGenControl("set", ...
    "CacheFolder", cache, ...
    "CodeGenFolder", codegen, ...
    "createDir", true);
set(groot, "defaultFigureVisible", "off");
end

function projectRoot = localInitializeReferenceProject(assetRoot, modelName)
projectRoot = fullfile(assetRoot, "Four-Bar-Optim");
projectFile = fullfile(projectRoot, "Four_Bar_Optim.prj");
sourceModel = fullfile(projectRoot, modelName + ".slx");
assert(isfile(projectFile) && isfile(sourceModel), ...
    "SimuVerity:F90:XMECH08:ReferenceProjectClosure", ...
    "The exact Four-Bar project closure is missing from the evaluator asset root.");
project = openProject(projectFile); %#ok<NASGU>
assert(bdIsLoaded(modelName), "SimuVerity:F90:XMECH08:ReferenceProjectStartup", ...
    "The official Four-Bar project StartUp did not load its source model.");
assert(evalin("base", "exist('pin_rad','var') == 1") && ...
    evalin("base", "exist('link_t','var') == 1") && ...
    evalin("base", "exist('a','var') == 1") && ...
    evalin("base", "exist('b','var') == 1"), ...
    "SimuVerity:F90:XMECH08:ReferenceProjectStartup", ...
    "The official Four-Bar StartUp did not initialize its geometry workspace.");
close_system(modelName, 0);
assert(~bdIsLoaded(modelName), "SimuVerity:F90:XMECH08:ReferenceProjectAlias", ...
    "The project source alias remained loaded before the evaluator alias load.");
end

function localCleanup(model, oldDir, oldPath, isReference, referenceProjectRoot)
try
    if bdIsLoaded(model), close_system(model, 0); end
catch
end
try, cd(oldDir); catch, end
path(oldPath);
end

function value = localFilePresence(pathValue)
assert(isfile(pathValue), "SimuVerity:FileMissing", "Required file is missing: %s", pathValue);
value = "present";
end

function value = localNow
value = string(datetime("now", "TimeZone", "local", ...
    "Format", "yyyy-MM-dd'T'HH:mm:ssXXX"));
end

function value = localError(ME)
value = struct( ...
    "identifier", string(ME.identifier), ...
    "message", string(ME.message));
end

function localWriteJson(pathValue, value)
fid = fopen(pathValue, "w", "n", "UTF-8");
assert(fid >= 0, "SimuVerity:F90:XMECH08:JsonOpen", ...
    "Cannot write evidence output: %s", pathValue);
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fwrite(fid, jsonencode(value, PrettyPrint=true), "char");
end

function value = localTernary(condition, yes, no)
if condition, value = yes; else, value = no; end
end

function root = localProjectRoot
here = fileparts(mfilename("fullpath"));
root = fileparts(fileparts(fileparts(fileparts(here))));
end
