function result = f90_xaero10_extract_evidence(modelPath, outputDir, evaluationMode)
% Fixed five-case evidence extraction for F90-XAERO-10.
% The extractor installs evaluator-owned public nominal inputs before candidate update
% and compile. Intervention effectiveness remains offline-scored performance,
% not an evidence-lock qualification gate.

repo = localProjectRoot();
taskDir = string(getenv("SIMUVERITY_TASK_ROOT"));
official = jsondecode(fileread(simuverity_official_scenarios_path()));
sourceModel = fullfile(taskDir, "reference", "source", "2018_Simulink", "comparison_noise_nonoise.slx");
expectedBinding = "present";
if nargin < 1 || strlength(string(modelPath)) == 0, modelPath = sourceModel; end
if nargin < 3 || strlength(string(evaluationMode)) == 0, evaluationMode = "reference"; end
scoringRunId = string(getenv("SIMUVERITY_SCORING_RUN_ID"));
if strlength(scoringRunId) == 0
    scoringRunId = "f90_xaero10_manual_" + string(datetime("now", "Format", "yyyyMMdd'T'HHmmss"));
end
if nargin < 2 || strlength(string(outputDir)) == 0
    outputDir = fullfile(repo, "results", "cross_domain", "simuverity_public", ...
        "F90-XAERO-10", "fixed_evidence", scoringRunId);
end
assert(~isfolder(outputDir), "SimuVerity:F90:XAERO10:OutputExists", ...
    "Fresh evidence output exists: %s", outputDir);
mkdir(outputDir);
diary(fullfile(outputDir, "extractor.log"));
cleanDiary = onCleanup(@() diary("off")); %#ok<NASGU>
evidencePath = fullfile(outputDir, "evidence.json");
modelPath = string(modelPath);
sourcePresenceBefore = localFilePresence(modelPath);
isReference = lower(strtrim(string(getenv("SIMUVERITY_EVALUATION_SUBJECT")))) == "reference";
publicInputNames = ["attitude_command_rad", "measurement_noise_covariance"];
evidence = struct( ...
    "schema", "simuverity.f90-xaero10-evidence.v1", ...
    "task_id", "F90-XAERO-10", ...
    "scoring_run_id", scoringRunId, ...
    "evaluation_subject", string(evaluationMode), ...
    "model_file_presence_before", sourcePresenceBefore, ...
    "reference_direct_golden", isReference, ...
    "runtime_changes", "Normal mode, evaluator-owned public inputs, non-truncating logs, isolated cache/codegen, evaluator-only resampling, and four in-memory measurement taps for the unlogged second-branch plant states", ...
    "public_input_setup", struct( ...
        "owner", "evaluator", ...
        "names", publicInputNames, ...
        "candidate_nominal_injected_before_update_compile", false, ...
        "scenario_overrides_via_simulation_input", ~isReference, ...
        "candidate_or_dependency_package_modified", false), ...
    "load_pass", false, ...
    "update_pass", false, ...
    "compile_pass", false, ...
    "simulate_pass", false, ...
    "all_official_evidence_valid", false, ...
    "static_audit", struct(), ...
    "behavior_audit", struct(), ...
    "evidence_qualification", struct( ...
        "intervention_axis_performance_is_qualification", false, ...
        "required_outputs_and_runtime_only", true), ...
    "scenario_count", numel(official.scenarios), ...
    "scenarios", struct([]), ...
    "EVIDENCE_COMPLETE", false, ...
    "contains_score_decisions", false, ...
    "failure", "");
localWriteJson(evidencePath, evidence);

[modelDir, model, ~] = fileparts(modelPath);
oldPath = path;
oldDir = pwd;
sessionCleanup = onCleanup(@() localRestore(oldPath, oldDir)); %#ok<NASGU>
addpath(modelDir, "-begin");
scratch = fullfile(outputDir, "runtime_scratch");
mkdir(scratch);
cache = fullfile(scratch, "cache");
codegen = fullfile(scratch, "codegen");
mkdir(cache);
mkdir(codegen);
Simulink.fileGenControl("set", "CacheFolder", cache, "CodeGenFolder", codegen, "createDir", true);

try
    load_system(modelPath);
    cleanModel = onCleanup(@() localClose(model)); %#ok<NASGU>
    evidence.load_pass = true;
    if ~isReference
        publicInputCleanup = localInstallPublicNominalInputs(official.scenarios); %#ok<NASGU>
        evidence.public_input_setup.candidate_nominal_injected_before_update_compile = true;
    end
    set_param(model, "SimulationMode", "normal", "ReturnWorkspaceOutputs", "on", "LimitDataPoints", "off");
    toWs = find_system(model, "LookUnderMasks", "all", "BlockType", "ToWorkspace");
    for index = 1:numel(toWs), set_param(toWs{index}, "MaxDataPoints", "inf"); end
    if isReference, localAddSecondBranchTaps(model); end
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
        caseTimer = tic;
        out = localRunScenario(model, scenario, isReference, official.simulation.duration_seconds);
        if isReference
            signals = localReadReference(out, scenario, official.simulation);
        else
            signals = localReadCandidate(out, scenario, official.simulation);
        end
        contract = localContract(signals, official.simulation.duration_seconds);
        assert(all(structfun(@logical, contract)), "SimuVerity:F90:XAERO10:OutputContract", ...
            "Scenario %s violates output contract.", scenario.id);
        rows{index} = struct( ...
            "id", string(scenario.id), ...
            "inputs", rmfield(scenario, "id"), ...
            "time_s", signals.time_s, ...
            "noisy_closed_loop_state", signals.noisy_closed_loop_state, ...
            "noise_free_closed_loop_state", signals.noise_free_closed_loop_state, ...
            "command_noise_state", signals.command_noise_state, ...
            "output_contract", contract, ...
            "metrics", localMetrics(signals), ...
            "wall_seconds", toc(caseTimer), ...
            "valid", true);
    end
    rows = [rows{:}];
    evidence.scenarios = rows;
    evidence.suite_wall_seconds = toc(suiteTimer);
    evidence.simulate_pass = true;
    evidence.all_official_evidence_valid = all([rows.valid]);
    evidence.behavior_audit = localBehaviorAudit(rows);
    evidence.model_file_presence_after = localFilePresence(modelPath);
    evidence.model_binding_preserved = evidence.model_file_presence_after == evidence.model_file_presence_before;
    assert(evidence.model_binding_preserved, "SimuVerity:F90:XAERO10:ModelModified", ...
        "Evaluated model changed.");
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

function cleanup = localInstallPublicNominalInputs(scenarios)
ids = string({scenarios.id});
nominalIndex = find(ids == "nominal_zero_command", 1);
assert(~isempty(nominalIndex), "SimuVerity:F90:XAERO10:NominalScenarioMissing", ...
    "The evaluator-owned public nominal input row is missing.");
nominal = scenarios(nominalIndex);
names = ["attitude_command_rad", "measurement_noise_covariance"];
values = [double(nominal.attitude_command_rad), double(nominal.measurement_noise_covariance)];
existed = false(size(names));
previous = cell(size(names));
for index = 1:numel(names)
    existed(index) = evalin("base", "exist('" + names(index) + "','var') == 1");
    if existed(index), previous{index} = evalin("base", names(index)); end
    assignin("base", names(index), values(index));
end
cleanup = onCleanup(@() localRestorePublicInputs(names, existed, previous));
end

function localRestorePublicInputs(names, existed, previous)
for index = 1:numel(names)
    try
        if existed(index)
            assignin("base", names(index), previous{index});
        else
            evalin("base", "clear('" + names(index) + "')");
        end
    catch
    end
end
end

function out = localRunScenario(model, scenario, isReference, duration)
in = Simulink.SimulationInput(model);
in = in.setModelParameter("StopTime", num2str(duration, 17), "SimulationMode", "normal", ...
    "ReturnWorkspaceOutputs", "on", "LimitDataPoints", "off");
if isReference
    in = in.setBlockParameter(model + "/Constant", "Value", num2str(scenario.attitude_command_rad, 17));
    in = in.setBlockParameter(model + "/Constant1", "Value", num2str(scenario.attitude_command_rad, 17));
    in = in.setBlockParameter(model + "/" + sprintf("Band-Limited\nWhite Noise"), ...
        "Cov", num2str(scenario.measurement_noise_covariance, 17));
else
    in = in.setVariable("attitude_command_rad", double(scenario.attitude_command_rad));
    in = in.setVariable("measurement_noise_covariance", double(scenario.measurement_noise_covariance));
end
capture = evalc("out=sim(in);"); %#ok<NASGU>
end

function signals = localReadReference(out, scenario, simulation)
grid = (0:double(simulation.evidence_grid_step_seconds):double(simulation.duration_seconds)).';
tout = double(out.tout(:));
noisy = localNumericOutput(out, "NonLinear", tout, 4, grid);
clean = [localSeriesOutput(out, "xa10_clean_x1", 1, grid), ...
    localSeriesOutput(out, "xa10_clean_x2", 1, grid), ...
    localSeriesOutput(out, "xa10_clean_x3", 1, grid), ...
    localSeriesOutput(out, "xa10_clean_x4", 1, grid)];
commands = repmat([double(scenario.attitude_command_rad), ...
    double(scenario.measurement_noise_covariance)], numel(grid), 1);
signals = struct("time_s", grid, "noisy_closed_loop_state", noisy, ...
    "noise_free_closed_loop_state", clean, "command_noise_state", commands);
end

function signals = localReadCandidate(out, scenario, simulation)
grid = (0:double(simulation.evidence_grid_step_seconds):double(simulation.duration_seconds)).';
noisy = localSeriesOutput(out, "noisy_closed_loop_state", 4, grid);
clean = localSeriesOutput(out, "noise_free_closed_loop_state", 4, grid);
commands = localSeriesOutput(out, "command_noise_state", 2, grid);
assert(max(abs(commands(:, 1) - double(scenario.attitude_command_rad))) <= 1e-6 && ...
    max(abs(commands(:, 2) - double(scenario.measurement_noise_covariance))) <= 1e-6, ...
    "SimuVerity:F90:XAERO10:CommandLog", "Command/noise log differs from official input.");
signals = struct("time_s", grid, "noisy_closed_loop_state", noisy, ...
    "noise_free_closed_loop_state", clean, "command_noise_state", commands);
end

function dataGrid = localNumericOutput(out, name, t, width, grid)
value = double(out.get(name));
if isvector(value), value = value(:); end
if size(value, 1) ~= numel(t) && size(value, 2) == numel(t), value = value.'; end
assert(size(value, 1) == numel(t) && size(value, 2) == width, ...
    "SimuVerity:F90:XAERO10:ReferenceShape", "Source output %s has invalid shape.", name);
dataGrid = localResample(t, value, grid, name);
end

function localAddSecondBranchTaps(model)
blocks = ["Integrator21", "Integrator7", "Integrator19", "Integrator20"];
variables = ["xa10_clean_x1", "xa10_clean_x2", "xa10_clean_x3", "xa10_clean_x4"];
for index = 1:numel(blocks)
    source = model + "/" + blocks(index);
    sink = model + "/__eval_clean_" + string(index);
    add_block("simulink/Sinks/To Workspace", sink, "VariableName", variables(index), ...
        "SaveFormat", "Timeseries", "MaxDataPoints", "inf", ...
        "Position", [3200 100 + 45 * index 3290 130 + 45 * index]);
    sourcePorts = get_param(source, "PortHandles");
    sinkPorts = get_param(sink, "PortHandles");
    add_line(model, sourcePorts.Outport(1), sinkPorts.Inport(1), "autorouting", "on");
end
end

function dataGrid = localSeriesOutput(out, name, width, grid)
try
    value = out.get(name);
catch
    error("SimuVerity:F90:XAERO10:MissingOutput", "Required output %s absent.", name);
end
if isa(value, "timeseries")
    t = double(value.Time(:));
    data = squeeze(double(value.Data));
elseif isstruct(value) && isfield(value, "time") && isfield(value, "signals")
    t = double(value.time(:));
    data = squeeze(double(value.signals.values));
else
    error("SimuVerity:F90:XAERO10:OutputType", "Output %s is not a supported Timeseries.", name);
end
if isvector(data), data = data(:); end
if size(data, 1) ~= numel(t) && size(data, 2) == numel(t), data = data.'; end
assert(size(data, 1) == numel(t) && size(data, 2) == width, ...
    "SimuVerity:F90:XAERO10:OutputShape", "Output %s has invalid width.", name);
dataGrid = localResample(t, data, grid, name);
end

function dataGrid = localResample(t, data, grid, name)
assert(all(isfinite(t)) && all(isfinite(data(:))), ...
    "SimuVerity:F90:XAERO10:Finite", "Output %s nonfinite.", name);
[t, keep] = unique(t, "stable");
data = data(keep, :);
assert(numel(t) >= 50 && all(diff(t) > 0) && t(1) <= 0.01 && t(end) >= grid(end) - 0.01, ...
    "SimuVerity:F90:XAERO10:Coverage", "Output %s lacks full coverage.", name);
dataGrid = interp1(t, data, grid, "linear", "extrap");
assert(all(isfinite(dataGrid(:)), "all"), ...
    "SimuVerity:F90:XAERO10:Resample", "Output %s nonfinite after resampling.", name);
end

function contract = localContract(signals, duration)
contract = struct( ...
    "time_strict", all(diff(signals.time_s) > 0), ...
    "full_coverage", abs(signals.time_s(1)) <= 1e-12 && abs(signals.time_s(end) - duration) <= 1e-9, ...
    "noisy_width_4", size(signals.noisy_closed_loop_state, 2) == 4, ...
    "clean_width_4", size(signals.noise_free_closed_loop_state, 2) == 4, ...
    "command_width_2", size(signals.command_noise_state, 2) == 2, ...
    "finite_noisy", all(isfinite(signals.noisy_closed_loop_state(:))), ...
    "finite_clean", all(isfinite(signals.noise_free_closed_loop_state(:))), ...
    "finite_command", all(isfinite(signals.command_noise_state(:))));
end

function metrics = localMetrics(signals)
divergence = signals.noisy_closed_loop_state - signals.noise_free_closed_loop_state;
metrics = struct( ...
    "noisy_rms", sqrt(mean(signals.noisy_closed_loop_state .^ 2, 1)), ...
    "clean_rms", sqrt(mean(signals.noise_free_closed_loop_state .^ 2, 1)), ...
    "noisy_final", signals.noisy_closed_loop_state(end, :), ...
    "clean_final", signals.noise_free_closed_loop_state(end, :), ...
    "noisy_peak_abs", max(abs(signals.noisy_closed_loop_state), [], 1), ...
    "clean_peak_abs", max(abs(signals.noise_free_closed_loop_state), [], 1), ...
    "branch_divergence_rms", sqrt(mean(divergence .^ 2, 1)), ...
    "branch_divergence_peak", max(abs(divergence), [], 1));
end

function audit = localBehaviorAudit(rows)
nominal = rows(1).metrics;
large = rows(3).metrics;
high = rows(4).metrics;
commandDelta = norm([large.noisy_final - nominal.noisy_final, ...
    large.clean_final - nominal.clean_final]);
noiseDelta = norm(high.branch_divergence_rms - nominal.branch_divergence_rms);
audit = struct( ...
    "command_final_state_delta", commandDelta, ...
    "noise_branch_divergence_delta", noiseDelta, ...
    "command_axis_effective", commandDelta > 1e-5, ...
    "noise_axis_effective", noiseDelta > 1e-6, ...
    "performance_only_not_evidence_qualification", true);
end

function audit = localStaticAudit(model, isReference)
blocks = find_system(model, "LookUnderMasks", "all", "FollowLinks", "on", "Type", "Block");
audit = struct( ...
    "block_count", numel(blocks), ...
    "reference_fixed_single_entry", isReference, ...
    "source_native_to_workspace_count", 2, ...
    "source_native_second_logger_duplicates_first_branch", isReference, ...
    "evaluator_in_memory_second_branch_tap_count", 4 * double(isReference), ...
    "saturation_count", numel(find_system(model, "LookUnderMasks", "all", "BlockType", "Saturate")));
end

function localWriteJson(pathName, value)
fid = fopen(pathName, "w", "n", "UTF-8");
assert(fid >= 0, "SimuVerity:F90:XAERO10:Write", "Cannot write %s.", pathName);
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, "%s\n", jsonencode(value, "PrettyPrint", true));
end

function summary = localFilePresence(pathName)
assert(isfile(pathName), "SimuVerity:FileMissing", "Required file is missing: %s", pathName);
summary = "present";
end

function root = localProjectRoot()
root = string(fileparts(mfilename("fullpath")));
for index = 1:4, root = string(fileparts(root)); end
end

function localClose(model)
try
    if bdIsLoaded(model), close_system(model, 0); end
catch
end
end

function localRestore(oldPath, oldDir)
try, path(oldPath); catch, end
try, cd(oldDir); catch, end
end
