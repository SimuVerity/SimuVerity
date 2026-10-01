function receipt = f90_xtherm06_score_model(modelPath, outDir, evaluationMode)
%F90_XTHERM06_SCORE_MODEL One-session evidence extraction for the dedicated scorer.
%
% With no arguments this is the single lane-B evidence entry.  All six
% official scenarios run sequentially in one MATLAB process.  Score-free
% evidence is fixed on disk and can then be recalculated by the pure Python
% offline scorer without starting MATLAB again.
arguments
    modelPath (1,1) string = ""
    outDir (1,1) string = ""
    evaluationMode (1,1) string = "reference"
end
candidateMode = strcmpi(evaluationMode, "candidate");

root = string(getenv("SIMUVERITY_TASK_VENDOR_ROOT"));
taskRoot = string(getenv("SIMUVERITY_TASK_ROOT"));
referenceRoot = string(getenv("SIMUVERITY_RUNTIME_SUBMISSION_BUNDLE"));
assert(strlength(modelPath) > 0, "SimuVerity:F90:XTHERM06:CandidatePath", ...
    "Candidate evaluation requires an explicit model path.");
generationRunId = string(getenv("SIMUVERITY_GENERATION_RUN_ID"));
assert(strlength(generationRunId) > 0, "SimuVerity:F90:XTHERM06:GenerationRunId", ...
    "SIMUVERITY_GENERATION_RUN_ID is required.");
if strlength(outDir) == 0
    outDir = fullfile(tempdir, "SimuVerity", "F90-XTHERM-06", generationRunId);
end
assert(~isfolder(outDir), "SimuVerity:F90:XTHERM06:OutputReuse", ...
    "Evidence output already exists for GenerationRunId %s.", generationRunId);
mkdir(outDir);

official = jsondecode(fileread(simuverity_official_scenarios_path()));
if ~candidateMode
    addpath(referenceRoot);
    addpath(fullfile(referenceRoot, "Libraries"));
    addpath(fullfile(referenceRoot, "Scripts_Data"));
else
    addpath(fileparts(modelPath), "-begin");
end
addpath(fullfile(root, "scripts", "formal90", "tasks", "f90_xtherm06"));
assert(isfile(modelPath), "SimuVerity:F90:XTHERM06:ReferenceMissing", ...
    "Model is missing: %s", modelPath);

cacheDir = string(getenv("SIMULINK_CACHE_FOLDER"));
codegenDir = string(getenv("SIMULINK_CODEGEN_FOLDER"));
assert(strlength(cacheDir) > 0 && strlength(codegenDir) > 0, ...
    "SimuVerity:F90:XTHERM06:Isolation", ...
    "Isolated Simulink cache and codegen folders are required.");
Simulink.fileGenControl("set", "CacheFolder", cacheDir, ...
    "CodeGenFolder", codegenDir, "createDir", true);
set(groot, "defaultFigureVisible", "off");

receipt = struct;
receipt.schema = "simuverity.f90-xtherm06-evidence.v1";
receipt.task_id = "F90-XTHERM-06";
if candidateMode
    receipt.adapter = "candidate_public_timeseries_contract";
else
    receipt.adapter = "unchanged_direct_golden_with_noninvasive_logging";
end
receipt.reference_substantive_modifications = 0;
receipt.extraction_only = true;
receipt.contains_score_decisions = false;
receipt.load_pass = false;
receipt.update_pass = false;
receipt.compile_pass = false;
receipt.static_audit = struct;
receipt.scenarios = struct([]);
receipt.errors = struct;
receipt.started_at = localNow;
receipt.runtime = struct( ...
    "generation_run_id", generationRunId, ...
    "matlab_release", string(version("-release")), ...
    "matlab_prefdir", string(getenv("MATLAB_PREFDIR")), ...
    "appdata", string(getenv("APPDATA")), ...
    "temp", string(getenv("TEMP")), ...
    "cache", cacheDir, ...
    "codegen", codegenDir, ...
    "mcp_port", string(getenv("SIMUVERITY_MCP_PORT")));

old = pwd;
cleanupDir = onCleanup(@() cd(old)); %#ok<NASGU>
[~, model] = fileparts(modelPath);
scenarioArtifacts = repmat(struct("id", "", "time_s", [], ...
    "outputs", struct), numel(official.scenarios), 1);
try
    if candidateMode
        cd(fileparts(modelPath));
    else
        cd(referenceRoot);
    end
    load_system(modelPath);
    modelCleanup = onCleanup(@() localCloseModel(model)); %#ok<NASGU>
    receipt.load_pass = true;
    set_param(model, ...
        "ReturnWorkspaceOutputs", "on", ...
        "SignalLogging", "on", ...
        "SignalLoggingName", "logsout", ...
        "StopTime", num2str(double(official.simulation.stop_s), "%.15g"));
    if ~candidateMode
        localEnableReferenceLogging(model);
        receipt.static_audit = localStaticAudit(model);
    else
        receipt.static_audit = localCandidateStaticAudit(model);
    end

    localApplyScenario(model, official.scenarios(1), candidateMode);
    try
        set_param(model, "SimulationCommand", "update");
        receipt.update_pass = true;
    catch ME
        receipt.errors.update = localError(ME);
    end
    if receipt.update_pass
        compiled = false;
        try
            feval(model, [], [], [], "compile");
            compiled = true;
            receipt.compile_pass = true;
        catch ME
            receipt.errors.compile = localError(ME);
        end
        if compiled
            try
                feval(model, [], [], [], "term");
            catch
            end
        end
    end

    rows = repmat(localEmptyScenario, numel(official.scenarios), 1);
    for index = 1:numel(official.scenarios)
        scenario = official.scenarios(index);
        rows(index).id = string(scenario.id);
        rows(index).requested_inputs = struct( ...
            "Cooling_Enable", double(scenario.Cooling_Enable), ...
            "AmbientTemp_C", double(scenario.AmbientTemp_C), ...
            "CoolantMassFlow_kgps", ...
                double(scenario.CoolantMassFlow_kgps));
        scenarioArtifacts(index).id = string(scenario.id);
        try
            localApplyScenario(model, scenario, candidateMode);
            simOut = sim(model, "ReturnWorkspaceOutputs", "on");
            [time, outputs, paths] = localExtractOutputs( ...
                simOut, model, double(official.simulation.stop_s), scenario, ...
                candidateMode);
            localValidateOutputs(time, outputs, ...
                double(official.simulation.stop_s));
            rows(index).simulation_pass = true;
            rows(index).valid = true;
            rows(index).time_start_s = time(1);
            rows(index).time_end_s = time(end);
            rows(index).sample_count = numel(time);
            rows(index).selected_paths = paths;
            rows(index).summary = localSummary(time, outputs);
            scenarioArtifacts(index).time_s = time;
            scenarioArtifacts(index).outputs = outputs;
        catch ME
            rows(index).simulation_pass = false;
            rows(index).valid = false;
            rows(index).error = localError(ME);
        end
    end
    receipt.scenarios = localAttachOutputs(rows, scenarioArtifacts);
    rawPath = fullfile(outDir, "raw_evidence.mat");
    save(rawPath, "scenarioArtifacts", "-v7.3");
    receipt.raw_artifact = struct( ...
        "path", string(rawPath), ...
        "format", "MAT-v7.3", ...
        "variable", "scenarioArtifacts");
catch ME
    receipt.errors.session = localError(ME);
end

localCloseModel(model);
receipt.model_closed_without_save = ~bdIsLoaded(model);
receipt.finished_at = localNow;
evidencePath = fullfile(outDir, "evidence.json");
localWriteJson(evidencePath, receipt);
fprintf("F90_XTHERM06_EVIDENCE load=%d update=%d compile=%d valid=%d/%d path=%s\n", ...
    receipt.load_pass, receipt.update_pass, receipt.compile_pass, ...
    sum([receipt.scenarios.valid]), numel(receipt.scenarios), evidencePath);
end

function localApplyScenario(model, scenario, candidateMode)
assignin("base", "Cooling_Enable", double(scenario.Cooling_Enable));
assignin("base", "AmbientTemp_C", double(scenario.AmbientTemp_C));
assignin("base", "CoolantMassFlow_kgps", ...
    double(scenario.CoolantMassFlow_kgps));

% Direct-golden adapter: map only public inputs into parameters already
% supported by the unchanged source model.
if ~candidateMode && bdIsLoaded(model) && ...
        getSimulinkBlockHandle(model + "/Pump", false) > 0
    if ~evalin("base", "exist('bev','var')")
        bev_motor_cooling_param;
    end
    bev = evalin("base", "bev");
    bev.Tambient = double(scenario.AmbientTemp_C);
    assignin("base", "bev", bev);
    assignin("base", "Cooling_On", double(scenario.Cooling_Enable));
    set_param(model + "/Pump", "mass_flow", ...
        sprintf("%.17g", double(scenario.CoolantMassFlow_kgps)));
end
end

function localEnableReferenceLogging(model)
% The exact linked source path was statically checked before the only
% evidence session.  Logging is an in-memory signal tap and is never saved.
target = model + "/Driver/Determine Target Speed";
assert(getSimulinkBlockHandle(target, false) > 0, ...
    "SimuVerity:F90:XTHERM06:TargetBlockMissing", ...
    "Native target-speed subsystem is missing.");
ports = get_param(target, "PortHandles");
assert(~isempty(ports.Outport) && ports.Outport(1) > 0, ...
    "SimuVerity:F90:XTHERM06:TargetPortMissing", ...
    "Native target-speed output port is missing.");
set_param(ports.Outport(1), ...
    "DataLogging", "on", ...
    "DataLoggingNameMode", "Custom", ...
    "DataLoggingName", "speed_reference");
end

function audit = localStaticAudit(model)
blocks = string(find_system(model, ...
    "SearchDepth", 1, ...
    "FollowLinks", "off", ...
    "LookUnderMasks", "none", ...
    "Type", "Block"));
sig = strings(size(blocks));
for index = 1:numel(blocks)
    sig(index) = lower(regexprep( ...
        localGet(blocks(index), "ReferenceBlock") + " " + ...
        localGet(blocks(index), "SourceBlock") + " " + ...
        localGet(blocks(index), "SourceType") + " " + ...
        localGet(blocks(index), "BlockType"), "\s+", " "));
end

battery = localFind(blocks, sig, ["dc voltage source"]);
motor = localFind(blocks, sig, ["motor & drive"]);
gear = localFind(blocks, sig, ["gear box"]);
tire = localFind(blocks, sig, ["tire (simple)"]);
chassis = localFind(blocks, sig, ["translational elements/mass"]);
speedSensor = localFind(blocks, sig, ["translational motion sensor"]);
driver = localFind(blocks, sig, ["human driver model", "/driver"]);
conduction = localFind(blocks, sig, ["conductive heat"]);
casing = localFind(blocks, sig, ["thermal elements/thermal mass"]);
pump = localFind(blocks, sig, ["flow rate source"]);
pipe = blocks(contains(sig, "pipe (tl)"));
tank = localFind(blocks, sig, ["tank (tl)"]);
ambient = localFind(blocks, sig, ["temperature source"]);
variant = blocks(contains(sig, "variantpmconnector") | ...
    contains(lower(blocks), "variant conn"));

audit = struct;
audit.battery_motor_connected = localConnected(battery, motor);
audit.motor_driveline_connected = localConnectedSet( ...
    [motor, gear, tire, chassis]);
audit.speed_feedback_present = localDriverFeedback(driver);
audit.motor_thermal_to_casing_connected = ...
    localConnectedSet([motor, conduction, casing]);
audit.coolant_loop_connected = numel(pipe) >= 2 && ...
    localConnectedSet([pump, pipe(:)', tank]);
audit.ambient_rejection_connected = ~isempty(ambient) && ...
    any(arrayfun(@(index) localConnected(pipe(index), ambient), ...
        1:numel(pipe)));
audit.cooling_variant_present = false;
for index = 1:numel(variant)
    controls = localGet(variant(index), "VariantControls");
    audit.cooling_variant_present = audit.cooling_variant_present || ...
        any(contains(controls, "Cooling_On"), "all");
end
audit.block_witnesses = struct( ...
    "battery", battery, "motor", motor, "gear", gear, ...
    "tire", tire, "chassis", chassis, ...
    "speed_sensor", speedSensor, "driver", driver, ...
    "conduction", conduction, "casing", casing, ...
    "pump", pump, "pipes", pipe, "tank", tank, ...
    "ambient", ambient, "variants", variant);
audit.core_path_qualified = ...
    audit.battery_motor_connected && ...
    audit.motor_driveline_connected && ...
    audit.speed_feedback_present && ...
    audit.motor_thermal_to_casing_connected && ...
    audit.coolant_loop_connected && ...
    audit.ambient_rejection_connected && ...
    audit.cooling_variant_present;
end

function audit = localCandidateStaticAudit(model)
blocks = string(find_system(model, "FollowLinks", "on", ...
    "LookUnderMasks", "all", "Type", "Block"));
descriptors = strings(size(blocks));
for index = 1:numel(blocks)
    descriptors(index) = lower(localGet(blocks(index), "ReferenceBlock") + " " + ...
        localGet(blocks(index), "SourceType") + " " + ...
        localGet(blocks(index), "BlockType"));
end
has = @(tokens) all(arrayfun(@(token) any(contains(descriptors, token)), ...
    lower(string(tokens))));
audit = struct;
audit.battery_motor_connected = has(["battery", "motor"]);
audit.motor_driveline_connected = has(["motor"]) && ...
    (has(["gear"]) || has(["vehicle body"]) || has(["tire"]));
audit.speed_feedback_present = any(contains(descriptors, "pid")) && ...
    (any(contains(descriptors, "motion sensor")) || ...
     any(contains(descriptors, "speed")));
audit.motor_thermal_to_casing_connected = has(["motor"]) && ...
    (any(contains(descriptors, "thermal mass")) || ...
     any(contains(descriptors, "heat flow")));
audit.coolant_loop_connected = any(contains(descriptors, "pump")) && ...
    (any(contains(descriptors, "pipe")) || ...
     any(contains(descriptors, "thermal liquid")));
audit.ambient_rejection_connected = any(contains(descriptors, "heat exchanger")) || ...
    any(contains(descriptors, "convective heat"));
audit.cooling_variant_present = any(contains(descriptors, "valve")) || ...
    any(contains(descriptors, "controlled mass flow"));
audit.core_path_qualified = all(structfun(@logical, audit));
audit.candidate_structure_scan = true;
end

function pass = localDriverFeedback(driver)
pass = false;
if isempty(driver), return; end
try
    ports = get_param(driver, "PortConnectivity");
    hasInput = false;
    hasOutput = false;
    for index = 1:numel(ports)
        hasInput = hasInput || ~isempty(ports(index).SrcBlock);
        hasOutput = hasOutput || ~isempty(ports(index).DstBlock);
    end
    pass = hasInput && hasOutput;
catch
end
end

function pass = localConnectedSet(blocks)
blocks = blocks(strlength(blocks) > 0);
pass = numel(blocks) >= 2;
if ~pass, return; end
for index = 2:numel(blocks)
    if ~localConnected(blocks(1), blocks(index))
        pass = false;
        return;
    end
end
end

function pass = localConnected(source, target)
pass = false;
if isempty(source) || isempty(target), return; end
sourceHandle = getSimulinkBlockHandle(source, false);
targetHandle = getSimulinkBlockHandle(target, false);
if sourceHandle <= 0 || targetHandle <= 0, return; end
queue = sourceHandle;
visited = zeros(0, 1);
while ~isempty(queue)
    current = queue(1);
    queue(1) = [];
    if current == targetHandle
        pass = true;
        return;
    end
    if any(visited == current), continue; end
    visited(end+1, 1) = current; %#ok<AGROW>
    try
        connectivity = get_param(current, "PortConnectivity");
    catch
        connectivity = struct([]);
    end
    for index = 1:numel(connectivity)
        neighbors = [double(connectivity(index).SrcBlock(:)); ...
            double(connectivity(index).DstBlock(:))];
        neighbors = neighbors(isfinite(neighbors) & neighbors > 0);
        queue = [queue; neighbors]; %#ok<AGROW>
    end
end
end

function block = localFind(blocks, signatures, tokens)
block = "";
searchText = signatures + " " + lower(blocks);
for index = 1:numel(tokens)
    found = find(contains(searchText, lower(tokens(index))), 1);
    if ~isempty(found)
        block = blocks(found);
        return;
    end
end
end

function value = localGet(block, parameter)
value = "";
if strlength(block) == 0, return; end
try
    value = string(get_param(block, parameter));
catch
end
end

function [time, outputs, paths] = localExtractOutputs( ...
        simOut, model, stopTime, scenario, candidateMode)
names = [ ...
    "speed_reference", "vehicle_speed", ...
    "motor_torque_request", "motor_torque_actual", ...
    "motor_temperature", "casing_temperature", ...
    "coolant_inlet_temperature", "coolant_outlet_temperature", ...
    "coolant_mass_flow"];
public = struct;
publicValid = true;
for index = 1:numel(names)
    [series, present] = localPublicSeries(simOut, names(index));
    publicValid = publicValid && present;
    if present, public.(names(index)) = series; end
end
if publicValid
    source = public;
    paths = struct("adapter", "public_timeseries_contract");
else
    assert(~candidateMode, "SimuVerity:F90:XTHERM06:PublicOutputsRequired", ...
        "Candidate model must emit every public Timeseries output.");
    [source, paths] = localNativeReferenceSeries(simOut, model, scenario);
end

time = (0:0.5:stopTime)';
outputs = struct;
for index = 1:numel(names)
    name = names(index);
    outputs.(name) = localInterp(source.(name), time);
end
end

function [series, present] = localPublicSeries(simOut, name)
series = localEmptySeries;
present = false;
try
    value = simuverity_public_output_compatibility( ...
        simOut,name,1,AllowBaseWorkspace=true);
    series = struct("time", double(value.Time(:)), ...
        "values", double(value.Data(:)));
    present = numel(series.time) >= 3;
catch
end
end

function [source, paths] = localNativeReferenceSeries(simOut, model, scenario)
simlog = localGetOutput(simOut, "simlog_" + model);
logsout = localGetOutput(simOut, "logsout");
assert(~isempty(simlog) && ~isempty(logsout), ...
    "SimuVerity:F90:XTHERM06:NativeLogsMissing", ...
    "Native Simscape log or target-speed signal log is missing.");

source = struct;
source.speed_reference = localDatasetSeries(logsout, "speed_reference");
% The unchanged source model represents its native target-speed signal in
% km/h.  The public contract is m/s, so the adapter performs only the unit
% conversion; the target trajectory itself is unchanged.
source.speed_reference.values = source.speed_reference.values / 3.6;
source.vehicle_speed = localNodeSeries(simlog.Chassis.M.v, "m/s");
source.motor_torque_request = localNodeSeries(simlog.Motor.Tr, "N*m");
source.motor_torque_actual = localNodeSeries( ...
    simlog.Motor.torque_elec, "N*m");
source.motor_temperature = localNodeSeries(simlog.Motor.H.T, "degC");
source.casing_temperature = localNodeSeries(simlog.Casing.M.T, "degC");

[source.coolant_inlet_temperature, inletPath] = localCandidateSeries( ...
    simlog, ["Pipe_Casing.A.T", "Pump.B.T"], "degC");
[source.coolant_outlet_temperature, outletPath] = localCandidateSeries( ...
    simlog, ["Pipe_Casing.B.T", "Pipe_Ambient.A.T"], "degC");
[source.coolant_mass_flow, flowPath] = localCandidateSeries( ...
    simlog, ["Pump.mdot_A", "Pipe_Casing.mdot_A"], "kg/s");
if double(scenario.Cooling_Enable) == 0
    % Cooling_On==0 compiles the entire coolant branch out through the
    % source model's physical variant connectors.  For the public output
    % interface, the absent branch is therefore represented explicitly as
    % zero flow at the commanded ambient boundary.  These values receive no
    % thermal-quality credit in the cooling-loss scenario; the scorer uses
    % the physical motor/casing response as the causal failure witness.
    inactiveTime = source.vehicle_speed.time;
    ambient = double(scenario.AmbientTemp_C);
    source.coolant_inlet_temperature = struct( ...
        "time", inactiveTime, ...
        "values", ambient * ones(size(inactiveTime)));
    source.coolant_outlet_temperature = struct( ...
        "time", inactiveTime, ...
        "values", ambient * ones(size(inactiveTime)));
    source.coolant_mass_flow = struct( ...
        "time", inactiveTime, ...
        "values", zeros(size(inactiveTime)));
    inletPath = "inactive_variant:AmbientTemp_C";
    outletPath = "inactive_variant:AmbientTemp_C";
    flowPath = "inactive_variant:Cooling_Enable=0";
end
rows = struct("path", {}, "series", {});
if isempty(source.coolant_inlet_temperature.time) || ...
        isempty(source.coolant_outlet_temperature.time) || ...
        isempty(source.coolant_mass_flow.time)
    rows = localCollectSeries(simlog, "simlog");
end
if isempty(source.coolant_inlet_temperature.time) || ...
        isempty(source.coolant_outlet_temperature.time)
    temperatureRows = localRowsByUnit(rows, "Pipe_Casing", ...
        ["K", "degC"]);
    assert(numel(temperatureRows) >= 2, ...
        "SimuVerity:F90:XTHERM06:CoolantTemperatureMissing", ...
        "Two physical Pipe Casing coolant temperatures were not found.");
    source.coolant_inlet_temperature = localRowSeries( ...
        temperatureRows(1), "degC");
    source.coolant_outlet_temperature = localRowSeries( ...
        temperatureRows(2), "degC");
    inletPath = string(temperatureRows(1).path);
    outletPath = string(temperatureRows(2).path);
end
if isempty(source.coolant_mass_flow.time)
    flowRows = localRowsByUnit(rows, "Pump", ["kg/s"]);
    assert(~isempty(flowRows), "SimuVerity:F90:XTHERM06:CoolantFlowMissing", ...
        "Physical coolant-loop mass flow was not found.");
    source.coolant_mass_flow = localRowSeries(flowRows(1), "kg/s");
    flowPath = string(flowRows(1).path);
end
paths = struct( ...
    "adapter", "native_simscape_log", ...
    "speed_reference", "native_target_kmh_converted_to_mps", ...
    "coolant_inlet", inletPath, ...
    "coolant_outlet", outletPath, ...
    "coolant_flow", flowPath);
end

function rows = localRowsByUnit(rows, token, units)
if isempty(rows), return; end
keep = false(size(rows));
for index = 1:numel(rows)
    if ~contains(lower(string(rows(index).path)), lower(string(token)))
        continue;
    end
    for unit = units
        try
            logSeries = rows(index).series;
            logSeries.values(char(unit));
            keep(index) = true;
            break;
        catch
        end
    end
end
rows = rows(keep);
end

function series = localRowSeries(row, unit)
series = localLogSeries(row.series, unit);
end

function series = localNodeSeries(node, unit)
logSeries = node.series;
series = localLogSeries(logSeries, unit);
end

function series = localLogSeries(logSeries, unit)
timeValues = logSeries.time;
values = logSeries.values(char(unit));
series = struct("time", double(timeValues(:)), ...
    "values", squeeze(double(values)));
end

function [series, path] = localCandidateSeries(root, locators, unit)
series = localEmptySeries;
path = "";
for locator = locators
    try
        node = root;
        for token = split(locator, ".")'
            node = node.(char(token));
        end
        series = localNodeSeries(node, unit);
        if ~isempty(series.time)
            path = "simlog." + locator;
            return;
        end
    catch
    end
end
end

function series = localDatasetSeries(dataset, name)
element = dataset.get(name);
assert(~isempty(element), "SimuVerity:F90:XTHERM06:LoggedSignalMissing", ...
    "Required logged signal %s is missing.", name);
values = element.Values;
series = struct("time", double(values.Time(:)), ...
    "values", squeeze(double(values.Data)));
end

function rows = localCollectSeries(node, path)
rows = struct("path", {}, "series", {});
try
    logSeries = node.series;
    rows(end+1) = struct( ... %#ok<AGROW>
        "path", char(path), ...
        "series", logSeries);
catch
end
try
    ids = cellstr(node.childIds);
catch
    ids = {};
end
for index = 1:numel(ids)
    child = ids{index};
    rows = [rows localCollectSeries(node.(child), ... %#ok<AGROW>
        path + "." + string(child))];
end
end

function [series, path] = localFindSeries(rows, token, suffixes, unit)
series = localEmptySeries;
path = "";
if isempty(rows), return; end
paths = string({rows.path});
normalized = replace(lower(paths), " ", "_");
token = replace(lower(string(token)), " ", "_");
candidate = contains(normalized, token);
for index = 1:numel(suffixes)
    match = candidate & ~cellfun(@isempty, ...
        regexp(cellstr(normalized), char(lower(suffixes(index))), "once"));
    selected = find(match, 1, "first");
    if ~isempty(selected)
        series = localRowSeries(rows(selected), unit);
        path = string(rows(selected).path);
        return;
    end
end
end

function values = localConvertUnit(values, fromUnit, toUnit)
values = double(values);
from = lower(string(fromUnit));
to = lower(string(toUnit));
if from == to || strlength(from) == 0, return; end
if from == "k" && to == "degc"
    values = values - 273.15;
elseif from == "degc" && to == "k"
    values = values + 273.15;
end
end

function values = localInterp(series, time)
assert(~isempty(series.time) && ~isempty(series.values), ...
    "SimuVerity:F90:XTHERM06:EmptySeries", "Required series is empty.");
sourceTime = double(series.time(:));
sourceValues = squeeze(double(series.values));
if size(sourceValues, 1) ~= numel(sourceTime) && ...
        size(sourceValues, 2) == numel(sourceTime)
    sourceValues = sourceValues';
end
assert(size(sourceValues, 1) == numel(sourceTime), ...
    "SimuVerity:F90:XTHERM06:SeriesShape", ...
    "Series time and values do not align.");
assert(size(sourceValues, 2) == 1, ...
    "SimuVerity:F90:XTHERM06:SeriesChannels", ...
    "Required output must have one channel.");
[sourceTime, uniqueIndex] = unique(sourceTime, "stable");
sourceValues = sourceValues(uniqueIndex, :);
values = interp1(sourceTime, sourceValues, time, "linear", "extrap");
values = double(values(:));
end

function localValidateOutputs(time, outputs, stopTime)
assert(numel(time) >= 1000 && time(1) <= 1e-9 && ...
    time(end) >= stopTime - 1e-6, ...
    "SimuVerity:F90:XTHERM06:TimeCoverage", ...
    "Evidence does not cover the complete maneuver.");
names = string(fieldnames(outputs));
for index = 1:numel(names)
    values = double(outputs.(names(index)));
    assert(numel(values) == numel(time) && all(isfinite(values)), ...
        "SimuVerity:F90:XTHERM06:OutputInvalid", ...
        "Output %s is incomplete or non-finite.", names(index));
end
assert(max(abs(outputs.vehicle_speed)) < 100, ...
    "SimuVerity:F90:XTHERM06:SpeedUnits", ...
    "Vehicle speed is inconsistent with m/s.");
assert(max(outputs.motor_temperature) < 500 && ...
    min(outputs.motor_temperature) > -100, ...
    "SimuVerity:F90:XTHERM06:TemperatureUnits", ...
    "Motor temperature is inconsistent with degC.");
end

function summary = localSummary(time, outputs)
tail = time >= max(time(end) - 60, time(1));
summary = struct( ...
    "speed_rmse_mps", sqrt(mean((outputs.vehicle_speed - ...
        outputs.speed_reference).^2)), ...
    "motor_peak_C", max(outputs.motor_temperature), ...
    "motor_tail_C", mean(outputs.motor_temperature(tail)), ...
    "casing_tail_C", mean(outputs.casing_temperature(tail)), ...
    "coolant_temperature_rise_tail_C", ...
        mean(outputs.coolant_outlet_temperature(tail) - ...
        outputs.coolant_inlet_temperature(tail)), ...
    "coolant_mass_flow_tail_kgps", ...
        mean(abs(outputs.coolant_mass_flow(tail))));
end

function rows = localAttachOutputs(rows, artifacts)
for index = 1:numel(rows)
    if rows(index).valid
        rows(index).time_s = artifacts(index).time_s;
        rows(index).outputs = artifacts(index).outputs;
    else
        rows(index).time_s = [];
        rows(index).outputs = struct;
    end
end
end

function row = localEmptyScenario
row = struct( ...
    "id", "", ...
    "requested_inputs", struct, ...
    "simulation_pass", false, ...
    "valid", false, ...
    "time_start_s", NaN, ...
    "time_end_s", NaN, ...
    "sample_count", 0, ...
    "selected_paths", struct, ...
    "summary", struct, ...
    "error", "", ...
    "time_s", [], ...
    "outputs", struct);
end

function series = localEmptySeries
series = struct("time", [], "values", []);
end

function value = localGetOutput(simOut, name)
value = [];
try
    value = simOut.get(char(name));
catch
end
if isempty(value)
    try
        if evalin("base", "exist('" + name + "','var')")
            value = evalin("base", name);
        end
    catch
    end
end
end

function localCloseModel(model)
try
    if bdIsLoaded(model), close_system(model, 0); end
catch
end
end

function value = localNow
value = string(datetime("now", "TimeZone", "local", ...
    "Format", "yyyy-MM-dd'T'HH:mm:ssXXX"));
end

function out = localError(ME)
out = struct("identifier", string(ME.identifier), ...
    "message", string(ME.message), ...
    "report", string(getReport(ME, "extended", "hyperlinks", "off")));
end

function localWriteJson(path, value)
fid = fopen(path, "w");
assert(fid >= 0, "SimuVerity:F90:XTHERM06:WriteJson", ...
    "Could not open JSON output: %s", path);
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fwrite(fid, jsonencode(value, "PrettyPrint", false), "char");
end
