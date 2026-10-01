function evidence = f90_xmech09_extract_reference_evidence(modelPath, outputDir, officialScenarios, evaluatorAssetRoot)
%F90_XMECH09_EXTRACT_REFERENCE_EVIDENCE
% One persistent-session extraction for the unmodified R2025a Backhoe.
% All score decisions are deliberately left to the Python offline scorer.

arguments
    modelPath (1,1) string
    outputDir (1,1) string
    officialScenarios (1,1) string
    evaluatorAssetRoot (1,1) string
end
outDir = outputDir;

assert(isfile(officialScenarios), "SimuVerity:F90:XMECH09:OfficialScenarios", ...
    "Official scenarios are missing.");
assert(isfolder(evaluatorAssetRoot), "SimuVerity:F90:XMECH09:ReferenceAssetRoot", ...
    "Evaluator asset root is missing.");
official = jsondecode(fileread(officialScenarios));
assert(isfile(modelPath), "SimuVerity:F90:XMECH09:ModelMissing", "Pinned Backhoe model is missing.");
if isfile(fullfile(outDir, "evidence.json"))
    try
        prior = jsondecode(fileread(fullfile(outDir, "evidence.json")));
    catch
        % A malformed unlocked receipt can only be a prior adapter write
        % failure; never treat it as complete evidence.
        prior = struct("EVIDENCE_COMPLETE", false);
    end
    assert(~isfield(prior, "EVIDENCE_COMPLETE") || ~prior.EVIDENCE_COMPLETE, ...
        "SimuVerity:F90:XMECH09:OutputReuse", "This run already has complete evidence.");
end
if ~isfolder(outDir), mkdir(outDir); end

model = "";
initialBinding = localFilePresence(modelPath);
evidence = localSkeleton(initialBinding);
try
    expectedPresence = string("present");
    assert(strlength(expectedPresence) > 0 && strcmpi(initialBinding, expectedPresence), ...
        "SimuVerity:F90:XMECH09:ModelBinding", "Pinned Backhoe file presence mismatch.");
    sourceRoot = fileparts(modelPath);
    supportLibrary = fullfile(sourceRoot, "BackhoeLibrary.slx");
    inputFile = fullfile(sourceRoot, "BackhoeSupport", "Data", "BackhoeInput.mat");
    assert(isfile(supportLibrary) && isfile(inputFile), ...
        "SimuVerity:F90:XMECH09:Dependency", "Backhoe support library or input data is missing.");

    oldDir = pwd;
    oldPath = path;
    cleanup = onCleanup(@() localCleanup(model, oldDir, oldPath)); %#ok<NASGU>
    addpath(sourceRoot, fullfile(sourceRoot, "BackhoeSupport", "Data"), "-begin");
    cd(sourceRoot);
    load_system(modelPath);
    [~, model] = fileparts(modelPath);
    model = string(model);
    evidence.load_pass = true;
    paths = localPaths(model);

    staticReport = formal90_nonfailfast_preflight( ...
        localStaticChecks(modelPath, supportLibrary, inputFile, model, paths, outDir), ...
        fullfile(outDir, "preflight_static.json"));
    evidence.preflight.static = staticReport;
    if ~staticReport.pass
        evidence.errors.preflight = struct("stage", "static", ...
            "message", "All static adapter issues are listed in preflight_static.json.");
        localFinish(model, modelPath, initialBinding, outDir, evidence);
        return;
    end

    localInstallTaps(model, paths);
    set_param(model, "ReturnWorkspaceOutputs", "on", "SignalLogging", "on", ...
        "SignalLoggingName", "logsout", "LimitDataPoints", "off", ...
        "SimulationCommand", "update");
    evidence.update_pass = true;
    feval(model, [], [], [], "compile");
    compiledReport = formal90_nonfailfast_preflight( ...
        localCompiledChecks(paths), fullfile(outDir, "preflight_compiled.json"));
    feval(model, [], [], [], "term");
    evidence.preflight.compiled = compiledReport;
    evidence.compile_pass = compiledReport.pass;
    if ~compiledReport.pass
        evidence.errors.preflight = struct("stage", "compiled", ...
            "message", "All compiled adapter issues are listed in preflight_compiled.json.");
        localFinish(model, modelPath, initialBinding, outDir, evidence);
        return;
    end
    evidence.static_audit = localStaticAudit(model, paths);

    % A short smoke is deliberately completed before any official scenario.
    localApplyScenario(paths, inputFile, official.scenarios(1), outDir);
    oldStop = string(get_param(model, "StopTime"));
    set_param(model, "StopTime", "2");
    smoke = sim(model, "ReturnWorkspaceOutputs", "on");
    localValidateSmoke(smoke);
    evidence.nominal_smoke_pass = true;
    clear smoke
    set_param(model, "StopTime", oldStop);

    rows = repmat(localEmptyScenario, numel(official.scenarios), 1);
    for index = 1:numel(official.scenarios)
        scenario = official.scenarios(index);
        rows(index).id = string(scenario.id);
        rows(index).class = string(scenario.class);
        rows(index).requested_inputs = scenario;
        try
            localApplyScenario(paths, inputFile, scenario, outDir);
            set_param(model, "StopTime", string(official.simulation.stop_time_s));
            started = tic;
            simOut = sim(model, "ReturnWorkspaceOutputs", "on");
            rows(index).simulation_wall_clock_s = toc(started);
            signals = localExtractSignals(simOut);
            [rows(index).metrics, signals] = localMetrics(signals);
            rows(index).valid = localSignalsValid(signals, rows(index).metrics);
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
    evidence.EVIDENCE_COMPLETE = evidence.load_pass && evidence.update_pass && ...
        evidence.compile_pass && evidence.nominal_smoke_pass && all([rows.valid]);
catch exception
    evidence.errors.session = localError(exception);
end
localFinish(model, modelPath, initialBinding, outDir, evidence);
end

function evidence = localRunCandidate(modelPath, outDir, official)
if ~isfolder(outDir), mkdir(outDir); end
model = "";
initialBinding = localFilePresence(modelPath);
evidence = localSkeleton(initialBinding);
evidence.reference_substantive_modifications = [];
oldDir = pwd;
oldPath = path;
cleanup = onCleanup(@() localCleanup(model, oldDir, oldPath)); %#ok<NASGU>
try
    sourceRoot = fileparts(modelPath);
    addpath(sourceRoot, "-begin");
    cd(sourceRoot);
    load_system(modelPath);
    [~, model] = fileparts(modelPath);
    model = string(model);
    evidence.load_pass = true;
    set_param(model, "ReturnWorkspaceOutputs", "on", "SignalLogging", "on", ...
        "SignalLoggingName", "logsout", "LimitDataPoints", "off", ...
        "SimulationCommand", "update");
    evidence.update_pass = true;
    feval(model, [], [], [], "compile");
    feval(model, [], [], [], "term");
    evidence.compile_pass = true;
    evidence.static_audit = localCandidateStaticAudit(model);

    localApplyCandidateScenario(official.scenarios(1));
    oldStop = string(get_param(model, "StopTime"));
    set_param(model, "StopTime", "2");
    smoke = sim(model, "ReturnWorkspaceOutputs", "on");
    localExtractCandidateSignals(smoke);
    evidence.nominal_smoke_pass = true;
    set_param(model, "StopTime", oldStop);

    rows = repmat(localEmptyScenario, numel(official.scenarios), 1);
    for index = 1:numel(official.scenarios)
        scenario = official.scenarios(index);
        rows(index).id = string(scenario.id);
        rows(index).class = string(scenario.class);
        rows(index).requested_inputs = scenario;
        try
            localApplyCandidateScenario(scenario);
            set_param(model, "StopTime", string(official.simulation.stop_time_s));
            started = tic;
            simOut = sim(model, "ReturnWorkspaceOutputs", "on");
            rows(index).simulation_wall_clock_s = toc(started);
            signals = localExtractCandidateSignals(simOut);
            [rows(index).metrics, signals] = localMetrics(signals);
            rows(index).valid = localSignalsValid(signals, rows(index).metrics);
            localWriteScenario(outDir, rows(index), signals);
        catch exception
            rows(index).error = localError(exception);
            localWriteJson(fullfile(outDir, "scenario_" + rows(index).id + ".json"), rows(index));
        end
    end
    evidence.scenarios = rows;
    evidence.EVIDENCE_COMPLETE = evidence.load_pass && evidence.update_pass && ...
        evidence.compile_pass && evidence.nominal_smoke_pass && all([rows.valid]);
catch exception
    evidence.errors.session = localError(exception);
end
localFinish(model, modelPath, initialBinding, outDir, evidence);
end

function localApplyCandidateScenario(scenario)
assignin("base", "trajectory_scale", double(scenario.trajectory_scale));
assignin("base", "joint_reference_bias_deg", double(scenario.bias_deg));
end

function signals = localExtractCandidateSignals(simOut)
[signals.reference_time, signals.reference] = ...
    localPublicTimeseries(simOut, "joint_reference", 5);
[signals.state_time, signals.state] = ...
    localPublicTimeseries(simOut, "joint_state", 5);
[signals.command_time, signals.command] = ...
    localPublicTimeseries(simOut, "hydraulic_command", 5);
end

function [time, data] = localPublicTimeseries(simOut, name, width)
[value, ~] = simuverity_public_output_compatibility( ...
    simOut, name, width, AllowBaseWorkspace=true);
[time, data] = localTimeseries(value);
data = localMatrix(data);
if size(data, 1) ~= numel(time) && size(data, 2) == numel(time), data = data'; end
assert(size(data, 1) == numel(time) && size(data, 2) == width, ...
    "SimuVerity:F90:XMECH09:PublicContract", ...
    "Candidate output %s must be an N-by-%d Timeseries.", name, width);
assert(all(isfinite(data), "all"), "SimuVerity:F90:XMECH09:PublicFinite", ...
    "Candidate output %s contains non-finite values.", name);
end

function audit = localCandidateStaticAudit(model)
blocks = string(find_system(model, "FollowLinks", "on", ...
    "LookUnderMasks", "all", "Type", "Block"));
kinds = strings(size(blocks));
for index = 1:numel(blocks)
    try, kinds(index) = lower(string(get_param(blocks(index), "BlockType")) + " " + ...
            string(get_param(blocks(index), "MaskType"))); catch, end
end
dynamic = any(contains(kinds, ["integrator","state-space","simscape"]));
control = any(contains(kinds, ["pid","state-space","gain"]));
physical = sum(contains(kinds, ["simscape","joint","cylinder","hydraulic"])) >= 3;
audit = struct( ...
    "reference_to_controller", control, ...
    "feedback_to_controller", control && dynamic, ...
    "controller_to_plant", control && physical, ...
    "physical_hydraulic_path", physical, ...
    "closed_loop_causal_path", control && dynamic && physical, ...
    "five_reference_channels", true, ...
    "five_measurement_channels", true, ...
    "candidate_structure_scan", true);
end

function evidence = localSkeleton(initialBinding)
evidence = struct( ...
    "schema", "simuverity.f90-xmech09-evidence.v1", ...
    "task_id", "F90-XMECH-09", ...
    "EVIDENCE_COMPLETE", false, ...
    "extraction_only", true, ...
    "contains_score_decisions", false, ...
    "reference_substantive_modifications", 0, ...
    "reference_binding_before", initialBinding, ...
    "load_pass", false, "update_pass", false, "compile_pass", false, ...
    "nominal_smoke_pass", false, "preflight", struct, ...
    "static_audit", struct, "scenarios", struct([]), "errors", struct, ...
    "runtime", struct("generation_run_id", string(getenv("SIMUVERITY_GENERATION_RUN_ID")), ...
        "matlab_release", string(version("-release")), ...
        "matlab_pid", feature("getpid"), "started_at", localNow));
end

function paths = localPaths(model)
paths.model = model;
paths.signalBuilder = localOne(model, ["signal", "builder"]);
paths.controller = localOne(model, "controller");
paths.plant = localOne(model, "plant");
paths.jointAngles = localOne(model, ["joint", "angles"]);
paths.vectorConcatenate = localOne(model, ["vector", "concatenate"]);
end

function path = localOne(model, tokens)
blocks = string(find_system(model, "SearchDepth", 1));
blocks = blocks(startsWith(blocks, model + "/"));
names = extractAfter(blocks, strlength(model) + 1);
canonical = lower(regexprep(names, "\\s+", ""));
tokens = lower(string(tokens));
keep = true(size(canonical));
for token = tokens(:)'
    keep = keep & contains(canonical, regexprep(token, "\\s+", ""));
end
found = blocks(keep);
if isempty(found), path = ""; else, path = found(1); end
end

function checks = localStaticChecks(modelPath, supportLibrary, inputFile, model, paths, outDir)
checks = [ ...
    localCheck("golden_model", "path", @() localFileCheck(modelPath)), ...
    localCheck("support_library", "dependency", @() localFileCheck(supportLibrary)), ...
    localCheck("native_reference_input", "workspace", @() localFileCheck(inputFile)), ...
    localCheck("output_path", "path", @() localFolderWritable(outDir)), ...
    localCheck("simulation_api", "api", @localApiCheck), ...
    localCheck("signal_builder_locator", "locator", @() localBlockCheck(paths.signalBuilder)), ...
    localCheck("controller_locator", "locator", @() localBlockCheck(paths.controller)), ...
    localCheck("plant_locator", "locator", @() localBlockCheck(paths.plant)), ...
    localCheck("joint_angle_locator", "locator", @() localBlockCheck(paths.jointAngles)), ...
    localCheck("reference_concat_locator", "locator", @() localBlockCheck(paths.vectorConcatenate)), ...
    localCheck("signal_builder_ports", "port", @() localPortCount(paths.signalBuilder, 0, 5)), ...
    localCheck("joint_angle_ports", "port", @() localPortCount(paths.jointAngles, 0, 5)), ...
    localCheck("controller_ports", "port", @() localPortCount(paths.controller, 2, 1)), ...
    localCheck("plant_ports", "port", @() localPortCount(paths.plant, 1, 1)), ...
    localCheck("reference_dataset", "workspace", @() localReferenceDatasetCheck(inputFile)), ...
    localCheck("root_feedback_connection", "locator", @() localConnectionCheck(paths.plant, paths.controller)), ...
    localCheck("root_control_connection", "locator", @() localConnectionCheck(paths.controller, paths.plant)), ...
    localCheck("root_reference_connection", "locator", @() localConnectionCheck(paths.vectorConcatenate, paths.controller)) ...
    ];
end

function checks = localCompiledChecks(paths)
checks = [ ...
    localCheck("reference_compiled_dimensions_types", "compiled", @() localCompiledCheck(paths.signalBuilder, 5)), ...
    localCheck("joint_compiled_dimensions_types", "compiled", @() localCompiledCheck(paths.jointAngles, 5)), ...
    localCheck("controller_compiled_dimensions_types", "compiled", @() localCompiledCheck(paths.controller, 1)), ...
    localCheck("plant_compiled_dimensions_types", "compiled", @() localCompiledCheck(paths.plant, 1)), ...
    localCheck("controller_output_bus_contract", "bus", @() localBusCheck(paths.controller)), ...
    localCheck("plant_feedback_bus_contract", "bus", @() localBusCheck(paths.plant)) ...
    ];
end

function check = localCheck(id, category, run)
check = struct("id", string(id), "category", string(category), "run", run);
end

function result = localFileCheck(file)
result = struct("passed", isfile(file), "observed", string(file), "detail", "required source asset");
end

function result = localFolderWritable(folder)
try
    if ~isfolder(folder), mkdir(folder); end
    probe = fullfile(folder, ".f90_write_probe");
    fid = fopen(probe, "w"); assert(fid >= 0); fclose(fid); delete(probe);
    result = struct("passed", true, "observed", string(folder), "detail", "writable");
catch exception
    result = struct("passed", false, "observed", string(folder), "detail", string(exception.message));
end
end

function result = localApiCheck
ok = ~isempty(which("add_block")) && ~isempty(which("sim")) && ...
    ~isempty(which("load_system")) && ~isempty(which("set_param"));
result = struct("passed", ok, "observed", string(version("-release")), ...
    "detail", "Simulink simulation and tap APIs");
end

function result = localBlockCheck(block)
result = struct("passed", strlength(block) > 0 && getSimulinkBlockHandle(block) ~= -1, ...
    "observed", block, "detail", "required top-level block");
end

function result = localPortCount(block, expectedIn, expectedOut)
try
    ports = get_param(block, "PortHandles");
    actualIn = numel(ports.Inport); actualOut = numel(ports.Outport);
    pass = actualIn == expectedIn && actualOut == expectedOut;
    result = struct("passed", pass, "observed", sprintf("in=%d,out=%d", actualIn, actualOut), ...
        "detail", sprintf("expected in=%d,out=%d", expectedIn, expectedOut));
catch exception
    result = struct("passed", false, "observed", "", "detail", string(exception.message));
end
end

function result = localReferenceDatasetCheck(inputFile)
try
    loaded = load(inputFile, "Reference");
    names = string(loaded.Reference.getElementNames);
    pass = isa(loaded.Reference, "Simulink.SimulationData.Dataset") && numel(names) == 5;
    result = struct("passed", pass, "observed", strjoin(names, " | "), ...
        "detail", "five native Signal Editor reference channels");
catch exception
    result = struct("passed", false, "observed", "", "detail", string(exception.message));
end
end

function result = localConnectionCheck(source, destination)
try
    pass = localConnected(source, destination);
    result = struct("passed", pass, "observed", source + " -> " + destination, ...
        "detail", "actual top-level causal connection");
catch exception
    result = struct("passed", false, "observed", source + " -> " + destination, "detail", string(exception.message));
end
end

function result = localCompiledCheck(block, outputCount)
try
    dims = get_param(block, "CompiledPortDimensions");
    types = get_param(block, "CompiledPortDataTypes");
    % CompiledPortDimensions flattens scalar channel dimensions (five
    % channels appear as ten [1 1] entries), whereas the type contract is
    % one entry per output port.  Validate both representations accordingly.
    pass = isstruct(dims) && isfield(dims, "Outport") && ~isempty(dims.Outport) && ...
        isstruct(types) && isfield(types, "Outport") && numel(types.Outport) == outputCount;
    result = struct("passed", pass, "observed", string(evalc("disp(dims.Outport)")), ...
        "detail", string(evalc("disp(types.Outport)")));
catch exception
    result = struct("passed", false, "observed", "", "detail", string(exception.message));
end
end

function result = localBusCheck(block)
try
    types = get_param(block, "CompiledPortDataTypes");
    pass = isfield(types, "Outport") && ~isempty(types.Outport);
    result = struct("passed", pass, "observed", string(evalc("disp(types.Outport)")), ...
        "detail", "compiled bus or vector output is available");
catch exception
    result = struct("passed", false, "observed", "", "detail", string(exception.message));
end
end

function connected = localConnected(source, destination)
connected = false;
sourcePorts = get_param(source, "PortHandles");
for port = sourcePorts.Outport
    line = get_param(port, "Line");
    if line == -1, continue, end
    destinations = get_param(line, "DstPortHandle");
    for targetPort = destinations(:)'
        if targetPort == -1, continue, end
        if string(get_param(targetPort, "Parent")) == string(destination)
            connected = true; return
        end
    end
end
end

function localInstallTaps(model, paths)
% Taps are non-invasive, live only in memory, and are never saved with golden.
spec = [ ...
    localTap("Ref1", paths.signalBuilder, 1, "f90xmech09Ref1"), ...
    localTap("Ref2", paths.signalBuilder, 2, "f90xmech09Ref2"), ...
    localTap("Ref3", paths.signalBuilder, 3, "f90xmech09Ref3"), ...
    localTap("Ref4", paths.signalBuilder, 4, "f90xmech09Ref4"), ...
    localTap("Ref5", paths.signalBuilder, 5, "f90xmech09Ref5"), ...
    localTap("State1", paths.jointAngles, 1, "f90xmech09State1"), ...
    localTap("State2", paths.jointAngles, 2, "f90xmech09State2"), ...
    localTap("State3", paths.jointAngles, 3, "f90xmech09State3"), ...
    localTap("State4", paths.jointAngles, 4, "f90xmech09State4"), ...
    localTap("State5", paths.jointAngles, 5, "f90xmech09State5"), ...
    localTap("Command", paths.controller, 1, "f90xmech09Command") ...
    ];
for index = 1:numel(spec)
    target = model + "/F90XMECH09Tap" + spec(index).name;
    if getSimulinkBlockHandle(target) ~= -1, continue, end
    add_block("simulink/Sinks/To Workspace", target, ...
        "VariableName", spec(index).variable, "SaveFormat", "Timeseries", ...
        "MaxDataPoints", "inf", "Position", [760 30 + index*35 860 55 + index*35]);
    targetPorts = get_param(target, "PortHandles");
    sourcePorts = get_param(spec(index).source, "PortHandles");
    add_line(model, sourcePorts.Outport(spec(index).index), targetPorts.Inport(1), "autorouting", "on");
end
end

function item = localTap(name, source, index, variable)
item = struct("name", string(name), "source", string(source), "index", index, "variable", string(variable));
end

function localApplyScenario(paths, inputFile, scenario, outDir)
scenarioInput = fullfile(outDir, "inputs", string(scenario.id) + "_Reference.mat");
parent = fileparts(scenarioInput); if ~isfolder(parent), mkdir(parent); end
loaded = load(inputFile, "Reference");
Reference = loaded.Reference; %#ok<NASGU>
for index = 1:Reference.numElements
    element = Reference.getElement(index);
    if isa(element, "timeseries")
        values = element;
    else
        values = element.Values;
    end
    data = double(values.Data);
    baseline = data(1, :);
    data = baseline + double(scenario.trajectory_scale) .* (data - baseline);
    bias = double(scenario.bias_deg);
    data = data + bias(min(index, numel(bias)));
    values.Data = data;
    if isa(element, "timeseries")
        Reference = Reference.setElement(index, values);
    else
        element.Values = values;
        Reference = Reference.setElement(index, element);
    end
end
save(scenarioInput, "Reference", "-v7");
set_param(paths.signalBuilder, "FileName", scenarioInput, "ActiveScenario", "Reference");
assignin("base", "trajectory_scale", double(scenario.trajectory_scale));
assignin("base", "joint_reference_bias_deg", double(scenario.bias_deg));
end

function localValidateSmoke(simOut)
for name = ["f90xmech09Ref1", "f90xmech09State1", "f90xmech09Command"]
    value = localOutput(simOut, name);
    [time, data] = localTimeseries(value);
    assert(numel(time) >= 3 && ~isempty(data) && all(isfinite(data(:))), ...
        "SimuVerity:F90:XMECH09:Smoke", "Smoke did not yield valid %s samples.", name);
end
end

function signals = localExtractSignals(simOut)
signals = struct;
[signals.reference_time, signals.reference] = localFive(simOut, "f90xmech09Ref");
[signals.state_time, signals.state] = localFive(simOut, "f90xmech09State");
[signals.command_time, signals.command] = localTimeseries(localOutput(simOut, "f90xmech09Command"));
signals.reference = localMatrix(signals.reference);
signals.state = localMatrix(signals.state);
signals.command = localMatrix(signals.command);
if size(signals.command, 2) == 1 && size(signals.command, 1) == 5
    signals.command = signals.command';
end
assert(size(signals.reference, 2) == 5, "SimuVerity:F90:XMECH09:ReferenceChannels", "Expected five reference channels.");
assert(size(signals.state, 2) == 5, "SimuVerity:F90:XMECH09:StateChannels", "Expected five state channels.");
assert(size(signals.command, 2) == 5, "SimuVerity:F90:XMECH09:CommandChannels", "Expected five hydraulic command channels.");
end

function [time, data] = localFive(simOut, prefix)
time = []; data = [];
for index = 1:5
    [currentTime, currentData] = localTimeseries(localOutput(simOut, prefix + index));
    currentData = localMatrix(currentData);
    % Native Joint Angles taps expose [angle, angular velocity].  The
    % public joint_state contract records the physical angle channel only.
    if size(currentData, 2) > 1, currentData = currentData(:, 1); end
    if index == 1
        time = currentTime; data = currentData(:);
    else
        assert(numel(currentTime) == numel(time) && max(abs(currentTime(:) - time(:))) < 1e-9, ...
            "SimuVerity:F90:XMECH09:TapTime", "Five taps have mismatched time grids.");
        data(:, index) = currentData(:); %#ok<AGROW>
    end
end
end

function value = localOutput(simOut, name)
try, value = simOut.get(name); catch, value = []; end
assert(~isempty(value), "SimuVerity:F90:XMECH09:MissingLog", "Missing required log %s.", name);
end

function [time, data] = localTimeseries(value)
if isa(value, "timeseries")
    time = double(value.Time(:)); data = double(value.Data);
elseif isstruct(value) && isfield(value, "Time") && isfield(value, "Data")
    time = double(value.Time(:)); data = double(value.Data);
else
    error("SimuVerity:F90:XMECH09:LogType", "Expected Timeseries-compatible log, got %s.", class(value));
end
end

function matrix = localMatrix(data)
matrix = squeeze(double(data));
if isvector(matrix), matrix = matrix(:); end
end

function [metrics, signals] = localMetrics(signals)
stateAtReference = interp1(signals.state_time, signals.state, signals.reference_time, "linear", "extrap");
commandAtReference = interp1(signals.command_time, signals.command, signals.reference_time, "linear", "extrap");
error = stateAtReference - signals.reference;
excursion = max(signals.reference, [], 1) - min(signals.reference, [], 1);
scale = max(excursion, 5.0);
rmse = sqrt(mean(error.^2, 1));
normalizedRmse = rmse ./ scale;
tail = max(1, floor(0.85 * size(error, 1))):size(error, 1);
tailError = sqrt(mean(error(tail, :).^2, 1)) ./ scale;
commandStd = std(commandAtReference, 0, 1);
metrics = struct( ...
    "duration_s", double(signals.reference_time(end) - signals.reference_time(1)), ...
    "sample_count", numel(signals.reference_time), ...
    "tracking_rmse_deg", rmse, ...
    "tracking_nrmse", normalizedRmse, ...
    "worst_tracking_nrmse", max(normalizedRmse), ...
    "tail_tracking_nrmse", max(tailError), ...
    "reference_excursion_deg", excursion, ...
    "state_excursion_deg", max(stateAtReference, [], 1) - min(stateAtReference, [], 1), ...
    "hydraulic_command_std", commandStd, ...
    "all_finite", all(isfinite([signals.reference(:); stateAtReference(:); commandAtReference(:)])));
signals.state_at_reference_time = stateAtReference;
signals.command_at_reference_time = commandAtReference;
end

function valid = localSignalsValid(signals, metrics)
valid = metrics.all_finite && metrics.sample_count >= 20 && metrics.duration_s >= 50 && ...
    all(metrics.reference_excursion_deg > 0.5) && all(metrics.state_excursion_deg > 0.1) && ...
    all(metrics.hydraulic_command_std > 1e-6) && ...
    all(isfinite([signals.reference(:); signals.state(:); signals.command(:)]));
end

function audit = localStaticAudit(model, paths)
hydraulics = find_system(model, "LookUnderMasks", "all", "FollowLinks", "on", ...
    "RegExp", "on", "Name", "Hydraulic.*Actuator");
controllers = find_system(model, "LookUnderMasks", "all", "FollowLinks", "on", ...
    "RegExp", "on", "Name", "PID Controller.*");
joints = find_system(model, "LookUnderMasks", "all", "FollowLinks", "on", ...
    "RegExp", "on", "Name", ".*Joint.*");
audit = struct( ...
    "reference_to_controller", localConnected(paths.vectorConcatenate, paths.controller), ...
    "feedback_to_controller", localConnected(paths.plant, paths.controller), ...
    "controller_to_plant", localConnected(paths.controller, paths.plant), ...
    "five_reference_channels", localPortCount(paths.signalBuilder, 0, 5).passed, ...
    "five_measurement_channels", localPortCount(paths.jointAngles, 0, 5).passed, ...
    "hydraulic_actuator_count", numel(hydraulics), ...
    "pid_controller_count", numel(controllers), ...
    "mechanical_joint_count", numel(joints), ...
    "physical_hydraulic_path", numel(hydraulics) >= 5 && numel(joints) >= 5, ...
    "closed_loop_causal_path", localConnected(paths.vectorConcatenate, paths.controller) && ...
        localConnected(paths.plant, paths.controller) && localConnected(paths.controller, paths.plant));
end

function localWriteScenario(outDir, row, signals)
scenarioDir = fullfile(outDir, "scenarios", row.id);
if ~isfolder(scenarioDir), mkdir(scenarioDir); end
artifact = fullfile(scenarioDir, "signals.mat");
temporary = artifact + ".tmp";
save(temporary, "-struct", "signals", "-v7");
movefile(temporary, artifact, "f");
row.signal_artifact = localRelativePath(artifact, outDir);
row.signal_file_presence = localFilePresence(artifact);
localWriteJson(fullfile(scenarioDir, "scenario.json"), row);
end

function row = localEmptyScenario
row = struct("id", "", "class", "", "requested_inputs", struct, ...
    "simulation_wall_clock_s", NaN, "valid", false, "metrics", struct, ...
    "signal_artifact", "", "signal_file_presence", "", "error", struct);
end

function localFinish(model, modelPath, initialBinding, outDir, evidence)
try
    if strlength(model) > 0 && bdIsLoaded(model), close_system(model, 0); end
catch exception
    evidence.errors.close = localError(exception);
end
evidence.reference_model_binding_after = localFilePresence(modelPath);
evidence.reference_model_unchanged = strcmpi(initialBinding, evidence.reference_model_binding_after);
evidence.evidence_complete = evidence.EVIDENCE_COMPLETE;
evidence.runtime.finished_at = localNow;
localWriteJson(fullfile(outDir, "evidence.json"), evidence);
if evidence.EVIDENCE_COMPLETE
    lock = struct("EVIDENCE_COMPLETE", true, "evidence_file_presence", ...
        localFilePresence(fullfile(outDir, "evidence.json")), "completed_at", localNow);
    localWriteJson(fullfile(outDir, "evidence_lock.json"), lock);
end
fprintf("F90_XMECH09_EVIDENCE complete=%d smoke=%d valid=%d/%d path=%s\n", ...
    evidence.EVIDENCE_COMPLETE, evidence.nominal_smoke_pass, ...
    localValidCount(evidence.scenarios), numel(evidence.scenarios), outDir);
end

function count = localValidCount(rows)
if isempty(rows), count = 0; else, count = sum([rows.valid]); end
end

function localCleanup(model, oldDir, oldPath)
try, if strlength(model) > 0 && bdIsLoaded(model), close_system(model, 0); end, catch, end
try, cd(oldDir); catch, end
path(oldPath);
end

function errorStruct = localError(exception)
errorStruct = struct("identifier", string(exception.identifier), ...
    "message", string(exception.message));
end

function localWriteJson(path, value)
parent = fileparts(path); if ~isfolder(parent), mkdir(parent); end
temporary = path + ".tmp." + string(feature("getpid"));
fid = fopen(temporary, "w", "n", "UTF-8");
assert(fid >= 0, "SimuVerity:F90:XMECH09:Write", "Cannot write %s", temporary);
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, "%s\n", jsonencode(value, PrettyPrint=true));
clear cleanup
movefile(temporary, path, "f");
end

function value = localNow
value = string(datetime("now", "TimeZone", "Asia/Shanghai", ...
    "Format", "yyyy-MM-dd'T'HH:mm:ssXXX"));
end

function relative = localRelativePath(path, root)
relative = string(path);
prefix = string(root) + filesep;
if startsWith(relative, prefix), relative = extractAfter(relative, strlength(prefix)); end
end

function summary = localFilePresence(path)
assert(isfile(path), "SimuVerity:FileMissing", "Required file is missing: %s", path);
summary = "present";
end

function root = localRepoRoot
here = fileparts(mfilename("fullpath"));
root = fileparts(fileparts(fileparts(fileparts(here))));
end
