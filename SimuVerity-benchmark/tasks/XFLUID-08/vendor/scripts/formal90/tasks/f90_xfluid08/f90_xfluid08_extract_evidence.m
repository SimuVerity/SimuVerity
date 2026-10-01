function evidence = f90_xfluid08_extract_evidence(modelPath, outputDir, officialScenarios, evaluatorAssetRoot)
%F90_XFLUID08_EXTRACT_EVIDENCE Extract score-free evidence in one session.
%
% The R2025a example is never saved. The adapter only selects one of the
% example's existing Signal Editor profiles, exposes existing initial fuel
% volumes, disables log truncation in memory, and reads native Simscape and
% signal-logging evidence. All official scenarios run in this MATLAB process.

arguments
    modelPath (1,1) string
    outputDir (1,1) string
    officialScenarios (1,1) string
    evaluatorAssetRoot (1,1) string
end
outDir = outputDir;
sourceRoot = evaluatorAssetRoot;
parameterScript = fullfile(sourceRoot, ...
    "AircraftFuelSupplySystemWithThreeTanksParameters.m");
profileFile = fullfile(sourceRoot, ...
    "AircraftFuelSupplySystemWithThreeTanks.mat");
assert(isfile(officialScenarios), "SimuVerity:F90:XFLUID08:OfficialScenarios", ...
    "Official scenarios are missing.");
assert(isfolder(sourceRoot), "SimuVerity:F90:XFLUID08:ReferenceAssetRoot", ...
    "Evaluator asset root is missing.");
official = jsondecode(fileread(officialScenarios));
expectedPresence = lower(strtrim(string("present")));
assert(strcmpi(localFilePresenceFile(modelPath), expectedPresence), ...
    "SimuVerity:F90:XFLUID08:ReferenceIdentity", ...
    "Reference file presence differs from the task binding.");

generationRunId = string(getenv("SIMUVERITY_GENERATION_RUN_ID"));
assert(strlength(generationRunId) > 0, "SimuVerity:F90:XFLUID08:GenerationRunId", ...
    "SIMUVERITY_GENERATION_RUN_ID is required.");
assert(isfile(modelPath) && isfile(parameterScript) && isfile(profileFile), ...
    "SimuVerity:F90:XFLUID08:ReferenceMissing", ...
    "The unchanged R2025a reference is incomplete.");

assert(~isfolder(outDir), "SimuVerity:F90:XFLUID08:OutputReuse", ...
    "Evidence output already exists for GenerationRunId %s.", generationRunId);
mkdir(outDir);

localConfigureIsolation;
set(groot, "defaultFigureVisible", "off");
oldDir = pwd;
dirCleanup = onCleanup(@() cd(oldDir)); %#ok<NASGU>
cd(sourceRoot);

evidence = struct;
evidence.schema = "simuverity.f90-xfluid08-evidence.v1";
evidence.task_id = "F90-XFLUID-08";
evidence.source = struct( ...
    "owner", "MathWorks", ...
    "release", "R2025a", ...
    "example", "Aircraft Fuel Supply System with Three Tanks", ...
    "model", "AircraftFuelSupplySystemWithThreeTanks.slx", ...
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
    run(parameterScript);
    modelHandle = load_system(modelPath);
    model = string(get_param(modelHandle, "Name"));
    modelCleanup = onCleanup(@() localCloseModel(model)); %#ok<NASGU>
    evidence.load_pass = true;

    set_param(model, ...
        "StopTime", string(official.simulation.stop_time_s), ...
        "ReturnWorkspaceOutputs", "on", ...
        "SignalLogging", "on", ...
        "SignalLoggingSaveFormat", "Dataset", ...
        "LimitDataPoints", "off", ...
        "SimscapeLogType", "all", ...
        "SimscapeLogLimitData", "off", ...
        "SimscapeLogOpenViewer", "off", ...
        "SimscapeLogToSDI", "off");
    localApplyScenario(model, official.scenarios(1), parameterScript);

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
            localApplyScenario(model, scenario, parameterScript);
            simOut = sim(model, ...
                "ReturnWorkspaceOutputs", "on", ...
                "StopTime", string(official.simulation.stop_time_s));
            scenarioWall(index) = toc(started);
            [simlog, logsout] = localGetNativeLogs(simOut);
            [signals, metrics, locators] = localExtractNativeEvidence( ...
                simlog, logsout, scenario);
            rows(index).simulation_pass = true;
            rows(index).sample_count = numel(signals.time_s);
            rows(index).end_time_s = signals.time_s(end);
            rows(index).time_coverage_pass = ...
                signals.time_s(1) <= 0.05 && ...
                signals.time_s(end) >= ...
                    double(official.simulation.stop_time_s) - 0.5;
            rows(index).required_evidence_pass = ...
                rows(index).sample_count >= 50 && ...
                metrics.finite_fraction >= 0.999999;
            rows(index).valid = rows(index).time_coverage_pass && ...
                rows(index).required_evidence_pass;
            rows(index).metrics = metrics;
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
fprintf("F90_XFLUID08_EVIDENCE load=%d update=%d compile=%d valid=%d/%d path=%s\n", ...
    evidence.load_pass, evidence.update_pass, evidence.compile_pass, ...
    localValidCount(evidence.scenarios), numel(evidence.scenarios), ...
    evidencePath);
end

function localApplyScenario(model, scenario, parameterScript)
run(parameterScript);
assignin("base", "vol_init_wing", ...
    double(scenario.wing_initial_volume_m3));
assignin("base", "vol_init_center", ...
    double(scenario.center_initial_volume_m3));
block = model + "/Flight Scenarios";
set_param(block, "ActiveScenario", string(scenario.native_profile));
end

function [simlog, logsout] = localGetNativeLogs(simOut)
simlog = [];
logsout = [];
names = string(simOut.who);
simlogNames = [ ...
    "simlog_AircraftFuelSupplySystemWithThreeTanks", ...
    "simlog"];
logNames = [ ...
    "logsout_AircraftFuelSupplySystemWithThreeTanks", ...
    "logsout"];
for name = simlogNames
    if any(names == name)
        simlog = simOut.get(name);
        break;
    end
end
for name = logNames
    if any(names == name)
        logsout = simOut.get(name);
        break;
    end
end
if isempty(simlog)
    for name = simlogNames
        try
            simlog = evalin("base", name);
            if ~isempty(simlog), break; end
        catch
        end
    end
end
if isempty(logsout)
    for name = logNames
        try
            logsout = evalin("base", name);
            if ~isempty(logsout), break; end
        catch
        end
    end
end
assert(~isempty(simlog), "SimuVerity:F90:XFLUID08:SimlogMissing", ...
    "Native Simscape log was not returned.");
assert(~isempty(logsout) && numElements(logsout) >= 4, ...
    "SimuVerity:F90:XFLUID08:LogsoutMissing", ...
    "Native pump-command signal log was not returned.");
end

function [signals, metrics, locators] = localExtractNativeEvidence( ...
    simlog, logsout, scenario)
pumpPaths = [ ...
    "Tank_System_Left_Wing.Pump_1", ...
    "Tank_System_Left_Wing.Pump_2", ...
    "Tank_System_Right_Wing.Pump_1", ...
    "Tank_System_Right_Wing.Pump_2"];
commandNames = ["LWP1", "LWP2", "RWP1", "RWP2"];

speedSeries = repmat(struct("time", [], "data", [], "locator", ""), 4, 1);
for index = 1:4
    speedSeries(index) = localNodeSeries(simlog, ...
        pumpPaths(index) + ".R.w", ["rpm"]);
end
t = speedSeries(1).time;
assert(numel(t) >= 50, "SimuVerity:F90:XFLUID08:Samples", ...
    "Native physical log has too few samples.");

commandRpm = zeros(numel(t), 4);
actualRpm = zeros(numel(t), 4);
flowKgS = zeros(numel(t), 4);
pressureRiseMpa = zeros(numel(t), 4);
shaftPowerW = zeros(numel(t), 4);
hydraulicPowerW = zeros(numel(t), 4);
locators = struct;
locators.pump = repmat(struct( ...
    "speed", "", "flow", "", "pressure_rise", "", ...
    "mechanical_power", "", "hydraulic_power", ""), 4, 1);

for index = 1:4
    command = localLoggedSeries(logsout, commandNames(index));
    commandRpm(:, index) = localInterpPrevious(command, t) * 60;
    actualRpm(:, index) = localInterpLinear(speedSeries(index), t);

    flow = localNodeSeries(simlog, ...
        pumpPaths(index) + ".mdot_A", ["kg/s"]);
    pressure = localNodeSeries(simlog, ...
        pumpPaths(index) + ".p_diff", ["MPa"]);
    mechanicalPower = localNodeSeries(simlog, ...
        pumpPaths(index) + ".mechanical_power", ["W"]);
    hydraulicPower = localNodeSeries(simlog, ...
        pumpPaths(index) + ".hydraulic_power", ["W"]);

    flowKgS(:, index) = localInterpLinear(flow, t);
    pressureRiseMpa(:, index) = abs(localInterpLinear(pressure, t));
    shaftPowerW(:, index) = abs(localInterpLinear(mechanicalPower, t));
    hydraulicPowerW(:, index) = abs(localInterpLinear(hydraulicPower, t));

    locators.pump(index).speed = speedSeries(index).locator;
    locators.pump(index).flow = flow.locator;
    locators.pump(index).pressure_rise = pressure.locator;
    locators.pump(index).mechanical_power = mechanicalPower.locator;
    locators.pump(index).hydraulic_power = hydraulicPower.locator;
end

leftVolume = localNodeSeries(simlog, ...
    "Tank_System_Left_Wing.Fuel_Tank.V_out", ["m^3"]);
rightVolume = localNodeSeries(simlog, ...
    "Tank_System_Right_Wing.Fuel_Tank.V_out", ["m^3"]);
centerVolume = localNodeSeries(simlog, ...
    "Tank_System_Center.Central_Tank.V_out", ["m^3"]);
leftV = localInterpLinear(leftVolume, t);
rightV = localInterpLinear(rightVolume, t);
centerV = localInterpLinear(centerVolume, t);
cgOffset = 100 * (leftV - rightV) ./ ...
    max(leftV + rightV + centerV, eps);

engineFlow = localNodeSeries(simlog, ...
    "Engine.Engine_Pump.mdot_A", ["kg/s"]);
enginePressure = localNodeSeries(simlog, ...
    "Engine.Engine_Pump.p_diff", ["MPa"]);
engineFeedKgS = localInterpLinear(engineFlow, t);
enginePressureRiseMpa = abs(localInterpLinear(enginePressure, t));

locators.tank_volumes = [ ...
    leftVolume.locator, rightVolume.locator, centerVolume.locator];
locators.engine_feed = struct( ...
    "flow", engineFlow.locator, ...
    "pressure_rise", enginePressure.locator);

signals = struct;
signals.time_s = t;
signals.pump_speed_state = [ ...
    commandRpm(:,1), actualRpm(:,1), ...
    commandRpm(:,2), actualRpm(:,2), ...
    commandRpm(:,3), actualRpm(:,3), ...
    commandRpm(:,4), actualRpm(:,4)];
signals.tank_fuel_state = [leftV, rightV, centerV, cgOffset];
signals.transfer_hydraulics = [flowKgS, pressureRiseMpa];
signals.engine_feed_state = [engineFeedKgS, enginePressureRiseMpa];
signals.pump_power_state = [shaftPowerW, hydraulicPowerW];

late = t >= max(0.9 * t(end), t(end) - 300);
assert(nnz(late) >= 10, "SimuVerity:F90:XFLUID08:LateWindow", ...
    "Native log has too few late-window samples.");

trackingNrmse = zeros(1,4);
trackingCorrelation = zeros(1,4);
commandResponseRange = zeros(1,4);
reverseFraction = zeros(1,4);
efficiency = zeros(1,4);
for index = 1:4
    active = commandRpm(:,index) >= ...
        max(300, 0.1 * max(commandRpm(:,index)));
    if nnz(active) < 10
        active = true(size(t));
    end
    trackingNrmse(index) = sqrt(mean( ...
        (actualRpm(active,index)-commandRpm(active,index)).^2)) / ...
        max(sqrt(mean(commandRpm(active,index).^2)), 300);
    trackingCorrelation(index) = localAbsCorrelation( ...
        commandRpm(:,index), actualRpm(:,index));
    commandResponseRange(index) = max(actualRpm(:,index)) - ...
        min(actualRpm(:,index));
    forwardSign = sign(median(flowKgS(active,index)));
    if forwardSign == 0, forwardSign = 1; end
    significant = abs(flowKgS(:,index)) >= ...
        max(0.01 * max(abs(flowKgS(:,index))), 1e-4);
    reverseFraction(index) = mean( ...
        forwardSign * flowKgS(significant,index) < 0);
    validPower = active & shaftPowerW(:,index) > 1;
    if nnz(validPower) >= 5
        efficiency(index) = median( ...
            hydraulicPowerW(validPower,index) ./ ...
            shaftPowerW(validPower,index));
    else
        efficiency(index) = 0;
    end
end

feedAbs = abs(engineFeedKgS);
feedReference = median(feedAbs(late));
feedAvailability = mean(feedAbs >= max(0.5 * feedReference, 1e-4));
feedDropout = 1 - feedAvailability;
totalVolume = leftV + rightV + centerV;
observedLossM3 = totalVolume(1) - totalVolume(end);
integratedEngineLossM3 = trapz(t, feedAbs / 920.027);
inventoryResidual = abs(observedLossM3 - integratedEngineLossM3) / ...
    max(abs(integratedEngineLossM3), 0.05);
recovery = localRecoveryMetrics(t, commandRpm, actualRpm);

allValues = [signals.pump_speed_state, signals.tank_fuel_state, ...
    signals.transfer_hydraulics, signals.engine_feed_state, ...
    signals.pump_power_state];
metrics = struct( ...
    "native_profile", string(scenario.native_profile), ...
    "requested_wing_initial_volume_m3", ...
        double(scenario.wing_initial_volume_m3), ...
    "requested_center_initial_volume_m3", ...
        double(scenario.center_initial_volume_m3), ...
    "command_min_rpm", min(commandRpm, [], 1), ...
    "command_max_rpm", max(commandRpm, [], 1), ...
    "command_transition_count", sum(abs(diff(commandRpm)) > 30, 1), ...
    "pump_tracking_nrmse", trackingNrmse, ...
    "pump_command_speed_abs_correlation", trackingCorrelation, ...
    "pump_measured_speed_range_rpm", commandResponseRange, ...
    "pump_reverse_flow_fraction", reverseFraction, ...
    "pump_pressure_rise_mpa_late", ...
        median(pressureRiseMpa(late,:), 1), ...
    "pump_mass_flow_kg_s_late", median(abs(flowKgS(late,:)), 1), ...
    "pump_shaft_power_w_late", median(shaftPowerW(late,:), 1), ...
    "pump_hydraulic_power_w_late", ...
        median(hydraulicPowerW(late,:), 1), ...
    "pump_efficiency_late", efficiency, ...
    "left_volume_start_m3", leftV(1), ...
    "right_volume_start_m3", rightV(1), ...
    "center_volume_start_m3", centerV(1), ...
    "left_volume_end_m3", leftV(end), ...
    "right_volume_end_m3", rightV(end), ...
    "center_volume_end_m3", centerV(end), ...
    "minimum_tank_volume_m3", min([leftV; rightV; centerV]), ...
    "maximum_center_volume_m3", max(centerV), ...
    "maximum_absolute_cg_offset_percent", max(abs(cgOffset)), ...
    "engine_feed_mass_flow_kg_s_late", feedReference, ...
    "engine_feed_pressure_rise_mpa_late", ...
        median(enginePressureRiseMpa(late)), ...
    "engine_feed_availability_fraction", feedAvailability, ...
    "engine_feed_dropout_fraction", feedDropout, ...
    "total_fuel_volume_loss_m3", observedLossM3, ...
    "integrated_engine_delivery_m3", integratedEngineLossM3, ...
    "inventory_balance_relative_residual", inventoryResidual, ...
    "maximum_pump_restore_time_s", recovery.maximum_restore_time_s, ...
    "maximum_pump_shutdown_time_s", recovery.maximum_shutdown_time_s, ...
    "restore_event_count", recovery.restore_event_count, ...
    "shutdown_event_count", recovery.shutdown_event_count, ...
    "late_tank_volume_relative_drift", ...
        localRelativeDrift(t(late), totalVolume(late)), ...
    "finite_fraction", mean(isfinite(allValues), "all"));
end

function result = localRecoveryMetrics(t, command, actual)
restoreTimes = [];
shutdownTimes = [];
for column = 1:size(command,2)
    cmd = command(:,column);
    act = actual(:,column);
    threshold = max(300, 0.15 * max(cmd));
    changes = find(abs(diff(cmd)) > threshold);
    for event = changes(:)'
        after = event + 1;
        target = cmd(after);
        if target > cmd(event) + threshold
            tolerance = max(0.08 * abs(target), 120);
            settled = find(abs(act(after:end) - target) <= tolerance, 1);
            if ~isempty(settled)
                restoreTimes(end+1) = ...
                    t(after + settled - 1) - t(after); %#ok<AGROW>
            end
        elseif target < cmd(event) - threshold
            tolerance = max(0.08 * max(abs(cmd(event)),1), 120);
            settled = find(abs(act(after:end) - target) <= tolerance, 1);
            if ~isempty(settled)
                shutdownTimes(end+1) = ...
                    t(after + settled - 1) - t(after); %#ok<AGROW>
            end
        end
    end
end
result = struct( ...
    "restore_event_count", numel(restoreTimes), ...
    "shutdown_event_count", numel(shutdownTimes), ...
    "maximum_restore_time_s", localMaxOrMinusOne(restoreTimes), ...
    "maximum_shutdown_time_s", localMaxOrMinusOne(shutdownTimes));
end

function value = localMaxOrMinusOne(values)
if isempty(values)
    value = -1;
else
    value = max(values);
end
end

function value = localRelativeDrift(t, x)
if numel(t) < 3 || max(t) <= min(t)
    value = 1;
    return;
end
coefficient = polyfit(t(:), x(:), 1);
value = abs(coefficient(1)) * (max(t)-min(t)) / ...
    max(abs(mean(x)), 1e-6);
end

function value = localAbsCorrelation(a, b)
a = double(a(:));
b = double(b(:));
valid = isfinite(a) & isfinite(b);
if nnz(valid) < 3 || std(a(valid)) < eps || std(b(valid)) < eps
    value = 0;
    return;
end
matrix = corrcoef(a(valid), b(valid));
value = abs(matrix(1,2));
end

function series = localLoggedSeries(logsout, name)
element = logsout.getElement(char(name));
assert(~isempty(element) && isa(element.Values, "timeseries"), ...
    "SimuVerity:F90:XFLUID08:CommandLog", ...
    "Command log %s is missing or not a timeseries.", name);
series = struct( ...
    "time", double(element.Values.Time(:)), ...
    "data", double(squeeze(element.Values.Data)), ...
    "locator", string(name));
series.data = series.data(:);
end

function series = localNodeSeries(root, candidates, units)
candidates = string(candidates);
units = string(units);
lastError = [];
for candidate = candidates
    try
        node = root;
        tokens = split(candidate, ".");
        for token = tokens'
            node = node.(char(token));
        end
        for unit = units
            try
                logSeries = node.series;
                data = double(logSeries.values(char(unit)));
                timeValues = logSeries.time;
                series = struct( ...
                    "time", double(timeValues(:)), ...
                    "data", double(squeeze(data)), ...
                    "locator", candidate);
                if size(series.data,2) > 1
                    series.data = series.data(:,1);
                end
                series.data = series.data(:);
                return;
            catch ME
                lastError = ME;
            end
        end
    catch ME
        lastError = ME;
    end
end
if isempty(lastError)
    error("SimuVerity:F90:XFLUID08:Locator", ...
        "No locator candidate was provided.");
end
error("SimuVerity:F90:XFLUID08:Locator", ...
    "Unable to read any native locator [%s]: %s", ...
    strjoin(candidates, ", "), lastError.message);
end

function values = localInterpLinear(series, t)
sourceT = double(series.time(:));
sourceY = double(series.data(:));
[sourceT, uniqueIndex] = unique(sourceT, "last");
sourceY = sourceY(uniqueIndex);
if numel(sourceT) == 1
    values = repmat(sourceY, numel(t), 1);
else
    values = interp1(sourceT, sourceY, t, "linear", "extrap");
end
values = double(values(:));
end

function values = localInterpPrevious(series, t)
sourceT = double(series.time(:));
sourceY = double(series.data(:));
[sourceT, uniqueIndex] = unique(sourceT, "last");
sourceY = sourceY(uniqueIndex);
if numel(sourceT) == 1
    values = repmat(sourceY, numel(t), 1);
else
    values = interp1(sourceT, sourceY, t, "previous", "extrap");
end
values = double(values(:));
end

function audit = localStaticAudit(model)
blocks = string(find_system(model, ...
    "LookUnderMasks", "all", "FollowLinks", "on", "Type", "Block"));
referenceBlocks = strings(size(blocks));
blockTypes = strings(size(blocks));
for index = 1:numel(blocks)
    try
        referenceBlocks(index) = string(get_param(blocks(index), ...
            "ReferenceBlock"));
    catch
    end
    try
        blockTypes(index) = string(get_param(blocks(index), "BlockType"));
    catch
    end
end
library = lower(referenceBlocks);
names = lower(blocks);
lines = find_system(model, "FindAll", "on", "Type", "line");
audit = struct;
audit.block_count = numel(blocks);
audit.line_count = numel(lines);
audit.centrifugal_pump_count = ...
    sum(contains(library, "centrifugal pump"));
audit.tank_count = sum(contains(library, "/tank (tl)"));
audit.check_valve_count = sum(contains(library, "check valve"));
audit.directional_valve_count = ...
    sum(contains(library, "2-way directional"));
audit.motion_sensor_count = max( ...
    sum(contains(library, "rotational motion sensor")), ...
    sum(contains(names, "rotational motion sensor")));
audit.torque_source_count = ...
    sum(contains(library, "ideal torque source"));
audit.integrator_count = sum(blockTypes == "Integrator");
audit.feedback_sum_count = sum(blockTypes == "Sum");
audit.signal_editor_count = sum(contains(library, "signal editor"));
audit.left_wing_signature = any( ...
    contains(names, "tank system") & contains(names, "left wing"));
audit.right_wing_signature = any( ...
    contains(names, "tank system") & contains(names, "right wing"));
audit.center_tank_signature = any(contains(names, "tank system center"));
audit.engine_signature = any(contains(names, "/engine/engine pump"));
audit.redundant_transfer_signature = ...
    audit.centrifugal_pump_count >= 5 && ...
    audit.check_valve_count >= 4 && ...
    audit.left_wing_signature && audit.right_wing_signature;
audit.closed_loop_pump_speed_signature = ...
    audit.torque_source_count >= 4 && ...
    audit.integrator_count >= 4 && ...
    audit.feedback_sum_count >= 4;
audit.causal_fuel_path_signature = ...
    audit.redundant_transfer_signature && ...
    audit.tank_count >= 3 && ...
    audit.directional_valve_count >= 3 && ...
    audit.center_tank_signature && audit.engine_signature && ...
    audit.line_count >= 30;
audit.required_products = [ ...
    "Simulink", "Simscape", "Simscape Fluids"];
products = ver;
installed = string({products.Name});
audit.required_products_available = all(ismember( ...
    audit.required_products, installed));
end

function localConfigureIsolation
cache = string(getenv("SIMULINK_CACHE_FOLDER"));
codegen = string(getenv("SIMULINK_CODEGEN_FOLDER"));
assert(strlength(cache) > 0 && strlength(codegen) > 0, ...
    "SimuVerity:F90:XFLUID08:Isolation", ...
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
assert(fid >= 0, "SimuVerity:F90:XFLUID08:Write", ...
    "Cannot write %s.", path);
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
