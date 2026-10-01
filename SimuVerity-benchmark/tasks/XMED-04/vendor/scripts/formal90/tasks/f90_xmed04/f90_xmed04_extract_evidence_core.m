function evidence = f90_xmed04_extract_evidence_core(modelPath, outDir)
%f90_xmed04_extract_evidence_core Run scenarios with role-connected audit current.
arguments
    modelPath (1,1) string = ""
    outDir (1,1) string = ""
end

def = f90_xmed04_definition;
root = localProjectRoot;
generationRunId = string(getenv("SIMUVERITY_GENERATION_RUN_ID"));
assert(strlength(generationRunId) > 0, "SimuVerity:F90:XMED04:GenerationRunId", ...
    "SIMUVERITY_GENERATION_RUN_ID is required.");
if strlength(modelPath) == 0, modelPath = def.reference_model; end
assert(isfile(modelPath), "SimuVerity:F90:XMED04:ModelMissing", ...
    "Model under evaluation is missing: %s", modelPath);
if strlength(outDir) == 0
    outDir = fullfile(tempdir, "SimuVerity", def.formal_id, generationRunId);
end
if ~isfolder(outDir), mkdir(outDir); end
evidencePath = fullfile(outDir, "evidence.json");
assert(~isfile(evidencePath), "SimuVerity:F90:XMED04:OutputReuse", ...
    "Evidence already exists for GenerationRunId %s.", generationRunId);

localConfigureIsolation;
modelPresence = localFilePresence(modelPath);
isReference = lower(strtrim(string(getenv("SIMUVERITY_EVALUATION_SUBJECT")))) == "reference";
[modelDir, model] = fileparts(modelPath);
pathBefore = path;
cwdBefore = string(pwd);
environmentCleanup = onCleanup(@() localRestoreEnvironment(pathBefore, cwdBefore)); %#ok<NASGU>
addpath(modelDir, "-begin");
if isReference, cd(def.reference_root); end

evidence = struct;
evidence.schema = "simuverity.f90-xmed04-evidence.v1";
evidence.task_id = def.formal_id;
evidence.generation_run_id = generationRunId;
evidence.model_path = modelPath;
evidence.model_file_presence = modelPresence;
evidence.reference_subject = logical(isReference);
evidence.adapter = ternary(isReference, ...
    "reference_native_connected_signals", "public_timeseries_contract");
evidence.reference_substantive_modifications = 0;
evidence.extraction_only = true;
evidence.contains_score_decisions = false;
evidence.load_pass = false;
evidence.update_pass = false;
evidence.compile_pass = false;
evidence.scenarios = repmat(localEmptyRow, 0, 1);
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
    set_param(model, ...
        "ReturnWorkspaceOutputs", "on", ...
        "LimitDataPoints", "off");
    if isReference
        localInstallReferenceAdapter(model);
    end

    % Shared preflight and nominal smoke preparation happen before the
    % complete scenario batch in this same process.
    localApplyInputs(model, def.scenarios(1), isReference);
    set_param(model, "SimulationCommand", "update");
    evidence.update_pass = true;
    feval(model, [], [], [], "compile");
    feval(model, [], [], [], "term");
    evidence.compile_pass = true;
    evidence.static_audit = localStaticAudit(model, isReference);

    rows = repmat(localEmptyRow, 0, 1);
    for index = 1:numel(def.scenarios)
        scenario = def.scenarios(index);
        row = localEmptyRow;
        row.id = string(scenario.id);
        row.requested_inputs = scenario;
        try
            localApplyInputs(model, scenario, isReference);
            localClearPublicOutputs(isReference);
            in = Simulink.SimulationInput(model);
            in = in.setModelParameter( ...
                "StartTime", "0", ...
                "StopTime", "84600", ...
                "SignalLogging", "on", ...
                "SignalLoggingName", "logsout", ...
                "ReturnWorkspaceOutputs", "on", ...
                "LimitDataPoints", "off");
            out = sim(in);
            row.simulation_pass = true;
            row = localCollectRow(row, out, isReference);
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
    (~isReference) || localFilePresence(modelPath) == modelPresence;
evidence.finished_at = localNow;
localWriteJson(evidencePath, evidence);
if ~isempty(fatal), rethrow(fatal); end
end

function localInstallReferenceAdapter(model)
% All changes are in-memory measurement/configuration adaptations.
scope = model + "/Controller IO";
if getSimulinkBlockHandle(scope, false) > 0
    set_param(scope, "Commented", "on");
end
blocks = [ ...
    model + "/Diabetic Patient", ...
    model + "/Glucose Monitoring System", ...
    model + "/Insulin Pump", ...
    model + "/Meal", ...
    model + "/Meal"];
ports = [1, 1, 1, 2, 1];
names = [ ...
    "f90_xmed04_true_glucose", ...
    "f90_xmed04_observed_glucose", ...
    "f90_xmed04_insulin", ...
    "f90_xmed04_meal_rate", ...
    "f90_xmed04_absorbed_rate"];
for index = 1:numel(blocks)
    handles = get_param(blocks(index), "PortHandles");
    port = handles.Outport(ports(index));
    assert(port > 0, "SimuVerity:F90:XMED04:NativePort", ...
        "Required native signal port is missing: %s out%d.", ...
        blocks(index), ports(index));
    set_param(port, ...
        "DataLogging", "on", ...
        "DataLoggingNameMode", "Custom", ...
        "DataLoggingName", names(index));
end
end

function localApplyInputs(model, scenario, isReference)
names = ["MealTimes_min", "MealCarbs_g", ...
    "PatientWeight_kg", "SensorSampleTime_s"];
for name = names
    assignin("base", name, scenario.(name));
end
if ~isReference, return, end

% These are existing public knobs of the acquired source. Enabling its
% supported closed-loop mode and changing mask/workspace parameters does
% not alter the golden topology, controller, actuator, or equations.
assignin("base", "closeLoop", 1);
assignin("base", "Weight", double(scenario.PatientWeight_kg));
assignin("base", "Ts", double(scenario.SensorSampleTime_s));
set_param(model + "/Meal", ...
    "Ti", mat2str(double(scenario.MealTimes_min(:).')), ...
    "DGu", mat2str(double(scenario.MealCarbs_g(:).')));
end

function row = localCollectRow(row, out, isReference)
if isReference
    trueGlucose = out.logsout.getElement( ...
        "f90_xmed04_true_glucose").Values;
    observed = out.logsout.getElement( ...
        "f90_xmed04_observed_glucose").Values;
    insulin = out.logsout.getElement("f90_xmed04_insulin").Values;
    mealRate = out.logsout.getElement("f90_xmed04_meal_rate").Values;
    absorbedRate = out.logsout.getElement( ...
        "f90_xmed04_absorbed_rate").Values;
else
    trueGlucose = localRequiredTimeseries(out, "TrueGlucose_mg_dL");
    observed = localRequiredTimeseries(out, "ObservedGlucose_mg_dL");
    insulin = localRequiredTimeseries(out, "InsulinInfusion_mU_min");
    mealRate = localRequiredTimeseries(out, "MealCarbohydrateRate_g_s");
    absorbedRate = localRequiredTimeseries(out, "AbsorbedGlucoseRate_mmol_s");
end

[tg, vg] = localScalarSeries(trueGlucose, ...
    "TrueGlucose_mg_dL", true);
[to, vo] = localScalarSeries(observed, ...
    "ObservedGlucose_mg_dL", true);
[ti, vi] = localScalarSeries(insulin, ...
    "InsulinInfusion_mU_min", true);
[tm, vm] = localScalarSeries(mealRate, ...
    "MealCarbohydrateRate_g_s", false);
[ta, va] = localScalarSeries(absorbedRate, ...
    "AbsorbedGlucoseRate_mmol_s", false);
localAssertCoverage(tg, "TrueGlucose_mg_dL");
localAssertCoverage(to, "ObservedGlucose_mg_dL");
localAssertCoverage(ti, "InsulinInfusion_mU_min");
localAssertCoverage(tm, "MealCarbohydrateRate_g_s");
localAssertCoverage(ta, "AbsorbedGlucoseRate_mmol_s");

grid = (0:300:84600).';
g = localInterp(tg, vg, grid, "linear");
o = localInterp(to, vo, grid, "previous");
i = localInterp(ti, vi, grid, "previous");
mealIntegral = localIntegral(tm, vm);
absorbedIntegral = localIntegral(ta, va);

row.valid = true;
row.grid_time_s = grid;
row.profiles = struct( ...
    "true_glucose_mg_dL", g, ...
    "observed_glucose_mg_dL", o, ...
    "insulin_infusion_mU_min", i);
row.event_evidence = struct( ...
    "meal_rate_integral_g", mealIntegral, ...
    "absorbed_rate_integral_mmol", absorbedIntegral, ...
    "meal_rate_peak_g_s", max(vm), ...
    "absorbed_rate_peak_mmol_s", max(va), ...
    "meal_native_samples", numel(tm), ...
    "absorbed_native_samples", numel(ta));
row.summary = localSummary(grid, g, o, i, row.requested_inputs, ...
    mealIntegral, absorbedIntegral);
end

function summary = localSummary(time, glucose, observed, insulin, ...
        requested, mealIntegral, absorbedIntegral)
valid = time >= 1800;
g = glucose(valid);
o = observed(valid);
i = insulin(valid);
inRange = g >= 70 & g <= 180;
severeLow = g < 54;
severeHigh = g > 250;
mealTimes = double(requested.MealTimes_min(:)) * 60;
mealPeaks = zeros(numel(mealTimes), 1);
mealRecovery = zeros(numel(mealTimes), 1);
mealInsulinRise = zeros(numel(mealTimes), 1);
for index = 1:numel(mealTimes)
    start = mealTimes(index);
    finish = min(84600, start + 4 * 3600);
    window = time >= start & time <= finish;
    baselineWindow = time >= max(0, start - 1800) & time < start;
    if ~any(baselineWindow)
        baselineWindow = time <= start;
    end
    baselineG = median(glucose(baselineWindow), "omitnan");
    baselineI = median(insulin(baselineWindow), "omitnan");
    mealPeaks(index) = max(glucose(window), [], "omitnan");
    mealInsulinRise(index) = ...
        max(insulin(window), [], "omitnan") - baselineI;
    afterPeak = find(window & time >= start + 900);
    recovered = afterPeak(abs(glucose(afterPeak) - baselineG) <= ...
        max(18, 0.15 * max(baselineG, 1)));
    if isempty(recovered)
        mealRecovery(index) = 4 * 3600;
    else
        mealRecovery(index) = time(recovered(1)) - start;
    end
end
delta = diff(i);
summary = struct( ...
    "time_in_range_fraction", mean(inRange), ...
    "severe_hypoglycaemia_fraction", mean(severeLow), ...
    "severe_hyperglycaemia_fraction", mean(severeHigh), ...
    "glucose_min_mg_dL", min(g), ...
    "glucose_max_mg_dL", max(g), ...
    "glucose_mean_mg_dL", mean(g), ...
    "glucose_cv", std(g) / max(mean(g), 1e-9), ...
    "sensor_rmse_mg_dL", sqrt(mean((o - g).^2)), ...
    "sensor_max_abs_error_mg_dL", max(abs(o - g)), ...
    "insulin_min_mU_min", min(i), ...
    "insulin_max_mU_min", max(i), ...
    "insulin_mean_mU_min", mean(i), ...
    "insulin_std_mU_min", std(i), ...
    "insulin_change_rms_mU_min", sqrt(mean(delta.^2)), ...
    "meal_peak_glucose_mg_dL", mealPeaks, ...
    "meal_recovery_time_s", mealRecovery, ...
    "meal_insulin_rise_mU_min", mealInsulinRise, ...
    "meal_rate_integral_g", mealIntegral, ...
    "absorbed_rate_integral_mmol", absorbedIntegral, ...
    "all_values_finite", ...
        all(isfinite(g)) && all(isfinite(o)) && all(isfinite(i)));
end

function value = localRequiredTimeseries(out, name)
value = simuverity_public_output_compatibility( ...
    out, string(name), 1, AllowBaseWorkspace=true);
end

function [time, data] = localScalarSeries(value, name, requireFinite)
time = double(value.Time(:));
raw = double(value.Data);
assert(~isempty(time) && all(isfinite(time)), ...
    "SimuVerity:F90:XMED04:TimeseriesTime", "%s has invalid time.", name);
if numel(raw) == numel(time)
    data = reshape(raw, [], 1);
elseif size(raw, 1) == numel(time) && prod(size(raw, 2:ndims(raw))) == 1
    data = reshape(raw, [], 1);
else
    error("SimuVerity:F90:XMED04:TimeseriesShape", ...
        "%s must contain one scalar channel.", name);
end
[time, keep] = unique(time, "last");
data = data(keep);
assert(numel(time) >= 2 && all(diff(time) > 0), ...
    "SimuVerity:F90:XMED04:TimeseriesOrder", "%s time is not increasing.", name);
if requireFinite
    assert(all(isfinite(data)), "SimuVerity:F90:XMED04:TimeseriesFinite", ...
        "%s contains nonfinite values.", name);
else
    assert(all(isfinite(data)) && all(data >= -1e-9), ...
        "SimuVerity:F90:XMED04:MealEvidence", ...
        "%s contains invalid rate values.", name);
end
end

function localAssertCoverage(time, name)
assert(time(1) <= 1e-6 && time(end) >= 84600 - 1e-3, ...
    "SimuVerity:F90:XMED04:OutputCoverage", ...
    "%s does not cover the complete simulation.", name);
end

function values = localInterp(time, data, grid, method)
values = interp1(time, data, grid, method, "extrap");
values = double(values(:));
assert(all(isfinite(values)), "SimuVerity:F90:XMED04:Interpolation");
end

function area = localIntegral(time, data)
area = trapz(time, data);
if ~isfinite(area), area = NaN; end
end

function audit = localStaticAudit(model, isReference)
blocks = string(find_system(model, "LookUnderMasks", "all", ...
    "FollowLinks", "on", "Type", "Block"));
signature = strings(size(blocks));
blockType = strings(size(blocks));
for index = 1:numel(blocks)
    blockType(index) = lower(localGet(blocks(index), "BlockType"));
    signature(index) = lower(join([ ...
        localGet(blocks(index), "Name"), ...
        localGet(blocks(index), "MaskType"), ...
        localGet(blocks(index), "SourceBlock"), ...
        localGet(blocks(index), "ReferenceBlock"), ...
        blockType(index)], " "));
end
dynamicTypes = ["integrator", "discreteintegrator", "statespace", ...
    "discretestatespace", "transferfcn", "discretetransferfcn", ...
    "s-function"];
mealMask = contains(signature, ["meal", "carbohydrate", "absorp"]);
monitorMask = contains(signature, [ ...
    "glucose monitor", "glucose sensor", "zero-order hold", ...
    "zeroorderhold", "cgm", "sample"]);
controllerMask = contains(signature, [ ...
    "controller", "fuzzy logic", "pid", "stateflow", ...
    "matlab function"]);
actuatorMask = contains(signature, [ ...
    "insulin pump", "pump", "actuator", "saturation", "rate limiter"]);
physiologyMask = contains(signature, [ ...
    "patient", "physiology", "physio", "hovorka"]);
unclassifiedDynamicMask = ismember(blockType, dynamicTypes) & ...
    ~mealMask & ~monitorMask & ~controllerMask & ~actuatorMask;
physiologyPathMask = physiologyMask | unclassifiedDynamicMask;

role = struct;
role.physiological_dynamics = ...
    sum(ismember(blockType, dynamicTypes)) >= 2 || ...
    any(physiologyMask);
role.meal_absorption = any(mealMask);
role.sampled_monitor = any(monitorMask);
role.controller = any(controllerMask);
role.pump_or_actuator = any(actuatorMask);

if isReference
    meal = model + "/Meal";
    patient = model + "/Diabetic Patient";
    monitor = model + "/Glucose Monitoring System";
    controller = model + "/Controller";
    switchBlock = model + "/Switch";
    pump = model + "/Insulin Pump";
    connected = localDirectedReachable(meal, patient) && ...
        localDirectedReachable(patient, monitor) && ...
        localDirectedReachable(monitor, controller) && ...
        localDirectedReachable(controller, switchBlock) && ...
        localDirectedReachable(switchBlock, pump) && ...
        localDirectedReachable(pump, patient);
else
    mealBlocks = blocks(mealMask);
    physiologyBlocks = blocks(physiologyPathMask);
    monitorBlocks = blocks(monitorMask);
    controllerBlocks = blocks(controllerMask);
    actuatorBlocks = blocks(actuatorMask);
    rolePath = struct( ...
        "meal_to_physiology", ...
            localAnyDirectedReachable(mealBlocks, physiologyBlocks), ...
        "physiology_to_monitor", ...
            localAnyDirectedReachable(physiologyBlocks, monitorBlocks), ...
        "monitor_to_controller", ...
            localAnyDirectedReachable(monitorBlocks, controllerBlocks), ...
        "controller_to_actuator", ...
            localAnyDirectedReachable(controllerBlocks, actuatorBlocks), ...
        "actuator_to_physiology", ...
            localAnyDirectedReachable(actuatorBlocks, physiologyBlocks));
    connected = all(structfun(@logical, rolePath));
end
audit = struct( ...
    "roles", role, ...
    "connected_feedback_path", connected, ...
    "core_path_qualified", ...
        all(structfun(@logical, role)) && connected, ...
    "role_detection_uses_structure_and_connectivity", true, ...
    "role_specific_path_required", true);
if ~isReference
    audit.role_specific_path = rolePath;
end
end

function pass = localAnyDirectedReachable(sources, targets)
pass = false;
for source = reshape(string(sources), 1, [])
    for target = reshape(string(targets), 1, [])
        if source ~= target && localDirectedReachable(source, target)
            pass = true;
            return
        end
    end
end
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
evalin("base", "clear TrueGlucose_mg_dL ObservedGlucose_mg_dL " + ...
    "InsulinInfusion_mU_min MealCarbohydrateRate_g_s " + ...
    "AbsorbedGlucoseRate_mmol_s");
end

function row = localEmptyRow
row = struct( ...
    "id", "", ...
    "requested_inputs", struct, ...
    "simulation_pass", false, ...
    "valid", false, ...
    "grid_time_s", [], ...
    "profiles", struct, ...
    "event_evidence", struct, ...
    "summary", struct, ...
    "error", struct);
end

function localConfigureIsolation
cacheRoot = string(getenv("SIMULINK_CACHE_FOLDER"));
codegenRoot = string(getenv("SIMULINK_CODEGEN_FOLDER"));
assert(strlength(cacheRoot) > 0 && strlength(codegenRoot) > 0, ...
    "SimuVerity:F90:XMED04:Isolation", ...
    "SIMULINK_CACHE_FOLDER and SIMULINK_CODEGEN_FOLDER are required.");
if ~isfolder(cacheRoot), mkdir(cacheRoot); end
if ~isfolder(codegenRoot), mkdir(codegenRoot); end
Simulink.fileGenControl("set", ...
    "CacheFolder", cacheRoot, ...
    "CodeGenFolder", codegenRoot, ...
    "createDir", true);
set(groot, "defaultFigureVisible", "off");
end

function localRestoreEnvironment(pathBefore, cwdBefore)
try, path(pathBefore); catch, end
try, cd(cwdBefore); catch, end
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
assert(fid >= 0, "SimuVerity:F90:XMED04:WriteJson", ...
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
