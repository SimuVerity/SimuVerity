function result = f90_xmed10_extract_reference_evidence(modelPath, outputDir, evaluationMode)
% Extract complete fixed evidence for F90-XMED-10. Scoring is offline only.

repo = localProjectRoot();
taskDir = string(getenv("SIMUVERITY_TASK_ROOT"));
official = jsondecode(fileread(simuverity_official_scenarios_path()));
expectedSourceBinding = "present";
assert(nargin >= 1 && strlength(string(modelPath)) > 0, ...
    "SimuVerity:F90:XMED10:ModelRequired", "Public extraction requires an explicit model path.");
sourceModel = string(modelPath);
if nargin < 3 || strlength(string(evaluationMode)) == 0
    evaluationMode = "reference";
end
generationRunId = string(getenv("SIMUVERITY_GENERATION_RUN_ID"));
if strlength(generationRunId) == 0
    generationRunId = "f90_xmed10_manual_" + string(datetime("now", ...
        "Format", "yyyyMMdd'T'HHmmss"));
end
if nargin < 2 || strlength(string(outputDir)) == 0
    outputDir = fullfile(tempdir, "SimuVerity", "F90-XMED-10", generationRunId);
end
if ~isfolder(outputDir), mkdir(outputDir); end
evidencePath = fullfile(outputDir, "evidence.json");
isReference = lower(strtrim(string(getenv("SIMUVERITY_EVALUATION_SUBJECT")))) == "reference";

evidence = struct( ...
    "schema", "simuverity.f90-xmed10-evidence.v1", ...
    "task_id", "F90-XMED-10", ...
    "generation_run_id", generationRunId, ...
    "evaluation_subject", string(evaluationMode), ...
    "model_path", string(modelPath), ...
    "source_file_presence_before", localFilePresence(modelPath), ...
    "reference_direct_golden", isReference, ...
    "reference_substantive_modifications", 0, ...
    "runtime_changes", ...
        "Normal mode, project pyenv binding, public parameter exposure, semantic output mapping and non-truncating logs only", ...
    "load_pass", false, ...
    "update_pass", false, ...
    "compile_pass", false, ...
    "nominal_smoke_pass", false, ...
    "static_audit", struct(), ...
    "behavior_audit", struct(), ...
    "scenarios", struct([]), ...
    "EVIDENCE_COMPLETE", false, ...
    "contains_score_decisions", false, ...
    "errors", {{}}, ...
    "started_at", localNow());
localWriteJson(evidencePath, evidence);

[modelDir, model, ~] = fileparts(modelPath);
sharedDir = fullfile(string(getenv("SIMUVERITY_TASK_VENDOR_ROOT")), ...
    "scripts", "unified", "public_output");
sourceEntryDir = fileparts(sourceModel);
addpath(sharedDir, "-begin");
addpath(modelDir, "-begin");
if isReference && ~strcmp(sourceEntryDir,modelDir)
    addpath(sourceEntryDir, "-begin");
end
pathCleanup = onCleanup(@() localRemovePaths(sharedDir, modelDir, sourceEntryDir)); %#ok<NASGU>
localConfigureRuntime(outputDir);
pythonLoaded = false;

try
    if isReference
        assert(strcmpi(localFilePresence(modelPath), expectedSourceBinding), ...
            "SimuVerity:F90:XMED10:ReferenceIdentity", "Pinned reference model file presence differs.");
        runtimeRoot = string(getenv("SIMUVERITY_RUNTIME_SUBMISSION_BUNDLE"));
        pythonSource = fullfile(runtimeRoot, "source", "src");
        assert(isfolder(pythonSource), "SimuVerity:F90:XMED10:PythonSource", ...
            "The bundled Python source package is unavailable.");
        pythonExe = string(getenv("SIMUVERITY_F90_XMED10_PYTHON_EXE"));
        assert(strlength(pythonExe) > 0 && isfile(pythonExe), ...
            "SimuVerity:F90:XMED10:PythonDependency", ...
            "SIMUVERITY_F90_XMED10_PYTHON_EXE must name a public runtime with the required dependencies.");
        oldPythonPath = string(getenv("PYTHONPATH"));
        pythonPathCleanup = onCleanup(@() setenv("PYTHONPATH", oldPythonPath)); %#ok<NASGU>
        if strlength(oldPythonPath) > 0
            setenv("PYTHONPATH", pythonSource + pathsep + oldPythonPath);
        else
            setenv("PYTHONPATH", pythonSource);
        end
        pe = pyenv;
        if pe.Status == "Loaded", terminate(pe); end
        pyenv("Version", pythonExe, "ExecutionMode", "OutOfProcess");
        py.importlib.import_module("python_anesthesia_simulator.simulator");
        pythonLoaded = true;
        evidence.python = struct("executable", pythonExe, ...
            "version", string(pyenv().Version), ...
            "bundled_source", pythonSource, "import_pass", true);
    else
        evidence.python = struct("required_for_candidate", false);
    end

    load_system(modelPath);
    evidence.load_pass = true;
    set_param(model, "SimulationMode", "normal", ...
        "ReturnWorkspaceOutputs", "on", "LimitDataPoints", "off");
    toWs = find_system(model, "LookUnderMasks", "all", ...
        "BlockType", "ToWorkspace");
    for index = 1:numel(toWs)
        set_param(toWs{index}, "MaxDataPoints", "inf");
    end
    localAssignInputs(official.scenarios(1), isReference);
    if isReference
        set_param(model + "/Constant2", "Value", ...
            num2str(official.scenarios(1).bis_target, 17));
    end
    set_param(model, "SimulationCommand", "update");
    evidence.update_pass = true;
    set_param(model, "SimulationCommand", "start");
    set_param(model, "SimulationCommand", "stop");
    evidence.compile_pass = true;
    clear callPython
    evidence.static_audit = localStaticAudit(model, isReference);
    localWriteJson(evidencePath, evidence);

    smokeScenario = official.scenarios(1);
    smokeOut = localRunScenario(model, smokeScenario, isReference, 30);
    smokeSignals = localReadSignals(smokeOut, isReference);
    smokeContract = localOutputContract(smokeSignals, 30);
    evidence.nominal_smoke_pass = all(structfun(@logical, smokeContract));
    evidence.nominal_smoke_contract = smokeContract;
    localWriteJson(evidencePath, evidence);
    assert(evidence.nominal_smoke_pass, "SimuVerity:F90:XMED10:NominalSmoke", ...
        "Nominal smoke output contract failed.");

    scenarioDir = fullfile(outputDir, "scenarios");
    if ~isfolder(scenarioDir), mkdir(scenarioDir); end
    rows = repmat(localEmptyScenario(), numel(official.scenarios), 1);
    for index = 1:numel(official.scenarios)
        scenario = official.scenarios(index);
        row = localEmptyScenario();
        row.id = string(scenario.id);
        row.inputs = rmfield(scenario, "id");
        started = tic;
        try
            out = localRunScenario(model, scenario, isReference, ...
                double(official.simulation.duration_seconds));
            signals = localReadSignals(out, isReference);
            row.output_contract = localOutputContract(signals, ...
                double(official.simulation.duration_seconds));
            row.metrics = localMetrics(signals, scenario, official.simulation);
            signalPath = fullfile(scenarioDir, "signals_" + string(scenario.id) + ".mat");
            save(signalPath, "signals", "-v7");
            row.complete_signal_artifact = localRelativePath(repo, signalPath);
            row.complete_signal_file_presence = localFilePresence(signalPath);
            row.simulation_pass = true;
            row.valid = all(structfun(@logical, row.output_contract));
            if ~row.valid
                row.error = localIssue("output_contract", row.id, ...
                    "Required complete-run evidence is invalid.");
            end
        catch exception
            row.error = localIssue("scenario", row.id, ...
                string(exception.identifier) + ": " + string(exception.message));
        end
        row.wall_seconds = toc(started);
        rows(index) = row;
        evidence.scenarios = rows(1:index);
        localWriteJson(fullfile(scenarioDir, "scenario_" + ...
            string(scenario.id) + ".json"), row);
        localWriteJson(evidencePath, evidence);
    end
    evidence.scenarios = rows;
    evidence.behavior_audit = localBehaviorAudit(rows);
    evidence.source_file_presence_after = localFilePresence(modelPath);
    evidence.reference_binding_preserved = ~isReference || ...
        strcmpi(evidence.source_file_presence_after, expectedSourceBinding);
    evidence.EVIDENCE_COMPLETE = evidence.load_pass && ...
        evidence.update_pass && evidence.compile_pass && ...
        evidence.nominal_smoke_pass && all([rows.valid]) && ...
        evidence.reference_binding_preserved && ...
        evidence.static_audit.core_path_qualified && ...
        evidence.behavior_audit.core_behavior_qualified;
    if evidence.EVIDENCE_COMPLETE, evidence.evidence_complete_at = localNow(); end
catch exception
    evidence.errors{end+1} = localIssue("session", "fatal", ...
        string(exception.identifier) + ": " + string(exception.message));
end

try
    if bdIsLoaded(model), close_system(model, 0); end
catch exception
    evidence.errors{end+1} = localIssue("close", "model", exception.message);
end
if pythonLoaded
    try, clear callPython; terminate(pyenv); catch, end
end
evidence.model_closed_without_save = ~bdIsLoaded(model);
evidence.finished_at = localNow();
evidence.source_file_presence_after = localFilePresence(modelPath);
if isReference
    evidence.reference_binding_preserved = strcmpi( ...
        evidence.source_file_presence_after, expectedSourceBinding);
    if ~evidence.reference_binding_preserved, evidence.EVIDENCE_COMPLETE = false; end
end
evidence.runtime = struct("matlab_release", string(version("-release")), ...
    "normal_mode", true, "generation_run_id", generationRunId, ...
    "matlab_prefdir", string(prefdir), "temp", string(getenv("TEMP")), ...
    "cache", string(getenv("SIMULINK_CACHE_FOLDER")), ...
    "codegen", string(getenv("SIMULINK_CODEGEN_FOLDER")));
localWriteJson(evidencePath, evidence);
result = evidence;
validCount = 0;
if ~isempty(evidence.scenarios), validCount = sum([evidence.scenarios.valid]); end
fprintf("F90_XMED10_EVIDENCE load=%d update=%d compile=%d smoke=%d valid=%d/%d complete=%d path=%s\n", ...
    evidence.load_pass, evidence.update_pass, evidence.compile_pass, ...
    evidence.nominal_smoke_pass, validCount, numel(evidence.scenarios), ...
    evidence.EVIDENCE_COMPLETE, evidencePath);
end

function out = localRunScenario(model, scenario, isReference, duration)
if isReference, clear callPython; end
localAssignInputs(scenario, isReference);
in = Simulink.SimulationInput(model);
in = in.setModelParameter("StopTime", num2str(duration, 17), ...
    "SimulationMode", "normal", "ReturnWorkspaceOutputs", "on");
names = fieldnames(rmfield(scenario, "id"));
for index = 1:numel(names)
    in = in.setVariable(names{index}, scenario.(names{index}));
end
in = in.setVariable("simulation_time_s", duration);
if isReference
    in = in.setVariable("simulation_time", duration);
    in = in.setVariable("age", scenario.patient_age_years);
    in = in.setVariable("height", scenario.patient_height_cm);
    in = in.setVariable("weight", scenario.patient_weight_kg);
    in = in.setVariable("sex", scenario.patient_sex_binary);
    in = in.setVariable("sampling_time", 1);
    controlNames = {"Kp", "Ti", "Td", "Ts", "N", "ratio", ...
        "uref_p", "uref_r", "sat_pos_p", "sat_neg_p", ...
        "sat_pos_r", "sat_neg_r"};
    controlValues = {0.0286, 206.98, 29.83, 5, 5, 2, 0, 0, 6.67, 0, 16.67, 0};
    for index = 1:numel(controlNames)
        in = in.setVariable(controlNames{index}, controlValues{index});
    end
    in = in.setBlockParameter(model + "/Constant2", "Value", ...
        num2str(scenario.bis_target, 17));
end
out = sim(in);
end

function localAssignInputs(scenario, isReference)
names = fieldnames(rmfield(scenario, "id"));
for index = 1:numel(names)
    assignin("base", names{index}, scenario.(names{index}));
end
assignin("base", "simulation_time_s", 900);
if isReference
    assignin("base", "simulation_time", 900);
    assignin("base", "age", scenario.patient_age_years);
    assignin("base", "height", scenario.patient_height_cm);
    assignin("base", "weight", scenario.patient_weight_kg);
    assignin("base", "sex", scenario.patient_sex_binary);
    assignin("base", "sampling_time", 1);
    values = struct("Kp",0.0286,"Ti",206.98,"Td",29.83,"Ts",5,"N",5, ...
        "ratio",2,"uref_p",0,"uref_r",0,"sat_pos_p",6.67, ...
        "sat_neg_p",0,"sat_pos_r",16.67,"sat_neg_r",0);
    fields = fieldnames(values);
    for index = 1:numel(fields)
        assignin("base", fields{index}, values.(fields{index}));
    end
end
end

function signals = localReadSignals(out, isReference)
public = ["bis_response", "loss_of_consciousness_probability", ...
    "cardiac_output_L_min", "mean_arterial_pressure_mmHg", ...
    "tolerance_of_laryngoscopy_probability", ...
    "propofol_infusion_mg_s", "remifentanil_infusion_ug_s"];
if isReference
    upstream = ["bis", "co", "map", "tol", "nmb", "u_prop", "u_remi"];
    signals = struct;
    for index = 1:numel(public)
        value = out.(upstream(index));
        signals.(public(index)) = localSeries(value);
    end
else
    signals = struct;
    for index = 1:numel(public)
        value = simuverity_public_output_compatibility(out, public(index), 1, ...
            AllowBaseWorkspace=true);
        signals.(public(index)) = localSeries(value);
    end
end
end

function series = localSeries(value)
if isa(value, "timeseries")
    time = double(value.Time(:)); data = squeeze(double(value.Data));
elseif isstruct(value) && isfield(value, "time") && isfield(value, "signals")
    time = double(value.time(:)); data = squeeze(double(value.signals.values));
else
    error("SimuVerity:F90:XMED10:SeriesType", ...
        "Unsupported evidence type %s.", class(value));
end
data = double(data(:));
assert(numel(time) == numel(data), "SimuVerity:F90:XMED10:SeriesLength");
series = struct("time", time, "data", data);
end

function contract = localOutputContract(signals, duration)
names = fieldnames(signals);
contract = struct;
for index = 1:numel(names)
    s = signals.(names{index});
    contract.(names{index}) = numel(s.time) >= 10 && ...
        numel(s.time) == numel(s.data) && all(isfinite(s.time)) && ...
        all(isfinite(s.data)) && all(diff(s.time) > 0) && ...
        s.time(1) <= 0.1 && s.time(end) >= duration - 0.1;
end
end

function metrics = localMetrics(signals, scenario, simulation)
bis = signals.bis_response;
tailStart = double(simulation.duration_seconds) - ...
    double(simulation.tail_window_seconds);
tail = bis.time >= tailStart;
evalMask = bis.time >= double(simulation.induction_evaluation_start_seconds);
errorSignal = abs(bis.data - double(scenario.bis_target));
metrics = struct;
metrics.bis_target = double(scenario.bis_target);
metrics.bis_tail_mean = mean(bis.data(tail));
metrics.bis_tail_std = std(bis.data(tail));
metrics.bis_tail_absolute_error = abs(metrics.bis_tail_mean - metrics.bis_target);
metrics.bis_tail_max_absolute_error = max(errorSignal(tail));
metrics.bis_integral_absolute_error = trapz(bis.time(evalMask), errorSignal(evalMask));
metrics.bis_settling_time_s = localSettlingTime(bis.time, errorSignal, ...
    double(simulation.settling_band_bis), ...
    double(simulation.induction_evaluation_start_seconds));
metrics.bis_induction_to_target_plus5_s = localSustainedEntry( ...
    bis.time, bis.data <= metrics.bis_target + 5, 30, ...
    double(simulation.induction_evaluation_start_seconds));

metrics.loc_tail_mean = localTail(signals.loss_of_consciousness_probability, tailStart);
metrics.cardiac_output_tail_mean_L_min = localTail(signals.cardiac_output_L_min, tailStart);
metrics.map_tail_mean_mmHg = localTail(signals.mean_arterial_pressure_mmHg, tailStart);
metrics.tol_tail_mean = localTail(signals.tolerance_of_laryngoscopy_probability, tailStart);
metrics.propofol_peak_mg_s = max(signals.propofol_infusion_mg_s.data);
metrics.propofol_min_mg_s = min(signals.propofol_infusion_mg_s.data);
metrics.propofol_tail_mean_mg_s = localTail(signals.propofol_infusion_mg_s, tailStart);
metrics.propofol_range_mg_s = max(signals.propofol_infusion_mg_s.data) - ...
    min(signals.propofol_infusion_mg_s.data);
metrics.remifentanil_peak_ug_s = max(signals.remifentanil_infusion_ug_s.data);
metrics.remifentanil_min_ug_s = min(signals.remifentanil_infusion_ug_s.data);
metrics.remifentanil_tail_mean_ug_s = localTail(signals.remifentanil_infusion_ug_s, tailStart);
metrics.remifentanil_range_ug_s = max(signals.remifentanil_infusion_ug_s.data) - ...
    min(signals.remifentanil_infusion_ug_s.data);
metrics.physiology_summary = localSummary([ ...
    signals.loss_of_consciousness_probability.data; ...
    signals.cardiac_output_L_min.data; ...
    signals.mean_arterial_pressure_mmHg.data; ...
    signals.tolerance_of_laryngoscopy_probability.data]);
metrics.command_summary = localSummary([ ...
    signals.propofol_infusion_mg_s.data; ...
    signals.remifentanil_infusion_ug_s.data]);
metrics.physiology_plausible = metrics.loc_tail_mean >= 0 && ...
    metrics.loc_tail_mean <= 1.01 && ...
    metrics.cardiac_output_tail_mean_L_min >= 1 && ...
    metrics.cardiac_output_tail_mean_L_min <= 12 && ...
    metrics.map_tail_mean_mmHg >= 25 && metrics.map_tail_mean_mmHg <= 160 && ...
    metrics.tol_tail_mean >= 0 && metrics.tol_tail_mean <= 1.01;
metrics.commands_bounded = metrics.propofol_min_mg_s >= -1e-9 && ...
    metrics.propofol_peak_mg_s <= 6.67 + 1e-6 && ...
    metrics.remifentanil_min_ug_s >= -1e-9 && ...
    metrics.remifentanil_peak_ug_s <= 16.67 + 1e-6;
end

function audit = localStaticAudit(model, isReference)
blocks = find_system(model, "LookUnderMasks", "all", ...
    "FollowLinks", "on", "Type", "Block");
types = string(get_param(blocks, "BlockType"));
if isReference
    patient = model + "/Python Anesthesia Simulator";
    topSubsystems = string(find_system(model, "SearchDepth", 1, ...
        "BlockType", "SubSystem"));
    normalizedSubsystems = replace(topSubsystems, newline, " ");
    controller = topSubsystems(contains(normalizedSubsystems, ...
        "/Triggered Subsystem"));
    assert(isscalar(controller), "SimuVerity:F90:XMED10:ControllerLocator");
    patientLinks = localConnectedNames(patient);
    controllerLinks = localConnectedNames(controller);
    patientLinks = replace(patientLinks, newline, " ");
    controllerLinks = replace(controllerLinks, newline, " ");
    feedback = any(contains(controllerLinks, "Python Anesthesia Simulator")) && ...
        any(contains(patientLinks, "Triggered Subsystem"));
    normalizedBlocks = replace(string(blocks), newline, " ");
    dynamicPatient = any(contains(normalizedBlocks, ...
        "Python Anesthesia Simulator/Triggered Subsystem/MATLAB Function")) && ...
        sum(types == "S-Function") >= 1;
    dualActuation = numel(find_system(controller, "SearchDepth", 1, ...
        "BlockType", "Outport")) >= 2;
else
    feedback = true;
    dynamicPatient = any(ismember(types, ["Integrator", "DiscreteIntegrator", ...
        "StateSpace", "DiscreteStateSpace", "S-Function", "SubSystem"]));
    dualActuation = true;
end
audit = struct("block_count", numel(blocks), ...
    "subsystem_count", sum(types == "SubSystem"), ...
    "dynamic_patient_path_present", dynamicPatient, ...
    "feedback_connection_present", feedback, ...
    "dual_drug_actuator_path_present", dualActuation, ...
    "source_return_semantics_corrected_without_source_edit", isReference, ...
    "core_path_qualified", dynamicPatient && feedback && dualActuation);
end

function names = localConnectedNames(block)
names = strings(0,1);
ports = get_param(block, "PortConnectivity");
for index = 1:numel(ports)
    handles = [ports(index).SrcBlock, ports(index).DstBlock];
    handles = handles(handles > 0);
    for h = handles
        try, names(end+1,1) = string(getfullname(h)); catch, end %#ok<AGROW>
    end
end
end

function audit = localBehaviorAudit(rows)
valid = ~isempty(rows) && all([rows.valid]);
if ~valid
    audit = struct("age_axis_effective",false,"weight_axis_effective",false, ...
        "target_axis_effective",false,"dynamic_dual_actuation",false, ...
        "core_behavior_qualified",false);
    return
end
m = [rows.metrics]; nominal = m(1);
ageDelta = max(localPhysiologyDelta(nominal,m(2)),localPhysiologyDelta(nominal,m(3)));
weightDelta = max(localPhysiologyDelta(nominal,m(4)),localPhysiologyDelta(nominal,m(5)));
targetBisDelta = abs(m(6).bis_tail_mean - nominal.bis_tail_mean);
targetCommandDelta = max(abs([m(6).propofol_peak_mg_s-nominal.propofol_peak_mg_s, ...
    m(6).remifentanil_peak_ug_s-nominal.remifentanil_peak_ug_s]));
dynamicDual = all([m.propofol_range_mg_s] > 0.01) && ...
    all([m.remifentanil_range_ug_s] > 0.01);
audit = struct("age_axis_relative_response",ageDelta, ...
    "weight_axis_relative_response",weightDelta, ...
    "target_bis_tail_delta",targetBisDelta, ...
    "target_command_peak_delta",targetCommandDelta, ...
    "age_axis_effective",ageDelta >= 0.01, ...
    "weight_axis_effective",weightDelta >= 0.01, ...
    "target_axis_effective",targetBisDelta >= 3 && targetCommandDelta >= 0.02, ...
    "dynamic_dual_actuation",dynamicDual);
audit.core_behavior_qualified = audit.age_axis_effective && ...
    audit.weight_axis_effective && audit.target_axis_effective && dynamicDual;
end

function value = localPhysiologyDelta(a,b)
fields = {"loc_tail_mean","cardiac_output_tail_mean_L_min", ...
    "map_tail_mean_mmHg","tol_tail_mean"};
parts = zeros(size(fields));
for index = 1:numel(fields)
    parts(index) = abs(b.(fields{index})-a.(fields{index})) / ...
        max(abs(a.(fields{index})),1e-6);
end
value = max(parts);
end

function value = localTail(series, startTime)
mask = series.time >= startTime;
value = mean(series.data(mask));
end

function value = localSettlingTime(time, errorSignal, band, startTime)
mask = time >= startTime;
t = time(mask); e = errorSignal(mask);
bad = find(e > band, 1, "last");
if isempty(bad), value = t(1); elseif bad == numel(t), value = inf; ...
else, value = t(bad+1); end
end

function value = localSustainedEntry(time, condition, holdSeconds, startTime)
value = inf;
for index = 1:numel(time)
    if time(index) < startTime || ~condition(index), continue; end
    stop = find(time >= time(index)+holdSeconds, 1, "first");
    if ~isempty(stop) && all(condition(index:stop))
        value = time(index); return
    end
end
end

function value = localSummary(input)
input = double(input(:)); count = min(numel(input),8192);
if count == 0, value = 0; else
    value = sum(input(1:count) .* (mod((1:count)',101)+1));
end
end

function row = localEmptyScenario
row = struct("id","","inputs",struct(),"simulation_pass",false, ...
    "valid",false,"output_contract",struct(),"metrics",struct(), ...
    "complete_signal_artifact","","complete_signal_file_presence","", ...
    "wall_seconds",0,"error",struct());
end

function issue = localIssue(stage,id,message)
issue = struct("stage",string(stage),"id",string(id),"message",string(message));
end

function localConfigureRuntime(outputDir)
cache = fullfile(outputDir,"runtime","cache");
codegen = fullfile(outputDir,"runtime","codegen");
if ~isfolder(cache), mkdir(cache); end
if ~isfolder(codegen), mkdir(codegen); end
Simulink.fileGenControl("set","CacheFolder",cache, ...
    "CodeGenFolder",codegen,"createDir",true);
end

function root = localProjectRoot
root = fileparts(mfilename("fullpath"));
for level = 1:4, root = fileparts(root); end
end

function value = localRelativePath(repo,path)
value = replace(string(path),string(repo)+filesep,"");
value = replace(value,"\","/");
end

function value = localFilePresence(path)
assert(isfile(path), "SimuVerity:FileMissing", "Required file is missing: %s", path);
value = "present";
end

function value = localNow
value = string(datetime("now","TimeZone","Asia/Shanghai", ...
    "Format","yyyy-MM-dd'T'HH:mm:ssXXX"));
end

function localWriteJson(path,value)
parent = fileparts(path); if ~isfolder(parent), mkdir(parent); end
temporary = string(path)+".tmp."+string(feature("getpid"));
fid = fopen(temporary,"w","n","UTF-8"); assert(fid>=0,"SimuVerity:F90:XMED10:Write");
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,"%s\n",jsonencode(value,PrettyPrint=true));
clear cleanup
movefile(temporary,path,"f");
end

function localRemovePaths(sharedDir,modelDir,sourceEntryDir)
try, rmpath(sharedDir); catch, end
try, rmpath(modelDir); catch, end
if ~strcmp(sourceEntryDir,modelDir), try, rmpath(sourceEntryDir); catch, end, end
end
