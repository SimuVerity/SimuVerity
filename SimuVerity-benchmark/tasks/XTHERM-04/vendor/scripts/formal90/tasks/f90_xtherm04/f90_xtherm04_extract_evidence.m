function evidence = f90_xtherm04_extract_evidence(modelPath, outputDir, officialScenarios, evaluatorAssetRoot)
%F90_XTHERM04_EXTRACT_EVIDENCE Extract score-free evidence in one session.
%
% The R2025a example is never saved. The adapter disables only the
% nonphysical P-H visualization in memory, applies existing temperature and
% heat-gain parameters, logs native Results signals, and reads Simscape
% thermo-fluid evidence. Scoring is intentionally offline.

arguments
    modelPath (1,1) string
    outputDir (1,1) string
    officialScenarios (1,1) string
    evaluatorAssetRoot (1,1) string
end
outDir = outputDir;
sourceRoot = evaluatorAssetRoot;
assert(isfile(officialScenarios), "SimuVerity:F90:XTHERM04:OfficialScenarios", ...
    "Official scenarios are missing.");
assert(isfolder(sourceRoot), "SimuVerity:F90:XTHERM04:ReferenceAssetRoot", ...
    "Evaluator asset root is missing.");
official = jsondecode(fileread(officialScenarios));
expectedPresence = lower(strtrim(string("present")));
assert(strcmpi(localFilePresenceFile(modelPath), expectedPresence), ...
    "SimuVerity:F90:XTHERM04:ReferenceIdentity", ...
    "Reference file presence differs from the task binding.");

generationRunId = string(getenv("SIMUVERITY_GENERATION_RUN_ID"));
assert(strlength(generationRunId) > 0, "SimuVerity:F90:XTHERM04:GenerationRunId", ...
    "SIMUVERITY_GENERATION_RUN_ID is required.");
assert(isfile(modelPath), "SimuVerity:F90:XTHERM04:ReferenceMissing", ...
    "The unchanged R2025a reference is missing.");
assert(~isfolder(outDir), "SimuVerity:F90:XTHERM04:OutputReuse", ...
    "Evidence output already exists for GenerationRunId %s.", generationRunId);
mkdir(outDir);

localConfigureIsolation;
set(groot, "defaultFigureVisible", "off");
oldDir = pwd;
dirCleanup = onCleanup(@() cd(oldDir)); %#ok<NASGU>
cd(sourceRoot);

evidence = struct;
evidence.schema = "simuverity.f90-xtherm04-evidence.v1";
evidence.task_id = "F90-XTHERM-04";
evidence.source = struct( ...
    "owner", "MathWorks", ...
    "release", "R2025a", ...
    "example", "Reversible Heat Pump", ...
    "model", "ReversibleHeatPump.slx", ...
    "file_presence", ...
    "present");
evidence.reference_substantive_modifications = 0;
evidence.extraction_only = true;
evidence.contains_score_decisions = false;
evidence.load_pass = false;
evidence.update_pass = false;
evidence.compile_pass = false;
evidence.model_closed_without_save = false;
evidence.scenarios = repmat(localEmptyScenario, 0, 1);
evidence.static_audit = struct;
evidence.errors = struct;
evidence.started_at = localNow;
evidence.runtime = localRuntime(generationRunId);

model = "";
artifacts = repmat(struct("id", "", "signals", struct), ...
    numel(official.scenarios), 1);
try
    modelHandle = load_system(modelPath);
    model = string(get_param(modelHandle, "Name"));
    modelCleanup = onCleanup(@() localCloseModel(model)); %#ok<NASGU>
    evidence.load_pass = true;
    set_param(model, ...
        "StopTime", string(official.simulation.stop_time_s), ...
        "ReturnWorkspaceOutputs", "on", ...
        "SignalLogging", "on", ...
        "SignalLoggingName", "logsout", ...
        "SignalLoggingSaveFormat", "Dataset", ...
        "LimitDataPoints", "off", ...
        "SimscapeLogType", "all", ...
        "SimscapeLogLimitData", "off", ...
        "SimscapeLogOpenViewer", "off", ...
        "SimscapeLogToSDI", "off");
    set_param(model + "/P-H Diagram", "Commented", "on");
    try
        set_param(model + "/Results", "Open", "off");
    catch
    end
    localEnableNativeResultLogging(model);
    localApplyScenario(model, official.scenarios(1));

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
            try
                feval(model, [], [], [], "term");
            catch
            end
        end
    end

    evidence.static_audit = localStaticAudit(model);
    rows = repmat(localEmptyScenario, numel(official.scenarios), 1);
    scenarioWall = zeros(numel(official.scenarios), 1);
    for index = 1:numel(official.scenarios)
        scenario = official.scenarios(index);
        rows(index).id = string(scenario.id);
        rows(index).requested_inputs = rmfield(scenario, "id");
        artifacts(index).id = string(scenario.id);
        started = tic;
        try
            localApplyScenario(model, scenario);
            simOut = sim(model, ...
                "ReturnWorkspaceOutputs", "on", ...
                "StopTime", string(official.simulation.stop_time_s));
            scenarioWall(index) = toc(started);
            [simlog, logsout] = localGetSimulationLogs(simOut);
            [signals, locators] = localExtractEvidence(simlog, logsout);
            values = [signals.thermal_state, signals.hvac_control, ...
                signals.heat_flow_state, signals.power_cop_state, ...
                signals.refrigerant_state];
            rows(index).simulation_pass = true;
            rows(index).sample_count = numel(signals.time_s);
            rows(index).end_time_s = signals.time_s(end);
            rows(index).time_coverage_pass = ...
                signals.time_s(1) <= 0.05 && ...
                signals.time_s(end) >= ...
                    double(official.simulation.stop_time_s) - 1.0;
            rows(index).required_evidence_pass = ...
                rows(index).sample_count >= 100 && ...
                mean(isfinite(values), "all") >= 0.999999;
            rows(index).valid = rows(index).time_coverage_pass && ...
                rows(index).required_evidence_pass;
            rows(index).metrics = struct( ...
                "finite_fraction", mean(isfinite(values), "all"), ...
                "requested_T_set_degC", double(scenario.T_set_degC), ...
                "requested_T_house_init_degC", ...
                    double(scenario.T_house_init_degC), ...
                "requested_T_ambient_cold_degC", ...
                    double(scenario.T_ambient_cold_degC), ...
                "requested_T_ambient_hot_degC", ...
                    double(scenario.T_ambient_hot_degC), ...
                "requested_internal_heat_gain_scale", ...
                    double(scenario.internal_heat_gain_scale));
            rows(index).locators = locators;
            artifacts(index).signals = signals;
        catch ME
            scenarioWall(index) = toc(started);
            rows(index).simulation_pass = false;
            rows(index).valid = false;
            rows(index).error = localError(ME);
        end
        rows(index).wall_clock_seconds = scenarioWall(index);
    end
    evidence.scenarios = rows;
    evidence.runtime.scenario_wall_clock_seconds = scenarioWall;
    evidence.runtime.total_simulation_wall_clock_seconds = sum(scenarioWall);
    rawPath = fullfile(outDir, "raw_evidence.mat");
    save(rawPath, "artifacts", "-v7.3");
    evidence.raw_artifact = struct( ...
        "path", string(rawPath), ...
        "format", "MAT-v7.3", ...
        "variable", "artifacts");
catch ME
    evidence.errors.session = localError(ME);
end

localCloseModel(model);
evidence.model_closed_without_save = strlength(model) == 0 || ~bdIsLoaded(model);
evidence.finished_at = localNow;
evidencePath = fullfile(outDir, "evidence.json");
localWriteJson(evidencePath, evidence);
fprintf("F90_XTHERM04_EVIDENCE load=%d update=%d compile=%d valid=%d/%d path=%s\n", ...
    evidence.load_pass, evidence.update_pass, evidence.compile_pass, ...
    localValidCount(evidence.scenarios), numel(evidence.scenarios), ...
    evidencePath);
end

function localApplyScenario(model, scenario)
assignin("base", "T_house_init", double(scenario.T_house_init_degC));
assignin("base", "T_set", double(scenario.T_set_degC));
assignin("base", "T_env", double(scenario.T_ambient_cold_degC));
ambientTable = sprintf("[%.17g %.17g %.17g %.17g]", ...
    double(scenario.T_ambient_cold_degC), ...
    double(scenario.T_ambient_cold_degC), ...
    double(scenario.T_ambient_hot_degC), ...
    double(scenario.T_ambient_hot_degC));
set_param(model + "/Environment Temperature", "Table", ambientTable);
scale = double(scenario.internal_heat_gain_scale);
set_param(model + "/House/Appliances Heat Gain", ...
    "heat_flow", sprintf("%.17g", 500 * scale));
set_param(model + "/House/Occupant Heat Gain", ...
    "heat_flow", sprintf("%.17g", 4 * 70 * scale));
end

function localEnableNativeResultLogging(model)
ports = get_param(model + "/Subsystem", "PortHandles");
names = ["thermal_state_native", "heat_flow_state_native", ...
    "hvac_control_native"];
assert(numel(ports.Outport) == 3, "SimuVerity:F90:XTHERM04:ResultsPorts", ...
    "The native Results producer no longer has three outputs.");
for index = 1:3
    set_param(ports.Outport(index), ...
        "DataLogging", "on", ...
        "DataLoggingNameMode", "Custom", ...
        "DataLoggingName", names(index));
end
end

function [simlog, logsout] = localGetSimulationLogs(simOut)
simlog = [];
logsout = [];
names = string(simOut.who);
for name = ["simlog_ReversibleHeatPump", "simlog"]
    if any(names == name)
        simlog = simOut.get(name);
        break;
    end
end
for name = ["logsout_ReversibleHeatPump", "logsout"]
    if any(names == name)
        logsout = simOut.get(name);
        break;
    end
end
assert(~isempty(simlog), "SimuVerity:F90:XTHERM04:SimlogMissing", ...
    "Native Simscape evidence is missing.");
assert(~isempty(logsout), "SimuVerity:F90:XTHERM04:LogsoutMissing", ...
    "Native Results signal logging is missing.");
end

function [signals, locators] = localExtractEvidence(simlog, logsout)
thermal = localLoggedArray(logsout, "thermal_state_native");
heat = localLoggedArray(logsout, "heat_flow_state_native");
control = localLoggedArray(logsout, "hvac_control_native");
t = thermal.time;
thermalData = localInterpMatrix(thermal, t);
heatData = localInterpMatrix(heat, t);
controlData = localInterpMatrix(control, t);
assert(size(thermalData, 2) == 3 && size(heatData, 2) == 3 && ...
    size(controlData, 2) == 4, "SimuVerity:F90:XTHERM04:NativeWidth", ...
    "Native Results signal widths changed.");

compressorPower = localNodeSeries(simlog, ...
    "Compressor.mechanical_power", "kW");
outdoorFanPower = localNodeSeries(simlog, ...
    "External_Environment.Fan.mechanical_power", "kW");
indoorFanPower = localNodeSeries(simlog, ...
    "House.Fan.mechanical_power", "kW");
indoorPressure = localNodeSeries(simlog, ...
    "Indoor_Heat_Exchanger.two_phase_fluid_1.p", "MPa");
outdoorPressure = localNodeSeries(simlog, ...
    "Outdoor_Heat_Exchanger.two_phase_fluid_1.p", "MPa");
indoorSaturation = localNodeSeries(simlog, ...
    "Indoor_Heat_Exchanger.two_phase_fluid_1.T_sat_liq", "degC");
outdoorSaturation = localNodeSeries(simlog, ...
    "Outdoor_Heat_Exchanger.two_phase_fluid_1.T_sat_vap", "degC");
compressorFlow = localNodeSeries(simlog, ...
    "Compressor.mdot_A", "kg/s");
exvFlow = localNodeSeries(simlog, ...
    "Electronic_Expansion_Valve.mdot_A", "kg/s");

comp = abs(localInterpVector(compressorPower, t));
fanIn = abs(localInterpVector(indoorFanPower, t));
fanOut = abs(localInterpVector(outdoorFanPower, t));
totalPower = comp + fanIn + fanOut;
cop = abs(heatData(:, 2)) ./ max(totalPower, 1e-6);
signals = struct;
signals.time_s = t;
signals.thermal_state = thermalData;
signals.hvac_control = controlData;
signals.heat_flow_state = heatData;
signals.power_cop_state = [comp, fanIn, fanOut, totalPower, cop];
signals.refrigerant_state = [ ...
    localInterpVector(indoorPressure, t), ...
    localInterpVector(outdoorPressure, t), ...
    localInterpVector(indoorSaturation, t), ...
    localInterpVector(outdoorSaturation, t), ...
    localInterpVector(compressorFlow, t), ...
    localInterpVector(exvFlow, t)];
locators = struct( ...
    "thermal_state", thermal.locator, ...
    "heat_flow_state", heat.locator, ...
    "hvac_control", control.locator, ...
    "compressor_power", compressorPower.locator, ...
    "indoor_fan_power", indoorFanPower.locator, ...
    "outdoor_fan_power", outdoorFanPower.locator, ...
    "indoor_pressure", indoorPressure.locator, ...
    "outdoor_pressure", outdoorPressure.locator, ...
    "compressor_flow", compressorFlow.locator, ...
    "expansion_valve_flow", exvFlow.locator);
end

function series = localLoggedArray(logsout, name)
element = logsout.getElement(char(name));
assert(~isempty(element) && isa(element.Values, "timeseries"), ...
    "SimuVerity:F90:XTHERM04:LoggedSignal", ...
    "Native logged signal %s is missing.", name);
time = double(element.Values.Time(:));
data = double(squeeze(element.Values.Data));
if size(data, 1) ~= numel(time) && size(data, 2) == numel(time)
    data = data.';
end
assert(size(data, 1) == numel(time), "SimuVerity:F90:XTHERM04:LoggedShape", ...
    "Native logged signal %s has an unexpected shape.", name);
series = struct("time", time, "data", data, "locator", string(name));
end

function series = localNodeSeries(root, locator, unit)
node = root;
for token = split(string(locator), ".")'
    node = node.(char(token));
end
logSeries = node.series;
timeValues = logSeries.time;
series = struct( ...
    "time", double(timeValues(:)), ...
    "data", double(squeeze(logSeries.values(char(unit)))), ...
    "locator", string(locator));
series.data = series.data(:);
end

function values = localInterpVector(series, t)
sourceT = double(series.time(:));
sourceY = double(series.data(:));
[sourceT, uniqueIndex] = unique(sourceT, "last");
sourceY = sourceY(uniqueIndex);
values = interp1(sourceT, sourceY, t, "linear", "extrap");
values = double(values(:));
end

function values = localInterpMatrix(series, t)
sourceT = double(series.time(:));
sourceY = double(series.data);
[sourceT, uniqueIndex] = unique(sourceT, "last");
sourceY = sourceY(uniqueIndex, :);
values = zeros(numel(t), size(sourceY, 2));
for column = 1:size(sourceY, 2)
    values(:, column) = interp1(sourceT, sourceY(:, column), ...
        t, "linear", "extrap");
end
end

function audit = localStaticAudit(model)
blocks = string(find_system(model, ...
    "LookUnderMasks", "all", "FollowLinks", "on", "Type", "Block"));
references = strings(size(blocks));
types = strings(size(blocks));
for index = 1:numel(blocks)
    try
        references(index) = string(get_param(blocks(index), "ReferenceBlock"));
    catch
    end
    try
        types(index) = string(get_param(blocks(index), "BlockType"));
    catch
    end
end
names = lower(blocks);
library = lower(references);
normalizedNames = regexprep(names, "[^a-z0-9]+", " ");
audit = struct;
audit.block_count = numel(blocks);
audit.line_count = numel(find_system(model, "FindAll", "on", "Type", "line"));
audit.compressor_count = sum(contains(library, "compressor"));
audit.heat_exchanger_signature = ...
    any(contains(normalizedNames, "indoor heat exchanger")) && ...
    any(contains(normalizedNames, "outdoor heat exchanger"));
audit.expansion_valve_signature = ...
    any(contains(normalizedNames, "electronic expansion valve"));
audit.reversing_valve_signature = ...
    any(contains(normalizedNames, "directional") & ...
        contains(normalizedNames, "valve"));
audit.accumulator_signature = any(contains(normalizedNames, "accumulator"));
audit.moist_air_house_signature = ...
    any(contains(normalizedNames, "house air") & ...
        contains(normalizedNames, "volume"));
audit.temperature_sensor_signature = ...
    any(contains(normalizedNames, "temperature sensor"));
audit.integrator_count = sum(types == "Integrator");
audit.feedback_sum_count = sum(types == "Sum");
audit.control_signature = any(contains(normalizedNames, "control")) && ...
    any(contains(normalizedNames, "compressor control"));
audit.thermo_fluid_path_signature = ...
    audit.compressor_count >= 1 && ...
    audit.heat_exchanger_signature && ...
    audit.expansion_valve_signature && ...
    audit.reversing_valve_signature && ...
    audit.accumulator_signature && ...
    audit.moist_air_house_signature;
audit.closed_loop_temperature_signature = ...
    audit.control_signature && audit.temperature_sensor_signature && ...
    audit.feedback_sum_count >= 1;
audit.required_products = ["Simulink", "Simscape", "Simscape Fluids"];
products = ver;
installed = string({products.Name});
audit.required_products_available = all(ismember( ...
    audit.required_products, installed));
end

function localConfigureIsolation
cache = string(getenv("SIMULINK_CACHE_FOLDER"));
codegen = string(getenv("SIMULINK_CODEGEN_FOLDER"));
assert(strlength(cache) > 0 && strlength(codegen) > 0, ...
    "SimuVerity:F90:XTHERM04:Isolation", ...
    "SIMULINK_CACHE_FOLDER and SIMULINK_CODEGEN_FOLDER are required.");
Simulink.fileGenControl("set", ...
    "CacheFolder", cache, "CodeGenFolder", codegen, ...
    "createDir", true);
end

function value = localRuntime(generationRunId)
value = struct( ...
    "generation_run_id", generationRunId, ...
    "matlab_release", string(version("-release")), ...
    "matlab_prefdir", string(getenv("MATLAB_PREFDIR")), ...
    "appdata", string(getenv("APPDATA")), ...
    "temp", string(getenv("TEMP")), ...
    "cache", string(getenv("SIMULINK_CACHE_FOLDER")), ...
    "codegen", string(getenv("SIMULINK_CODEGEN_FOLDER")), ...
    "mcp_port", string(getenv("SIMUVERITY_MCP_PORT")));
end

function row = localEmptyScenario
row = struct( ...
    "id", "", ...
    "requested_inputs", struct, ...
    "simulation_pass", false, ...
    "time_coverage_pass", false, ...
    "required_evidence_pass", false, ...
    "valid", false, ...
    "sample_count", 0, ...
    "end_time_s", 0, ...
    "wall_clock_seconds", 0, ...
    "metrics", struct, ...
    "locators", struct, ...
    "error", struct);
end

function count = localValidCount(rows)
if isempty(rows) || ~isfield(rows, "valid")
    count = 0;
else
    count = sum([rows.valid]);
end
end

function localCloseModel(model)
try
    if bdIsLoaded(model)
        close_system(model, 0);
    end
catch
end
end

function payload = localError(ME)
payload = struct( ...
    "identifier", string(ME.identifier), ...
    "message", string(ME.message));
end

function value = localNow
value = string(datetime("now", "TimeZone", "Asia/Shanghai", ...
    "Format", "yyyy-MM-dd'T'HH:mm:ssXXX"));
end

function localWriteJson(path, payload)
text = jsonencode(payload, "PrettyPrint", true);
fid = fopen(path, "w", "n", "UTF-8");
assert(fid >= 0, "SimuVerity:F90:XTHERM04:Write", "Cannot write %s.", path);
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, "%s\n", text);
end

function binding = localFilePresenceFile(pathValue)
assert(isfile(pathValue), "SimuVerity:FileMissing", "Required file is missing: %s", pathValue);
binding = "present";
end

function root = localRepoRoot
root = fileparts(mfilename("fullpath"));
for level = 1:4
    root = fileparts(root);
end
end
