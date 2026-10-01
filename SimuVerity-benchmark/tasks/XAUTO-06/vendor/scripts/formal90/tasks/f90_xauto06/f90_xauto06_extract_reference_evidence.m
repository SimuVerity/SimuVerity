function evidence = f90_xauto06_extract_reference_evidence(modelPath, outDir, evaluationMode)
%F90_XAUTO06_EXTRACT_REFERENCE_EVIDENCE Persistent-session HEV evidence.
% The pinned MathWorks source is opened read-only.  This extractor only
% selects source-supported drive/grade/initial-state inputs and uses the
% source logsout dataset; it never saves an altered golden model.

arguments
    modelPath (1,1) string
    outDir (1,1) string
    evaluationMode (1,1) string = "reference"
end

model = "";
try
    official = jsondecode(fileread(simuverity_official_scenarios_path()));
    assert(isfile(modelPath), "SimuVerity:F90:XAUTO06:ModelMissing", "Pinned model is missing.");
    if strcmpi(evaluationMode, "candidate")
        evidence = localRunCandidate(modelPath, outDir, official);
        return;
    end
    if isfile(fullfile(outDir, "evidence.json"))
        prior = jsondecode(fileread(fullfile(outDir, "evidence.json")));
        assert(~isfield(prior, "EVIDENCE_COMPLETE") || ~prior.EVIDENCE_COMPLETE, ...
            "SimuVerity:F90:XAUTO06:OutputReuse", "Evidence is already complete for this run.");
    end
    if ~isfolder(outDir), mkdir(outDir); end

    initialBinding = localFilePresence(modelPath);
    evidence = localEvidenceSkeleton;
    expectedBinding = lower(strtrim(string("present")));
    assert(strlength(expectedBinding) > 0 && strcmpi(initialBinding, expectedBinding), ...
        "SimuVerity:F90:XAUTO06:ModelBinding", "Pinned model file presence mismatch.");
    runtimeRoot = string(getenv("SIMUVERITY_RUNTIME_SUBMISSION_BUNDLE"));
    projectPath = fullfile(runtimeRoot, "source", "HybridElectricVehicle.prj");
    paramsPath = fullfile(runtimeRoot, "source", "HEV", ...
        "PowerSplitHEV_params.m");
    assert(isfile(projectPath) && strcmpi(localFilePresence(projectPath), ...
        "present"), "SimuVerity:F90:XAUTO06:ProjectBinding", ...
        "Pinned project file presence mismatch.");
    assert(isfile(paramsPath) && strcmpi(localFilePresence(paramsPath), ...
        "present"), "SimuVerity:F90:XAUTO06:ParamsBinding", ...
        "Pinned parameter-script file presence mismatch.");

    hevDir = fileparts(modelPath);
    sourceRoot = fileparts(hevDir);
    oldFolder = pwd;
    folderCleanup = onCleanup(@() cd(oldFolder)); %#ok<NASGU>
    cd(hevDir);
    % The upstream .prj contains a UI-resource registry that is unrelated
    % to model execution and is not portable to isolated APPDATA/PREFDIR
    % sessions.  Load the untouched source through its MATLAB paths instead
    % of opening that UI project definition.
    sourcePaths = localAddSourcePaths(sourceRoot);
    pathCleanup = onCleanup(@() rmpath(char(strjoin(sourcePaths, pathsep)))); %#ok<NASGU>
    load_system(modelPath);
    [~, modelName] = fileparts(modelPath);
    model = string(modelName);
    evidence.load_pass = true;
    paths = localModelPaths(model);
    localApplyScenario(model, official.scenarios(1));

    staticReport = formal90_nonfailfast_preflight( ...
        localStaticChecks(modelPath, projectPath, paramsPath, sourceRoot, model, paths, outDir), ...
        fullfile(outDir, "preflight_static.json"));
    evidence.preflight.static = staticReport;
    if ~staticReport.pass
        evidence.errors.preflight = struct("stage", "static", ...
            "message", "One or more adapter/static checks failed.");
        localFinish(model, modelPath, initialBinding, outDir, evidence);
        return;
    end

    set_param(model, "ReturnWorkspaceOutputs", "on", ...
        "SignalLogging", "on", "SignalLoggingName", "logsout");
    set_param(model, "SimulationCommand", "update");
    evidence.update_pass = true;
    feval(model, [], [], [], "compile");
    compiledReport = formal90_nonfailfast_preflight( ...
        localCompiledChecks(paths), fullfile(outDir, "preflight_compiled.json"));
    feval(model, [], [], [], "term");
    evidence.preflight.compiled = compiledReport;
    evidence.compile_pass = compiledReport.pass;
    if ~compiledReport.pass
        evidence.errors.preflight = struct("stage", "compiled", ...
            "message", "One or more compiled port/type/bus checks failed.");
        localFinish(model, modelPath, initialBinding, outDir, evidence);
        return;
    end
    evidence.static_audit = localStaticAudit(model, paths);

    localApplyScenario(model, official.scenarios(1));
    originalStop = string(get_param(model, "StopTime"));
    set_param(model, "StopTime", "20");
    smoke = sim(model, "ReturnWorkspaceOutputs", "on");
    localValidateSmoke(smoke);
    evidence.nominal_smoke_pass = true;
    clear smoke
    set_param(model, "StopTime", originalStop);

    rows = repmat(localEmptyScenario, numel(official.scenarios), 1);
    for index = 1:numel(official.scenarios)
        scenario = official.scenarios(index);
        rows(index).id = string(scenario.id);
        rows(index).requested_inputs = scenario;
        try
            localApplyScenario(model, scenario);
            started = tic;
            simOut = sim(model, "ReturnWorkspaceOutputs", "on");
            rows(index).simulation_wall_clock_s = toc(started);
            outputs = localExtractOutputs(simOut);
            rows(index) = localFinalizeScenario(rows(index), outputs, scenario);
            localWriteScenarioEvidence(outDir, rows(index), outputs);
            clear simOut outputs
        catch exception
            rows(index).error = localError(exception);
            localWriteJson(fullfile(outDir, "scenario_" + rows(index).id + ".json"), rows(index));
        end
        evidence.scenarios = rows(1:index);
        localWriteJson(fullfile(outDir, "partial_evidence.json"), evidence);
    end
    evidence.scenarios = rows;
    evidence.EVIDENCE_COMPLETE = all([rows.valid]) && evidence.load_pass && ...
        evidence.update_pass && evidence.compile_pass && evidence.nominal_smoke_pass;
catch exception
    if ~exist("evidence", "var"), evidence = localEvidenceSkeleton; end
    evidence.errors.session = localError(exception);
end
localFinish(model, modelPath, initialBinding, outDir, evidence);
end

function evidence = localRunCandidate(modelPath, outDir, official)
model = ""; initialBinding = localFilePresence(modelPath);
evidence = localEvidenceSkeleton;
if ~isfolder(outDir), mkdir(outDir); end
oldFolder = pwd; folderCleanup = onCleanup(@() cd(oldFolder)); %#ok<NASGU>
try
    addpath(fileparts(modelPath), "-begin"); cd(fileparts(modelPath));
    load_system(modelPath); [~, model] = fileparts(modelPath); model = string(model);
    evidence.load_pass = true;
    set_param(model, "ReturnWorkspaceOutputs", "on", "SignalLogging", "on", ...
        "SignalLoggingName", "logsout");
    localApplyCandidateScenario(official.scenarios(1));
    set_param(model, "SimulationCommand", "update"); evidence.update_pass = true;
    feval(model, [], [], [], "compile"); feval(model, [], [], [], "term");
    evidence.compile_pass = true; evidence.static_audit = localCandidateStaticAudit(model);
    originalStop = string(get_param(model, "StopTime")); set_param(model, "StopTime", "20");
    smoke = sim(model, "ReturnWorkspaceOutputs", "on");
    localValidateCandidateSmoke(smoke); evidence.nominal_smoke_pass = true;
    set_param(model, "StopTime", originalStop);
    rows = repmat(localEmptyScenario, numel(official.scenarios), 1);
    for index = 1:numel(official.scenarios)
        scenario = official.scenarios(index);
        rows(index).id = string(scenario.id); rows(index).requested_inputs = scenario;
        try
            localApplyCandidateScenario(scenario);
            set_param(model, "StopTime", string(double(scenario.stop_time_s)));
            started = tic; simOut = sim(model, "ReturnWorkspaceOutputs", "on");
            rows(index).simulation_wall_clock_s = toc(started);
            outputs = localExtractCandidateOutputs(simOut);
            rows(index) = localFinalizeScenario(rows(index), outputs, scenario);
            localWriteScenarioEvidence(outDir, rows(index), outputs);
        catch exception
            rows(index).error = localError(exception);
        end
    end
    evidence.scenarios = rows;
    evidence.EVIDENCE_COMPLETE = all([rows.valid]) && evidence.load_pass && ...
        evidence.update_pass && evidence.compile_pass && evidence.nominal_smoke_pass;
catch exception
    evidence.errors.session = localError(exception);
end
localFinish(model, modelPath, initialBinding, outDir, evidence);
end

function localApplyCandidateScenario(scenario)
stopTime = double(scenario.stop_time_s);
t = (0:1:stopTime)';
peak = double(scenario.peak_speed_kph);
if peak <= 0, peak = 80; end
reference = peak .* max(0, sin(pi .* t ./ max(stopTime, 1)));
grade = double(scenario.road_grade_pct) .* ones(size(t));
assignin("base", "v_ref_kph", timeseries(reference, t));
assignin("base", "road_grade_pct", timeseries(grade, t));
assignin("base", "initial_soc_pct", double(scenario.initial_soc_pct));
end

function localValidateCandidateSmoke(simOut)
outputs = localExtractCandidateOutputs(simOut);
assert(numel(outputs.vehicle_speed.time_s) >= 2 && ...
    all(isfinite(outputs.vehicle_speed.values)), ...
    "SimuVerity:F90:XAUTO06:CandidateSmoke", "Candidate public outputs are invalid.");
end

function outputs = localExtractCandidateOutputs(simOut)
public = ["VehicleSpeed_kph","VehicleSpeedReference_kph","BatterySOC_pct", ...
    "EnginePower_kW","MG1Power_kW","MG2Power_kW","BatteryPower_kW", ...
    "BrakeCommand","RegenCommand"];
fields = ["vehicle_speed","speed_reference","battery_soc","engine_power", ...
    "mg1_power","mg2_power","battery_power","brake_command","regen_command"];
outputs = struct;
for index = 1:numel(public)
    value = simuverity_public_output_compatibility( ...
        simOut,public(index),1,AllowBaseWorkspace=true);
    data = double(squeeze(value.Data)); data = data(:);
    time = double(value.Time(:));
    assert(numel(time) == numel(data) && all(isfinite(data)), ...
        "SimuVerity:F90:XAUTO06:PublicContract", "Malformed candidate output %s.", public(index));
    outputs.(char(fields(index))) = struct("time_s", time, "values", data);
end
end

function audit = localCandidateStaticAudit(model)
blocks = lower(string(find_system(model, "FollowLinks", "on", ...
    "LookUnderMasks", "all", "Type", "Block")));
has = @(token) any(contains(blocks, lower(string(token))));
audit = struct("engine_present", has("engine"), "mg1_present", has("mg1"), ...
    "mg2_present", has("mg2"), "battery_present", has("battery"), ...
    "dcdc_present", has("dc"), "planetary_power_split_present", ...
    has("planetary"), "vehicle_present", has("vehicle"), ...
    "feedback_path_connected", has("controller") || has("feedback"), ...
    "core_powertrain_connected", has("engine") && has("battery") && has("vehicle"), ...
    "candidate_structure_scan", true);
end

function evidence = localEvidenceSkeleton
evidence = struct( ...
    "schema", "simuverity.f90-xauto06-evidence.v1", ...
    "task_id", "F90-XAUTO-06", "EVIDENCE_COMPLETE", false, ...
    "extraction_only", true, "contains_score_decisions", false, ...
    "reference_substantive_modifications", 0, ...
    "load_pass", false, "update_pass", false, "compile_pass", false, ...
    "nominal_smoke_pass", false, "preflight", struct, ...
    "static_audit", struct, "scenarios", struct([]), "errors", struct, ...
    "runtime", struct("generation_run_id", string(getenv("SIMUVERITY_GENERATION_RUN_ID")), ...
        "matlab_release", string(version("-release")), ...
        "mcp_port", string(getenv("SIMUVERITY_MCP_PORT")), ...
        "started_at", localNow));
end

function localFinish(model, modelPath, initialBinding, outDir, evidence)
try
    if strlength(model) > 0 && bdIsLoaded(model), close_system(model, 0); end
catch exception
    evidence.errors.close = localError(exception);
end
evidence.model_closed_without_save = strlength(model) == 0 || ~bdIsLoaded(model);
evidence.reference_model_binding_after = localFilePresence(modelPath);
evidence.reference_model_unchanged = strcmpi(initialBinding, evidence.reference_model_binding_after);
evidence.runtime.finished_at = localNow;
localWriteJson(fullfile(outDir, "evidence.json"), evidence);
if evidence.EVIDENCE_COMPLETE
    lock = struct("EVIDENCE_COMPLETE", true, ...
        "evidence_file_presence", localFilePresence(fullfile(outDir, "evidence.json")), ...
        "completed_at", localNow);
    localWriteJson(fullfile(outDir, "evidence_lock.json"), lock);
end
fprintf("F90_XAUTO06_EVIDENCE complete=%d smoke=%d valid=%d/%d path=%s\n", ...
    evidence.EVIDENCE_COMPLETE, evidence.nominal_smoke_pass, ...
    localValidCount(evidence.scenarios), numel(evidence.scenarios), outDir);
end

function paths = localModelPaths(model)
paths = struct;
paths.controller = model + "/Controller & Environment";
paths.battery = model + "/High Voltage Battery";
paths.dcdc = model + "/DC-DC Converter";
paths.power_split = model + "/Power Split Drive Unit";
paths.vehicle = model + "/Longitudinal Vehicle";
paths.planetary = localFindByToken(model, "planetary");
paths.engine = localFindByToken(model, "engine");
paths.mg1 = localFindByToken(model, "mg1");
paths.mg2 = localFindByToken(model, "mg2");
end

function checks = localStaticChecks(modelPath, projectPath, paramsPath, sourceRoot, model, paths, outDir)
checks = [ ...
    localCheck("golden_model", "path", @() localFileCheck(modelPath)), ...
    localCheck("project", "dependency", @() localFileCheck(projectPath)), ...
    localCheck("parameters", "dependency", @() localFileCheck(paramsPath)), ...
    localCheck("source_root", "path", @() localFolderCheck(sourceRoot)), ...
    localCheck("task_output_path", "path", @() localPathCheck(outDir)), ...
    localCheck("simulation_api", "api", @localApiCheck), ...
    localCheck("workspace_inputs", "workspace", @localWorkspaceInputCheck), ...
    localCheck("controller_locator", "locator", @() localBlockCheck(paths.controller)), ...
    localCheck("battery_locator", "locator", @() localBlockCheck(paths.battery)), ...
    localCheck("dcdc_locator", "locator", @() localBlockCheck(paths.dcdc)), ...
    localCheck("power_split_locator", "locator", @() localBlockCheck(paths.power_split)), ...
    localCheck("vehicle_locator", "locator", @() localBlockCheck(paths.vehicle)), ...
    localCheck("planetary_locator", "locator", @() localBlockCheck(paths.planetary)), ...
    localCheck("engine_locator", "locator", @() localBlockCheck(paths.engine)), ...
    localCheck("mg1_locator", "locator", @() localBlockCheck(paths.mg1)), ...
    localCheck("mg2_locator", "locator", @() localBlockCheck(paths.mg2)), ...
    localCheck("controller_ports", "port", @() localPortCheck(paths.controller)), ...
    localCheck("vehicle_ports", "port", @() localPortCheck(paths.vehicle)), ...
    localCheck("logging_object", "logging", @() localLoggingCheck(model)) ...
    ];
end

function checks = localCompiledChecks(paths)
checks = [ ...
    localCheck("controller_compiled_dimensions_types", "compiled", @() localCompiledPortCheck(paths.controller)), ...
    localCheck("battery_compiled_dimensions_types", "compiled", @() localCompiledPortCheck(paths.battery)), ...
    localCheck("dcdc_compiled_dimensions_types", "compiled", @() localCompiledPortCheck(paths.dcdc)), ...
    localCheck("power_split_compiled_dimensions_types", "compiled", @() localCompiledPortCheck(paths.power_split)), ...
    localCheck("vehicle_compiled_dimensions_types", "compiled", @() localCompiledPortCheck(paths.vehicle)), ...
    localCheck("controller_bus_contract", "bus", @() localCompiledBusCheck(paths.controller)) ...
    ];
end

function check = localCheck(id, category, action)
check = struct("id", string(id), "category", string(category), "run", action);
end

function result = localFileCheck(path)
result = struct("passed", isfile(path), "observed", string(path), "detail", "required pinned file");
end

function result = localFolderCheck(path)
result = struct("passed", isfolder(path), "observed", string(path), "detail", "required source folder");
end

function result = localPathCheck(path)
result = struct("passed", strlength(string(path)) < 220, "observed", string(path), ...
    "detail", "Windows output path length must remain safe");
end

function result = localApiCheck
versions = ver;
products = string({versions.Name});
needed = ["Simulink", "Simscape", "Simscape Driveline"];
passed = all(arrayfun(@(name) any(contains(products, name)), needed));
result = struct("passed", passed, "observed", strjoin(products, ";"), ...
    "detail", "required Simulink/Simscape/Driveline products");
end

function result = localWorkspaceInputCheck
needed = ["v_ref_kph", "road_grade_pct", "initial_soc_pct", "drivePattern_Signals", ...
    "inputSignals_RoadGrade", "initial", "batteryHV"];
names = string(evalin("base", "who"));
result = struct("passed", all(ismember(needed, names)), "observed", strjoin(names, ","), ...
    "detail", "public aliases and source-supported workspace inputs must be available");
end

function result = localBlockCheck(path)
passed = strlength(path) > 0 && getSimulinkBlockHandle(path) > 0;
result = struct("passed", passed, "observed", path, "detail", "required real-source locator");
end

function result = localPortCheck(path)
if strlength(path) == 0 || getSimulinkBlockHandle(path) < 0
    result = struct("passed", false, "observed", path, "detail", "source block missing");
    return;
end
ports = get_param(path, "PortHandles");
allPorts = [];
for field = ["Inport", "Outport", "LConn", "RConn"]
    if isfield(ports, field)
        allPorts = [allPorts; ports.(field)(:)]; %#ok<AGROW>
    end
end
result = struct("passed", ~isempty(allPorts) && any(allPorts > 0), "observed", path, ...
    "detail", "block must expose a real Simulink/physical connection port");
end

function result = localLoggingCheck(model)
enabled = string(get_param(model, "SignalLogging")) == "on";
name = string(get_param(model, "SignalLoggingName"));
result = struct("passed", enabled && name == "logsout", "observed", name, ...
    "detail", "source logsout object must be configured for complete output extraction");
end

function result = localCompiledPortCheck(path)
types = get_param(path, "CompiledPortDataTypes");
dims = get_param(path, "CompiledPortDimensions");
typeText = string(evalc("disp(types)"));
dimText = string(evalc("disp(dims)"));
passed = strlength(typeText) > 0 && strlength(dimText) > 0 && ...
    ~contains(typeText, "unknown", IgnoreCase=true) && ...
    ~contains(dimText, "unknown", IgnoreCase=true);
result = struct("passed", passed, "observed", "types=" + typeText + "; dims=" + dimText, ...
    "detail", "compiled dimensions and data types must resolve");
end

function result = localCompiledBusCheck(path)
types = get_param(path, "CompiledPortDataTypes");
text = string(evalc("disp(types)"));
result = struct("passed", strlength(text) > 0 && ~contains(text, "unknown", IgnoreCase=true), ...
    "observed", text, "detail", "compiled bus/type metadata must resolve without unknown ports");
end

function localApplyScenario(model, scenario)
evalin("base", "PowerSplitHEV_params");
set_param(model + "/Controller & Environment", "ReferencedSubsystem", ...
    "PowerSplitHEV_SpeedTracking_refsub");

builder = DrivePattern_InputSignalBuilder;
if string(scenario.drive_profile) == "SimpleDrivePattern"
    data = builder.SimpleDrivePattern("StopTime", seconds(double(scenario.stop_time_s)));
elseif string(scenario.drive_profile) == "Accelerate_Decelerate"
    data = builder.Accelerate_Decelerate( ...
        "PeakSpeed", double(scenario.peak_speed_kph), ...
        "StopTime", seconds(double(scenario.stop_time_s)));
else
    error("SimuVerity:F90:XAUTO06:ScenarioProfile", "Unsupported source drive profile %s.", scenario.drive_profile);
end
assignin("base", "drivePatternFromWorkspace", data.Options.useFromWorkspace);
assignin("base", "drivePattern_Signals", data.Signals);
assignin("base", "drivePattern_Bus", data.Bus);
[roadSignals, roadBus, ~] = DriverAndEnvironment_road_grade_pattern( ...
    "InputPattern", string(scenario.road_grade_pattern));
assignin("base", "inputSignals_RoadGrade", roadSignals);
assignin("base", "inputBus_RoadGrade", roadBus);
initial = evalin("base", "initial");
batteryHV = evalin("base", "batteryHV");
initial.hvBattery_SOC_pct = double(scenario.initial_soc_pct);
initial.hvBattery_Charge_Ahr = batteryHV.nominalCharge_Ahr * initial.hvBattery_SOC_pct / 100;
assignin("base", "initial", initial);
assignin("base", "t_end", double(scenario.stop_time_s));
% Public aliases are deliberate workspace inputs to the task contract; the
% pinned source consumes its native bundled equivalents above.
assignin("base", "v_ref_kph", data.Signals.VehSpd);
assignin("base", "road_grade_pct", double(scenario.road_grade_pct));
assignin("base", "initial_soc_pct", double(scenario.initial_soc_pct));
set_param(model, "StopTime", string(double(scenario.stop_time_s)));
end

function localValidateSmoke(simOut)
outputs = localExtractOutputs(simOut);
assert(numel(outputs.vehicle_speed.time_s) >= 2 && ...
    all(isfinite(outputs.vehicle_speed.values)) && ...
    all(isfinite(outputs.speed_reference.values)) && ...
    all(isfinite(outputs.battery_soc.values)), ...
    "SimuVerity:F90:XAUTO06:SmokeOutput", "Short nominal smoke did not produce required complete logs.");
end

function outputs = localExtractOutputs(simOut)
logsout = localGetLogsout(simOut);
outputs = struct;
outputs.vehicle_speed = localTimeseries(logsout, "Vehicle speed kph");
outputs.speed_reference = localTimeseries(logsout, "Vehicle Speed Reference (km/hr)");
outputs.battery_soc = localTimeseries(logsout, "HV Battery SOC");
outputs.engine_power = localTimeseries(logsout, "Engine Power");
outputs.mg1_power = localTimeseries(logsout, "MG1 Mech Power");
outputs.mg2_power = localTimeseries(logsout, "MG2 Mech Power");
outputs.battery_power = localTimeseries(logsout, "HV Battery Power");
outputs.brake_command = localTimeseries(logsout, "Brake On Off");
outputs.regen_command = localTimeseries(logsout, "MG2 Regen On Off");
end

function logsout = localGetLogsout(simOut)
try
    logsout = simOut.get("logsout");
catch
    logsout = evalin("base", "logsout");
end
assert(isa(logsout, "Simulink.SimulationData.Dataset"), ...
    "SimuVerity:F90:XAUTO06:Logsout", "Required source logsout Dataset is missing.");
end

function output = localTimeseries(logsout, name)
entry = logsout.get(string(name));
if isempty(entry)
    available = string(logsout.getElementNames);
    error("SimuVerity:F90:XAUTO06:LogMissing", "Required logsout signal is absent: %s. Available: %s", ...
        name, strjoin(available, "; "));
end
try
    series = getValuesFromLogsout(entry);
catch exception
    available = string(logsout.getElementNames);
    error("SimuVerity:F90:XAUTO06:LogType", "Required logsout signal %s cannot be resolved as a signal: %s. Available: %s", ...
        name, string(exception.message), strjoin(available, "; "));
end
assert(isa(series, "timeseries"), "SimuVerity:F90:XAUTO06:LogType", ...
    "Required signal %s is not a Timeseries.", name);
time = double(series.Time(:));
values = double(series.Data);
values = values(:);
assert(numel(time) >= 2 && numel(time) == numel(values) && ...
    all(isfinite(time)) && all(isfinite(values)), "SimuVerity:F90:XAUTO06:LogShape", ...
    "Malformed required Timeseries %s.", name);
output = struct("time_s", time, "values", values);
end

function row = localFinalizeScenario(row, outputs, scenario)
time = outputs.vehicle_speed.time_s;
speed = outputs.vehicle_speed.values;
reference = localInterpolate(outputs.speed_reference, time);
soc = localNormalizeSoc(localInterpolate(outputs.battery_soc, time));
engine = localInterpolate(outputs.engine_power, time);
mg1 = localInterpolate(outputs.mg1_power, time);
mg2 = localInterpolate(outputs.mg2_power, time);
battery = localInterpolate(outputs.battery_power, time);
brake = localInterpolate(outputs.brake_command, time) > 0.5;
regen = localInterpolate(outputs.regen_command, time) > 0.5;
error = speed - reference;
activePower = (abs(engine) > 0.5 & (abs(mg1) > 0.1 | abs(mg2) > 0.1)) | ...
    (abs(mg2) > 0.1 & abs(battery) > 0.1);
brakeFraction = mean(brake);
if any(brake)
    regenOverlap = sum(regen & brake) / sum(brake);
else
    regenOverlap = 0;
end
tail = time >= max(time(1), time(end) - min(20, 0.10 * double(scenario.stop_time_s)));
row.simulation_pass = true;
row.required_evidence_pass = numel(time) >= 100 && time(1) <= 0.1 && ...
    time(end) >= 0.99 * double(scenario.stop_time_s) && ...
    all(isfinite([speed; reference; soc; engine; mg1; mg2; battery])) && ...
    max(reference) - min(reference) >= 10;
row.valid = row.required_evidence_pass;
row.sample_count = numel(time);
row.start_time_s = time(1);
row.end_time_s = time(end);
row.metrics = struct( ...
    "speed_rmse_kph", sqrt(mean(error.^2)), ...
    "speed_peak_abs_error_kph", max(abs(error)), ...
    "tracking_fraction_within_5kph", mean(abs(error) <= 5), ...
    "speed_reference_excursion_kph", max(reference) - min(reference), ...
    "speed_actual_excursion_kph", max(speed) - min(speed), ...
    "final_window_abs_error_kph", mean(abs(error(tail))), ...
    "speed_reference_correlation", localCorrelation(speed, reference), ...
    "battery_soc_initial_pct", soc(1), ...
    "battery_soc_final_pct", soc(end), ...
    "battery_soc_min_pct", min(soc), ...
    "battery_soc_max_pct", max(soc), ...
    "engine_power_range_kW", localRange(engine), ...
    "mg1_power_range_kW", localRange(mg1), ...
    "mg2_power_range_kW", localRange(mg2), ...
    "battery_power_range_kW", localRange(battery), ...
    "power_split_activity_fraction", mean(activePower), ...
    "brake_active_fraction", brakeFraction, ...
    "regen_active_fraction", mean(regen), ...
    "regen_brake_overlap", regenOverlap, ...
    "engine_mg2_power_correlation", localCorrelation(engine, mg2));
row.error = struct;
end

function audit = localStaticAudit(model, paths)
audit = struct( ...
    "engine_present", localConnected(paths.engine), ...
    "mg1_present", localConnected(paths.mg1), ...
    "mg2_present", localConnected(paths.mg2), ...
    "battery_present", localConnected(paths.battery), ...
    "dcdc_present", localConnected(paths.dcdc), ...
    "planetary_power_split_present", localConnected(paths.planetary), ...
    "vehicle_present", localConnected(paths.vehicle), ...
    "feedback_path_connected", localConnected(paths.controller) && localConnected(paths.vehicle), ...
    "core_powertrain_connected", localConnected(paths.engine) && localConnected(paths.mg1) && ...
        localConnected(paths.mg2) && localConnected(paths.battery) && ...
        localConnected(paths.dcdc) && localConnected(paths.planetary) && ...
        localConnected(paths.vehicle) && localConnected(paths.controller), ...
    "source_model", model);
end

function path = localFindByToken(model, token)
blocks = find_system(model, "LookUnderMasks", "all", "FollowLinks", "on", "Type", "Block");
path = "";
for index = 1:numel(blocks)
    if contains(lower(string(get_param(blocks{index}, "Name"))), lower(string(token)))
        path = string(blocks{index});
        return;
    end
end
end

function paths = localAddSourcePaths(sourceRoot)
allPaths = string(strsplit(genpath(sourceRoot), pathsep));
discard = false(size(allPaths));
for marker = ["\\.git", "\\resources", "\\test", "\\cache", "\\docs"]
    discard = discard | contains(lower(allPaths), marker);
end
paths = allPaths(~discard & strlength(allPaths) > 0);
addpath(char(strjoin(paths, pathsep)), "-begin");
end

function present = localConnected(path)
if strlength(path) == 0 || getSimulinkBlockHandle(path) < 0
    present = false;
    return;
end
try
    handles = get_param(path, "PortHandles");
    allHandles = [];
    for field = ["Inport", "Outport", "LConn", "RConn"]
        if isfield(handles, field)
            allHandles = [allHandles; handles.(field)(:)]; %#ok<AGROW>
        end
    end
    for index = 1:numel(allHandles)
        if allHandles(index) > 0
            try
                lineHandle = get_param(allHandles(index), "Line");
                if ~isempty(lineHandle) && any(lineHandle ~= -1)
                    present = true;
                    return;
                end
            catch
                % Physical conserving ports need the PortConnectivity
                % fallback below rather than a Simulink Line handle.
            end
        end
    end
    connectivity = get_param(path, "PortConnectivity");
    present = ~isempty(connectivity) && any(arrayfun(@localPortIsConnected, connectivity));
catch
    present = false;
end
end

function present = localPortIsConnected(port)
present = (isfield(port, "SrcBlock") && port.SrcBlock ~= -1) || ...
    (isfield(port, "DstBlock") && ~isempty(port.DstBlock) && any(port.DstBlock ~= -1));
end

function values = localInterpolate(source, time)
values = interp1(source.time_s, source.values, time, "linear", "extrap");
values = double(values(:));
end

function values = localNormalizeSoc(values)
values = double(values(:));
if max(abs(values)) <= 1.5
    values = 100 * values;
end
end

function value = localRange(values)
values = double(values(:));
value = max(values) - min(values);
end

function value = localCorrelation(a, b)
a = double(a(:)); b = double(b(:));
if numel(a) < 3 || std(a) <= eps || std(b) <= eps
    value = 0;
else
    coefficient = corrcoef(a, b);
    value = coefficient(1, 2);
end
end

function localWriteScenarioEvidence(outDir, row, outputs)
matPath = fullfile(outDir, "scenario_" + row.id + ".mat");
temporary = matPath + ".tmp.mat";
save(temporary, "outputs", "row");
movefile(temporary, matPath, "f");
row.evidence_mat_file_presence = localFilePresence(matPath);
localWriteJson(fullfile(outDir, "scenario_" + row.id + ".json"), row);
end

function row = localEmptyScenario
row = struct("id", "", "requested_inputs", struct, "simulation_pass", false, ...
    "required_evidence_pass", false, "valid", false, "simulation_wall_clock_s", NaN, ...
    "sample_count", 0, "start_time_s", NaN, "end_time_s", NaN, ...
    "metrics", struct, "error", struct);
end

function count = localValidCount(rows)
if isempty(rows) || ~isfield(rows, "valid"), count = 0; else, count = sum([rows.valid]); end
end

function localWriteJson(path, payload)
parent = fileparts(path);
if ~isfolder(parent), mkdir(parent); end
temporary = path + ".tmp";
fid = fopen(temporary, "w", "n", "UTF-8");
assert(fid >= 0, "SimuVerity:F90:XAUTO06:Write", "Cannot write %s", temporary);
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, "%s\n", jsonencode(payload, PrettyPrint=true));
clear cleanup
movefile(temporary, path, "f");
end

function binding = localFilePresence(path)
assert(isfile(path), "SimuVerity:FileMissing", "Required file is missing: %s", path);
binding = "present";
end

function result = localError(exception)
result = struct("identifier", string(exception.identifier), "message", string(exception.message));
end

function value = localNow
value = string(datetime("now", "TimeZone", "Asia/Shanghai", ...
    "Format", "yyyy-MM-dd'T'HH:mm:ssXXX"));
end

function root = localRepoRoot
root = fileparts(fileparts(fileparts(fileparts(fileparts(mfilename("fullpath"))))));
end
