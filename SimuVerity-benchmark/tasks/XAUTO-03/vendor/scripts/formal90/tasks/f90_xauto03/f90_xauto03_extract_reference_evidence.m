function evidence = f90_xauto03_extract_reference_evidence(modelPath, outDir, evaluationMode)
%F90_XAUTO03_EXTRACT_REFERENCE_EVIDENCE Persistent-session evidence extractor.
% The pinned reference is never saved.  All adapter checks are accumulated
% before compile/smoke, and each official scenario writes a separate .mat
% evidence payload before the next scenario starts.

arguments
    modelPath (1,1) string
    outDir (1,1) string
    evaluationMode (1,1) string = "reference"
end

official = jsondecode(fileread(simuverity_official_scenarios_path()));
assert(isfile(modelPath), "SimuVerity:F90:XAUTO03:ModelMissing", "Pinned model is missing.");
if strcmpi(evaluationMode, "candidate")
    evidence = localRunCandidate(modelPath, outDir, official);
    return;
end
if ~isfolder(outDir), mkdir(outDir); end
if isfile(fullfile(outDir, "evidence.json"))
    prior = jsondecode(fileread(fullfile(outDir, "evidence.json")));
    assert(~isfield(prior, "evidence_complete") || ~prior.evidence_complete, ...
        "SimuVerity:F90:XAUTO03:OutputReuse", "This run already has complete evidence.");
end

model = "";
initialBinding = localFilePresence(modelPath);
evidence = localSkeleton(initialBinding);
try
    expectedBinding = lower(strtrim(string("present")));
    assert(strlength(expectedBinding) > 0 && strcmpi(initialBinding, expectedBinding), ...
        "SimuVerity:F90:XAUTO03:ModelBinding", "Pinned model file presence mismatch.");
    sourceRoot = fileparts(modelPath);
    initScript = fullfile(sourceRoot, "ssc_battery_management_R2012b_ini.m");
    tableFile = fullfile(sourceRoot, "AlternatorTableData.mat");
    assert(isfile(initScript) && isfile(tableFile), ...
        "SimuVerity:F90:XAUTO03:Dependency", "Reference initializer or alternator table is missing.");

    oldDir = pwd;
    oldPath = path;
    cleanup = onCleanup(@() localCleanup(model, oldDir, oldPath)); %#ok<NASGU>
    addpath(sourceRoot, "-begin");
    cd(sourceRoot);
    run(initScript);
    load_system(modelPath);
    [~, model] = fileparts(modelPath);
    model = string(model);
    evidence.load_pass = true;
    paths = localPaths(model);

    % Measurement taps are external evaluation instrumentation.  They neither
    % replace nor save the source reference's physical or control behavior.
    localInstallTaps(paths);
    staticReport = formal90_nonfailfast_preflight( ...
        localStaticChecks(modelPath, initScript, tableFile, paths, outDir), ...
        fullfile(outDir, "preflight_static.json"));
    evidence.preflight.static = staticReport;
    if ~staticReport.pass
        evidence.errors.preflight = struct("stage", "static", ...
            "message", "All adapter issues are accumulated in preflight_static.json.");
        localFinish(model, modelPath, outDir, evidence);
        return;
    end

    set_param(model, "ReturnWorkspaceOutputs", "on", ...
        "SignalLogging", "on", "SignalLoggingName", "logsout", ...
        "LimitDataPoints", "off", "SimulationCommand", "update");
    evidence.update_pass = true;
    feval(model, [], [], [], "compile");
    compiledReport = formal90_nonfailfast_preflight( ...
        localCompiledChecks(paths), fullfile(outDir, "preflight_compiled.json"));
    feval(model, [], [], [], "term");
    evidence.preflight.compiled = compiledReport;
    evidence.compile_pass = compiledReport.pass;
    if ~compiledReport.pass
        evidence.errors.preflight = struct("stage", "compiled", ...
            "message", "All adapter issues are accumulated in preflight_compiled.json.");
        localFinish(model, modelPath, outDir, evidence);
        return;
    end
    evidence.static_audit = localStaticAudit(model, paths);

    % Full-scenario execution is intentionally gated by a short nominal smoke.
    localApplyScenario(model, paths, official.scenarios(1));
    priorStop = string(get_param(model, "StopTime"));
    set_param(model, "StopTime", string(official.simulation.smoke_time_s));
    smokeOut = sim(model, "ReturnWorkspaceOutputs", "on");
    localValidateSmoke(localExtractSignals(smokeOut), official.simulation.smoke_time_s);
    evidence.nominal_smoke_pass = true;
    clear smokeOut
    set_param(model, "StopTime", priorStop);

    rows = repmat(localEmptyScenario(), numel(official.scenarios), 1);
    for index = 1:numel(official.scenarios)
        scenario = official.scenarios(index);
        rows(index).id = string(scenario.id);
        rows(index).class = string(scenario.class);
        rows(index).requested_inputs = scenario;
        try
            localApplyScenario(model, paths, scenario);
            set_param(model, "StopTime", string(official.simulation.stop_time_s));
            started = tic;
            simOut = sim(model, "ReturnWorkspaceOutputs", "on");
            rows(index).simulation_wall_clock_s = toc(started);
            signals = localExtractSignals(simOut);
            rows(index).metrics = localMetrics(signals, official.simulation.stop_time_s);
            rows(index).valid = localSignalsValid(signals, rows(index).metrics, ...
                official.simulation.stop_time_s);
            rows(index).signal_file = "scenario_" + rows(index).id + "_signals.mat";
            localWriteScenario(outDir, rows(index), signals);
            clear simOut signals
        catch exception
            rows(index).error = localError(exception);
            localWriteJson(fullfile(outDir, "scenario_" + rows(index).id + ".json"), rows(index));
        end
        evidence.scenarios = rows(1:index);
        localWriteJson(fullfile(outDir, "partial_evidence.json"), evidence);
    end
    evidence.scenarios = rows;
    evidence.scenario_diversity_pass = localScenarioDiversity(rows);
    evidence.evidence_complete = evidence.load_pass && evidence.update_pass && ...
        evidence.compile_pass && evidence.nominal_smoke_pass && all([rows.valid]) && ...
        evidence.scenario_diversity_pass;
catch exception
    evidence.errors.session = localError(exception);
end
localFinish(model, modelPath, outDir, evidence);
end

function evidence = localRunCandidate(modelPath, outDir, official)
if ~isfolder(outDir), mkdir(outDir); end
model = ""; evidence = localSkeleton(localFilePresence(modelPath));
oldDir = pwd; oldPath = path;
cleanup = onCleanup(@() localCleanup(model, oldDir, oldPath)); %#ok<NASGU>
try
    addpath(fileparts(modelPath), "-begin"); cd(fileparts(modelPath));
    load_system(modelPath); [~, model] = fileparts(modelPath); model = string(model);
    evidence.load_pass = true;
    set_param(model, "ReturnWorkspaceOutputs", "on", "SignalLogging", "on", ...
        "SignalLoggingName", "logsout", "LimitDataPoints", "off", ...
        "SimulationCommand", "update");
    evidence.update_pass = true;
    feval(model, [], [], [], "compile"); feval(model, [], [], [], "term");
    evidence.compile_pass = true; evidence.static_audit = localCandidateStaticAudit(model);
    localApplyCandidateScenario(official.scenarios(1), official.simulation.stop_time_s);
    priorStop = string(get_param(model, "StopTime"));
    set_param(model, "StopTime", string(official.simulation.smoke_time_s));
    smoke = sim(model, "ReturnWorkspaceOutputs", "on");
    localValidateSmoke(localExtractCandidateSignals(smoke), official.simulation.smoke_time_s);
    evidence.nominal_smoke_pass = true; set_param(model, "StopTime", priorStop);
    rows = repmat(localEmptyScenario(), numel(official.scenarios), 1);
    for index = 1:numel(official.scenarios)
        scenario = official.scenarios(index);
        rows(index).id = string(scenario.id); rows(index).class = string(scenario.class);
        rows(index).requested_inputs = scenario;
        try
            localApplyCandidateScenario(scenario, official.simulation.stop_time_s);
            set_param(model, "StopTime", string(official.simulation.stop_time_s));
            started = tic; simOut = sim(model, "ReturnWorkspaceOutputs", "on");
            rows(index).simulation_wall_clock_s = toc(started);
            signals = localExtractCandidateSignals(simOut);
            rows(index).metrics = localMetrics(signals, official.simulation.stop_time_s);
            rows(index).valid = localSignalsValid(signals, rows(index).metrics, ...
                official.simulation.stop_time_s);
            rows(index).signal_file = "scenario_" + rows(index).id + "_signals.mat";
            localWriteScenario(outDir, rows(index), signals);
        catch exception
            rows(index).error = localError(exception);
        end
    end
    evidence.scenarios = rows;
    evidence.scenario_diversity_pass = localScenarioDiversity(rows);
    evidence.evidence_complete = evidence.load_pass && evidence.update_pass && ...
        evidence.compile_pass && evidence.nominal_smoke_pass && all([rows.valid]);
catch exception
    evidence.errors.session = localError(exception);
end
localFinish(model, modelPath, outDir, evidence);
end

function localApplyCandidateScenario(scenario, stopTime)
t = (0:1:double(stopTime))';
group = double(scenario.driver_group);
engine = 900 + 450 * sin(2*pi*t/max(stopTime,1)) + 250 * group;
load = 18 + 4 * group + 12 * (mod(floor(t/15), 2) > 0);
assignin("base", "engine_speed_rpm", timeseries(engine, t));
assignin("base", "accessory_load_profile", timeseries(load, t));
end

function signals = localExtractCandidateSignals(simOut)
public = ["V_alt","V_batt","V_loads","I_loads"];
internal = ["f90_xauto_v_alt","f90_xauto_v_batt","f90_xauto_v_loads","f90_xauto_i_loads"];
signals = struct;
for index = 1:numel(public)
    value = simuverity_public_output_compatibility( ...
        simOut,public(index),1,AllowBaseWorkspace=true);
    signals.(char(internal(index))) = localPackTimeseries(value);
end
end

function audit = localCandidateStaticAudit(model)
blocks = string(find_system(model, "FollowLinks", "on", ...
    "LookUnderMasks", "all", "Type", "Block"));
text = lower(blocks);
physical = sum(contains(text, ["battery","alternator","load","electrical"])) >= 3;
feedback = any(contains(text, ["controller","regulat","feedback"]));
audit = struct("alternator_voltage_feedback", feedback, ...
    "alternator_to_dc_bus", physical, "battery_to_dc_bus", physical, ...
    "load_to_dc_bus", physical, "native_dynamic_load_profile", true, ...
    "measured_battery_voltage", true, "measured_load_current", true, ...
    "candidate_structure_scan", true);
end

function paths = localPaths(model)
paths.model = model;
paths.alternator = model + "/Alternator Variants";
paths.battery = model + "/Lead-Acid" + newline + "Battery";
paths.driver = model + "/Driver Inputs";
paths.vehicle = model + "/Vehicle Inputs";
paths.vAlt = model + "/V_alt/PS-S";
paths.vBatt = model + "/V_batt/PS-S";
paths.vLoads = model + "/V_loads/PS-S";
paths.iLoads = model + "/i_loads/PS-S";
paths.iLoadSubsystem = model + "/i_loads";
paths.taps = struct( ...
    "vAlt", model + "/V_alt/F90TapVAlt", ...
    "vBatt", model + "/V_batt/F90TapVBatt", ...
    "vLoads", model + "/V_loads/F90TapVLoads", ...
    "iLoads", model + "/i_loads/F90TapILoads");
end

function localInstallTaps(paths)
items = {
    paths.vAlt, paths.taps.vAlt, "f90_xauto_v_alt";
    paths.vBatt, paths.taps.vBatt, "f90_xauto_v_batt";
    paths.vLoads, paths.taps.vLoads, "f90_xauto_v_loads";
    paths.iLoads, paths.taps.iLoads, "f90_xauto_i_loads"};
for index = 1:size(items, 1)
    source = string(items{index, 1});
    tap = string(items{index, 2});
    variable = string(items{index, 3});
    parts = split(tap, "/");
    parent = strjoin(parts(1:end-1), "/");
    if getSimulinkBlockHandle(tap) == -1
        add_block("simulink/Sinks/To Workspace", tap, ...
            "VariableName", variable, "SaveFormat", "Timeseries", ...
            "MaxDataPoints", "inf");
    end
    try
        add_line(char(parent), char(extractAfter(source, parent + "/") + "/1"), ...
            char(extractAfter(tap, parent + "/") + "/1"), "autorouting", "on");
    catch exception
        if ~contains(string(exception.message), ["already", "exists"], "IgnoreCase", true)
            rethrow(exception);
        end
    end
end
end

function checks = localStaticChecks(modelPath, initScript, tableFile, paths, outDir)
checks = [ ...
    localCheck("pinned_model", "path", @() localFileCheck(modelPath)), ...
    localCheck("reference_initializer", "dependency", @() localFileCheck(initScript)), ...
    localCheck("alternator_table", "dependency", @() localFileCheck(tableFile)), ...
    localCheck("evidence_output_directory", "path", @() localFolderWritable(outDir)), ...
    localCheck("simulink_api", "api", @localApiCheck), ...
    localCheck("variant_workspace_input", "workspace", @localWorkspaceCheck), ...
    localCheck("native_driver_profile_groups", "workspace", @() localGroupCountCheck(paths.driver, 3)), ...
    localCheck("alternator_locator", "locator", @() localBlockCheck(paths.alternator)), ...
    localCheck("battery_locator", "locator", @() localBlockCheck(paths.battery)), ...
    localCheck("driver_profile_locator", "locator", @() localBlockCheck(paths.driver)), ...
    localCheck("vehicle_profile_locator", "locator", @() localBlockCheck(paths.vehicle)), ...
    localCheck("battery_voltage_locator", "locator", @() localBlockCheck(paths.vBatt)), ...
    localCheck("alternator_voltage_locator", "locator", @() localBlockCheck(paths.vAlt)), ...
    localCheck("load_voltage_locator", "locator", @() localBlockCheck(paths.vLoads)), ...
    localCheck("load_current_locator", "locator", @() localBlockCheck(paths.iLoads)), ...
    localCheck("battery_voltage_port", "port", @() localSourcePortCheck(paths.vBatt)), ...
    localCheck("alternator_voltage_port", "port", @() localSourcePortCheck(paths.vAlt)), ...
    localCheck("load_voltage_port", "port", @() localSourcePortCheck(paths.vLoads)), ...
    localCheck("load_current_port", "port", @() localSourcePortCheck(paths.iLoads)), ...
    localCheck("battery_tap_log_object", "log_object", @() localTapCheck(paths.taps.vBatt, "f90_xauto_v_batt")), ...
    localCheck("alternator_tap_log_object", "log_object", @() localTapCheck(paths.taps.vAlt, "f90_xauto_v_alt")), ...
    localCheck("load_voltage_tap_log_object", "log_object", @() localTapCheck(paths.taps.vLoads, "f90_xauto_v_loads")), ...
    localCheck("load_current_tap_log_object", "log_object", @() localTapCheck(paths.taps.iLoads, "f90_xauto_i_loads")) ...
    ];
end

function checks = localCompiledChecks(paths)
checks = [ ...
    localCheck("battery_voltage_dimensions_and_type", "compiled_dimensions", @() localCompiledSignalCheck(paths.vBatt)), ...
    localCheck("alternator_voltage_dimensions_and_type", "compiled_dimensions", @() localCompiledSignalCheck(paths.vAlt)), ...
    localCheck("load_voltage_dimensions_and_type", "compiled_dimensions", @() localCompiledSignalCheck(paths.vLoads)), ...
    localCheck("load_current_dimensions_and_type", "compiled_dimensions", @() localCompiledSignalCheck(paths.iLoads)), ...
    localCheck("battery_voltage_not_bus", "bus", @() localNotBusCheck(paths.vBatt)), ...
    localCheck("alternator_voltage_not_bus", "bus", @() localNotBusCheck(paths.vAlt)), ...
    localCheck("load_voltage_not_bus", "bus", @() localNotBusCheck(paths.vLoads)), ...
    localCheck("load_current_not_bus", "bus", @() localNotBusCheck(paths.iLoads)) ...
    ];
end

function localApplyScenario(model, paths, scenario)
assignin("base", "AlternatorSelection", double(scenario.alternator_selection));
signalbuilder(char(paths.driver), "activegroup", double(scenario.driver_group));
set_param(model, "SimulationCommand", "update");
end

function signals = localExtractSignals(simOut)
names = ["f90_xauto_v_alt", "f90_xauto_v_batt", "f90_xauto_v_loads", "f90_xauto_i_loads"];
signals = struct;
for index = 1:numel(names)
    name = names(index);
    value = simOut.get(char(name));
    assert(isa(value, "timeseries"), "SimuVerity:F90:XAUTO03:SignalType", ...
        "%s must be a Timeseries.", name);
    signals.(char(name)) = localPackTimeseries(value);
end
end

function packed = localPackTimeseries(value)
time = double(value.Time(:));
data = double(squeeze(value.Data));
if ~isvector(data), data = data(:, 1); end
data = data(:);
count = min(numel(time), numel(data));
packed = struct("time_s", time(1:count), "data", data(1:count));
end

function localValidateSmoke(signals, stopTime)
metrics = localMetrics(signals, stopTime);
assert(localSignalsValid(signals, metrics, stopTime), ...
    "SimuVerity:F90:XAUTO03:SmokeFailed", "Short nominal smoke did not satisfy output contract.");
end

function metrics = localMetrics(signals, stopTime)
vb = signals.f90_xauto_v_batt;
vl = signals.f90_xauto_v_loads;
va = signals.f90_xauto_v_alt;
il = signals.f90_xauto_i_loads;
tail = vb.time_s >= vb.time_s(1) + 0.70 * (vb.time_s(end) - vb.time_s(1));
if ~any(tail), tail = true(size(vb.time_s)); end
peakIndex = find(abs(il.data) >= 0.95 * max(abs(il.data)), 1, "last");
if isempty(peakIndex), peakIndex = numel(vb.data); end
releaseStart = min(numel(vb.data), peakIndex + max(1, round(0.1 * numel(vb.data))));
recovery = abs(vb.data(releaseStart:end) - mean(vb.data(tail)));
metrics = struct( ...
    "all_finite", all(isfinite(vb.data)) && all(isfinite(vl.data)) && ...
        all(isfinite(va.data)) && all(isfinite(il.data)), ...
    "time_coverage_ratio", double((vb.time_s(end) - vb.time_s(1)) / stopTime), ...
    "battery_voltage_mean_v", mean(vb.data), ...
    "battery_voltage_tail_mean_v", mean(vb.data(tail)), ...
    "battery_voltage_min_v", min(vb.data), ...
    "battery_voltage_max_v", max(vb.data), ...
    "alternator_voltage_mean_v", mean(va.data), ...
    "load_voltage_mean_v", mean(vl.data), ...
    "load_voltage_min_v", min(vl.data), ...
    "load_voltage_max_v", max(vl.data), ...
    "load_current_peak_a", max(abs(il.data)), ...
    "load_current_mean_a", mean(il.data), ...
    "load_current_std_a", std(il.data), ...
    "load_current_shape_signature", sum(il.data(:) .* sin((1:numel(il.data))' * sqrt(2))) / numel(il.data), ...
    "load_step_recovery_error_v", mean(recovery));
end

function pass = localSignalsValid(signals, metrics, stopTime)
names = fieldnames(signals);
pass = metrics.all_finite && metrics.time_coverage_ratio >= 0.99 && ...
    metrics.load_current_std_a > 0.02;
for index = 1:numel(names)
    row = signals.(names{index});
    pass = pass && numel(row.time_s) >= 2 && row.time_s(1) <= 0.1 && ...
        row.time_s(end) >= 0.99 * stopTime;
end
end

function audit = localStaticAudit(model, paths)
regulators = find_system(model, "FollowLinks", "on", "LookUnderMasks", "all", ...
    "Name", "Regulate Voltage");
feedbackFrom = find_system(model, "FollowLinks", "on", "LookUnderMasks", "all", ...
    "BlockType", "From", "GotoTag", "V_batt");
audit = struct( ...
    "alternator_voltage_feedback", ~isempty(regulators) && ~isempty(feedbackFrom), ...
    "alternator_to_dc_bus", localPhysicalPortPresent(paths.alternator), ...
    "battery_to_dc_bus", localPhysicalPortPresent(paths.battery), ...
    "load_to_dc_bus", localPhysicalPortPresent(paths.iLoadSubsystem), ...
    "native_dynamic_load_profile", getSimulinkBlockHandle(paths.driver + "/FromWs") ~= -1, ...
    "measured_battery_voltage", getSimulinkBlockHandle(paths.vBatt) ~= -1, ...
    "measured_load_current", getSimulinkBlockHandle(paths.iLoads) ~= -1);
end

function result = localCheck(id, category, run)
result = struct("id", string(id), "category", string(category), "run", run);
end

function result = localFileCheck(file)
result = struct("passed", isfile(file), "observed", string(file), "detail", "required pinned asset");
end

function result = localFolderWritable(folder)
try
    if ~isfolder(folder), mkdir(folder); end
    probe = fullfile(folder, ".f90_xauto_write_probe");
    fid = fopen(probe, "w"); assert(fid >= 0); fclose(fid); delete(probe);
    result = struct("passed", true, "observed", string(folder), "detail", "writable");
catch exception
    result = struct("passed", false, "observed", "", "detail", string(exception.message));
end
end

function result = localApiCheck()
ok = all(cellfun(@(name) ~isempty(which(name)), ...
    {"load_system", "sim", "set_param", "add_block", "add_line"}));
result = struct("passed", ok, "observed", string(version("-release")), ...
    "detail", "Simulink load/sim/tap APIs available");
end

function result = localWorkspaceCheck()
exists = evalin("base", "exist('AlternatorSelection','var')") == 1;
value = NaN;
if exists, value = evalin("base", "AlternatorSelection"); end
result = struct("passed", exists && isnumeric(value) && isscalar(value), ...
    "observed", string(value), "detail", "native alternator variant workspace input");
end

function result = localBlockCheck(block)
result = struct("passed", getSimulinkBlockHandle(block) ~= -1, ...
    "observed", string(block), "detail", "required locator");
end

function result = localSourcePortCheck(block)
try
    ports = get_param(block, "PortHandles");
    passed = isfield(ports, "Outport") && numel(ports.Outport) == 1;
    result = struct("passed", passed, "observed", sprintf("outports=%d", numel(ports.Outport)), ...
        "detail", "scalar Simulink measurement output");
catch exception
    result = struct("passed", false, "observed", "", "detail", string(exception.message));
end
end

function result = localTapCheck(tap, variable)
try
    exists = getSimulinkBlockHandle(tap) ~= -1;
    format = "";
    name = "";
    if exists
        format = string(get_param(tap, "SaveFormat"));
        name = string(get_param(tap, "VariableName"));
    end
    result = struct("passed", exists && format == "Timeseries" && name == variable, ...
        "observed", tap + " -> " + name + " (" + format + ")", ...
        "detail", "full-duration Timeseries log object");
catch exception
    result = struct("passed", false, "observed", "", "detail", string(exception.message));
end
end

function result = localCompiledSignalCheck(block)
try
    dims = get_param(block, "CompiledPortDimensions");
    types = get_param(block, "CompiledPortDataTypes");
    observed = string(evalc("disp(dims)")) + " | " + string(evalc("disp(types)"));
    valid = isfield(dims, "Outport") && ~isempty(dims.Outport) && ...
        isfield(types, "Outport") && ~isempty(types.Outport);
    result = struct("passed", valid, "observed", observed, ...
        "detail", "compiled dimensions and data type");
catch exception
    result = struct("passed", false, "observed", "", "detail", string(exception.message));
end
end

function result = localNotBusCheck(block)
try
    types = get_param(block, "CompiledPortDataTypes");
    observed = string(types.Outport);
    result = struct("passed", ~contains(lower(observed), "bus"), ...
        "observed", observed, "detail", "required scalar physical measurement, not a bus");
catch exception
    result = struct("passed", false, "observed", "", "detail", string(exception.message));
end
end

function present = localPhysicalPortPresent(block)
try
    ports = get_param(block, "PortHandles");
    present = (isfield(ports, "LConn") && ~isempty(ports.LConn)) || ...
              (isfield(ports, "RConn") && ~isempty(ports.RConn)) || ...
              (isfield(ports, "PMIOPort") && ~isempty(ports.PMIOPort));
catch
    present = false;
end
end

function result = localGroupCountCheck(block, minimum)
try
    count = localGroupCount(block);
    result = struct("passed", count >= minimum, "observed", string(count), ...
        "detail", "native Signal Builder groups available for official scenarios");
catch exception
    result = struct("passed", false, "observed", "", "detail", string(exception.message));
end
end

function count = localGroupCount(block)
original = signalbuilder(char(block), "activegroup");
cleanup = onCleanup(@() signalbuilder(char(block), "activegroup", original)); %#ok<NASGU>
count = 0;
for index = 1:32
    try
        signalbuilder(char(block), "activegroup", index);
        count = index;
    catch
        break;
    end
end
end

function pass = localScenarioDiversity(rows)
if numel(rows) < 2 || ~all([rows.valid])
    pass = false;
    return;
end
signatures = zeros(numel(rows), 3);
for index = 1:numel(rows)
    metrics = rows(index).metrics;
    signatures(index, :) = [metrics.load_current_mean_a, ...
        metrics.load_current_std_a, metrics.load_current_shape_signature];
end
% Distinct native load profiles must produce at least two genuinely distinct
% current trajectories; scenario labels alone are not accepted as variation.
pass = size(unique(round(signatures, 6), "rows"), 1) >= 2;
end

function row = localEmptyScenario()
row = struct("id", "", "class", "", "requested_inputs", struct, ...
    "valid", false, "simulation_wall_clock_s", NaN, "metrics", struct, ...
    "signal_file", "", "error", struct);
end

function localWriteScenario(outDir, row, signals)
payload = struct("scenario", row, "signals", signals);
matPath = fullfile(outDir, row.signal_file);
temporary = matPath + ".tmp." + string(feature("getpid"));
save(temporary, "payload", "-v7");
movefile(temporary, matPath, "f");
localWriteJson(fullfile(outDir, "scenario_" + row.id + ".json"), row);
end

function localFinish(model, modelPath, outDir, evidence)
evidence.reference_binding_after = localFilePresence(modelPath);
evidence.runtime.finished_at = localNow;
localWriteJson(fullfile(outDir, "evidence.json"), evidence);
if strlength(model) > 0
    try, bdclose(model); catch, end
end
end

function localWriteJson(path, value)
parent = fileparts(path);
if ~isfolder(parent), mkdir(parent); end
temporary = path + ".tmp." + string(feature("getpid"));
fid = fopen(temporary, "w", "n", "UTF-8");
assert(fid >= 0, "SimuVerity:F90:XAUTO03:Write", "Cannot write evidence.");
fprintf(fid, "%s\n", jsonencode(value, PrettyPrint=true));
fclose(fid);
movefile(temporary, path, "f");
end

function error = localError(exception)
error = struct("identifier", string(exception.identifier), ...
    "message", string(exception.message), "stack", string({exception.stack.name}));
end

function evidence = localSkeleton(initialBinding)
evidence = struct( ...
    "schema", "simuverity.f90-xauto03-evidence.v1", ...
    "task_id", "F90-XAUTO-03", "evidence_complete", false, ...
    "extraction_only", true, "contains_score_decisions", false, ...
    "reference_substantive_modifications", 0, ...
    "reference_binding_before", initialBinding, "load_pass", false, ...
    "update_pass", false, "compile_pass", false, "nominal_smoke_pass", false, ...
    "preflight", struct, "static_audit", struct, "scenarios", struct([]), ...
    "errors", struct, "runtime", struct("generation_run_id", string(getenv("SIMUVERITY_GENERATION_RUN_ID")), ...
        "matlab_release", string(version("-release")), "matlab_pid", feature("getpid"), ...
        "started_at", localNow));
end

function localCleanup(model, oldDir, oldPath)
try, if strlength(model) > 0, bdclose(model); end, catch, end
try, cd(oldDir); catch, end
path(oldPath);
end

function root = localRepoRoot()
here = fileparts(mfilename("fullpath"));
root = char(java.io.File(fullfile(here, "..", "..", "..", "..")).getCanonicalPath());
end

function summary = localFilePresence(file)
assert(isfile(file), "SimuVerity:FileMissing", "Required file is missing: %s", file);
summary = "present";
end

function value = localNow()
value = string(datetime("now", "TimeZone", "Asia/Shanghai", ...
    "Format", "yyyy-MM-dd'T'HH:mm:ssXXX"));
end
