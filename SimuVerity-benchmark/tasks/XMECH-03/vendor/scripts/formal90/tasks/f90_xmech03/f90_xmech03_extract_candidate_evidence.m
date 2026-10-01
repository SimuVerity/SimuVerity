function evidence = f90_xmech03_extract_candidate_evidence(modelPath, outDir)
%f90_xmech03_extract_candidate_evidence One-session, score-free evidence extraction.
%
% The exact reference is used without saving or changing its core. Existing
% workspace inputs are exposed, native 1024-point streaming is disabled in
% memory, and unlimited To Workspace taps are attached only by stable block
% path and output-port number. All five scenarios run in this MATLAB session.
arguments
    modelPath (1,1) string = ""
    outDir (1,1) string = ""
end

root = localProjectRoot;
taskRoot = string(getenv("SIMUVERITY_TASK_ROOT"));
official = jsondecode(fileread(simuverity_official_scenarios_path()));
sourceRoot = fullfile(taskRoot, "reference", "files", ...
    "Simscape-Dual-Clutch");
taskManifestPath = fullfile(taskRoot, "task.json");
assert(strlength(taskRoot) > 0 && isfile(taskManifestPath), ...
    "SimuVerity:F90:XMECH03:ReferenceManifest", ...
    "The public task manifest is unavailable.");
taskManifest = jsondecode(fileread(taskManifestPath));
assert(isstruct(taskManifest) && isscalar(taskManifest) && ...
    isfield(taskManifest, "reference") && isstruct(taskManifest.reference), ...
    "SimuVerity:F90:XMECH03:ReferenceManifest", ...
    "The public task manifest lacks the reference contract.");
expectedReferenceFilePresence = "present";
referenceModel = fullfile(sourceRoot, "Dual_Clutch_Trans.slx");
if strlength(modelPath) == 0, modelPath = referenceModel; end
assert(isfile(modelPath), "SimuVerity:F90:XMECH03:ModelMissing", ...
    "Model under evaluation is missing: %s", modelPath);

generationRunId = string(getenv("SIMUVERITY_GENERATION_RUN_ID"));
assert(strlength(generationRunId) > 0, "SimuVerity:F90:XMECH03:GenerationRunId", ...
    "SIMUVERITY_GENERATION_RUN_ID is required.");
if strlength(outDir) == 0
    outDir = fullfile(tempdir, "SimuVerity", "F90-XMECH-03", generationRunId);
end
assert(~isfolder(outDir), "SimuVerity:F90:XMECH03:OutputReuse", ...
    "Evidence output already exists for GenerationRunId %s.", generationRunId);
mkdir(outDir);

addpath(fullfile(root, "scripts", "xp9"));
modelPresence = lower(string(xp9_file_presence_file(modelPath)));
isReference = lower(strtrim(string(getenv("SIMUVERITY_EVALUATION_SUBJECT")))) == "reference";
evaluationSubject = lower(strtrim(string( ...
    getenv("SIMUVERITY_EVALUATION_SUBJECT"))));
if strlength(evaluationSubject) == 0
    evaluationSubject = "candidate";
end
assert(any(evaluationSubject == ["candidate", "reference"]), ...
    "SimuVerity:F90:XMECH03:EvaluationSubject", ...
    "Unsupported evaluation subject: %s", evaluationSubject);
if evaluationSubject == "reference"
    assert(isReference, "SimuVerity:F90:XMECH03:ReferenceIdentity", ...
        "Reference evaluation model file presence differs from task.json.");
end
[~, model] = fileparts(modelPath);

localConfigureIsolation;
set(groot, "defaultFigureVisible", "off");
pathBefore = path;
pathCleanup = onCleanup(@() path(pathBefore)); %#ok<NASGU>

evidence = struct;
evidence.schema = "simuverity.f90-xmech03-evidence.v1";
evidence.task_id = "F90-XMECH-03";
evidence.generation_run_id = generationRunId;
evidence.model_path = modelPath;
evidence.model_file_presence = modelPresence;
evidence.adapter = "standard_public_timeseries";
if isReference
    evidence.adapter = "reference_native_semantic_taps";
end
evidence.reference_subject = logical(isReference);
evidence.reference_substantive_modifications = 0;
evidence.extraction_only = true;
evidence.contains_score_decisions = false;
evidence.load_pass = false;
evidence.update_pass = false;
evidence.compile_pass = false;
evidence.scenarios = struct([]);
evidence.static_audit = struct;
evidence.errors = struct;
evidence.model_closed_without_save = false;
evidence.reference_binding_preserved = false;
evidence.started_at = localNow;
evidence.runtime = localRuntimeIdentity;

fatal = [];
try
    if isReference
        localInitializeReference(sourceRoot);
    end
    load_system(modelPath);
    evidence.load_pass = true;
    set_param(model, "ReturnWorkspaceOutputs", "on", ...
        "LimitDataPoints", "off");

    if isReference
        localSelectReferenceConfiguration(model);
        localReplaceNativeStreamingWithUnlimitedTaps(model);
    else
        % Candidate models may bind the three public inputs directly in
        % block parameters.  Make one declared scenario available before
        % update/compile; per-scenario values are still supplied below via
        % Simulink.SimulationInput and are not baked into the candidate.
        nominalScenario = official.scenarios(1);
        nominalCommand = localScenarioCommand(sourceRoot, nominalScenario);
        assignin("base", "speed_command", nominalCommand);
        assignin("base", "vehicle_mass_kg", ...
            double(nominalScenario.vehicle_mass_kg));
        assignin("base", "clutch_capacity_scale", ...
            double(nominalScenario.clutch_capacity_scale));
    end
    evidence.static_audit = localStaticAudit(model, isReference);

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
            try, feval(model, [], [], [], "term"); catch, end
        end
    end

    if evidence.update_pass && evidence.compile_pass
        baseline = struct;
        if isReference
            baseline = evalin("base", "DCT_Param");
        end
        rows = repmat(localEmptyScenario, numel(official.scenarios), 1);
        for index = 1:numel(official.scenarios)
            scenario = official.scenarios(index);
            row = localEmptyScenario;
            row.id = string(scenario.id);
            row.class = string(scenario.class);
            row.started_at = localNow;
            timer = tic;
            try
                command = localScenarioCommand(sourceRoot, scenario);
                row.requested_inputs = struct( ...
                    "duration_s", double(command.Time(end)), ...
                    "vehicle_mass_kg", ...
                        double(scenario.vehicle_mass_kg), ...
                    "clutch_capacity_scale", ...
                        double(scenario.clutch_capacity_scale));
                simInput = localSimulationInput(model, command, ...
                    scenario, isReference, baseline);
                simOut = sim(simInput);
                outputs = localExtractOutputs(simOut, command, ...
                    isReference);
                localValidateOutputs(outputs, double(command.Time(end)));
                outputFile = "scenario_" + row.id + ".json";
                localWriteJson(fullfile(outDir, outputFile), outputs);
                row.success = true;
                row.output_file = outputFile;
                row.output_file_presence = lower(string( ...
                    xp9_file_presence_file(fullfile(outDir, outputFile))));
                row.samples = numel(outputs.time_s);
                row.time_start_s = outputs.time_s(1);
                row.time_end_s = outputs.time_s(end);
            catch ME
                row.error = localError(ME);
            end
            row.wall_clock_seconds = toc(timer);
            row.finished_at = localNow;
            rows(index) = row;
            clear simOut outputs
        end
        evidence.scenarios = rows;
    end
catch ME
    fatal = ME;
    evidence.errors.session = localError(ME);
end

try
    if bdIsLoaded(model), close_system(model, 0); end
    evidence.model_closed_without_save = true;
catch ME
    evidence.errors.close_model = localError(ME);
end
if isReference
    evidence.reference_binding_preserved = ...
        lower(string(xp9_file_presence_file(referenceModel))) == ...
        expectedReferenceFilePresence;
end
evidence.finished_at = localNow;
localWriteJson(fullfile(outDir, "evidence.json"), evidence);

allScenariosPass = numel(evidence.scenarios) == ...
    numel(official.scenarios) && ...
    all([evidence.scenarios.success]);
if ~isempty(fatal), rethrow(fatal); end
assert(evidence.load_pass && evidence.update_pass && ...
    evidence.compile_pass && allScenariosPass, ...
    "SimuVerity:F90:XMECH03:EvidenceIncomplete", ...
    "The fixed-evidence session did not complete all required stages.");
end

function localConfigureIsolation
cacheDir = string(getenv("SIMULINK_CACHE_FOLDER"));
codegenDir = string(getenv("SIMULINK_CODEGEN_FOLDER"));
assert(strlength(cacheDir) > 0 && strlength(codegenDir) > 0, ...
    "SimuVerity:F90:XMECH03:Isolation", ...
    "Isolated Simulink cache and codegen folders are required.");
if ~isfolder(cacheDir), mkdir(cacheDir); end
if ~isfolder(codegenDir), mkdir(codegenDir); end
Simulink.fileGenControl("set", "CacheFolder", cacheDir, ...
    "CodeGenFolder", codegenDir, "createDir", true);
end

function localInitializeReference(sourceRoot)
addpath(genpath(sourceRoot));
assignin("base", "DCT_Model_HomeDir", char(sourceRoot));
localRunInBase(fullfile(sourceRoot, "Scripts_Data", ...
    "DCT_Model_PARAM.m"));
localRunInBase(fullfile(sourceRoot, "Libraries", "Engine", ...
    "MBC_Engine_Calibrations.m"));
end

function localRunInBase(file)
command = "run('" + replace(string(file), "'", "''") + "');";
evalin("base", command);
end

function localSelectReferenceConfiguration(model)
transmission = localResolveChild(model, "Dual Clutch Transmission");
engine = localResolveChild(model, "Engine");
vehicle = localResolveChild(model, "Vehicle Dynamics");
set_param(transmission, ...
    "LabelModeActiveChoice", "Detailed");
set_param(engine, ...
    "LabelModeActiveChoice", "Generic");
set_param(vehicle, ...
    "LabelModeActiveChoice", "Simple");
end

function localReplaceNativeStreamingWithUnlimitedTaps(model)
speedDemand = localResolveChild(model, "Speed Demand");
vehicle = localResolveChild(model, "Vehicle Dynamics");
engine = localResolveChild(model, "Engine");
transmission = localResolveChild(model, "Dual Clutch Transmission");
controller = localResolveChild(model, "Transmission Controller");
shiftState = localResolveChild(controller, "Shift state");

% Disable the four saved HMI streams that carry a 1024-point cap.
savedStreams = {
    vehicle, 1;
    engine, 1;
    controller, 2;
    shiftState, 5
    };
for index = 1:size(savedStreams, 1)
    try
        Simulink.sdi.markSignalForStreaming( ...
            savedStreams{index, 1}, savedStreams{index, 2}, "off");
    catch
    end
end

% Unsaved, unlimited taps use stable semantic paths and output-port numbers.
localAddTap(model, speedDemand, 1, ...
    "__F90_SpeedCommand", "f90_xmech03_speed_command", [780 40 920 70]);
localAddTap(model, vehicle, 1, ...
    "__F90_VehicleSpeed", "f90_xmech03_vehicle_speed", [780 80 920 110]);
localAddTap(model, engine, 1, ...
    "__F90_EngineSpeed", "f90_xmech03_engine_speed", [780 120 920 150]);
localAddTap(model, transmission, 1, ...
    "__F90_ClutchSlip", "f90_xmech03_clutch_slip", [780 160 920 190]);
localAddTap(model, controller, 2, ...
    "__F90_ClutchPressure", "f90_xmech03_clutch_pressure", ...
    [780 200 920 230]);
localAddTap(model, controller, 3, ...
    "__F90_TorqueDemand", "f90_xmech03_torque_demand", ...
    [780 240 920 270]);
localAddTap(controller, shiftState, 5, ...
    "__F90_GearState", "f90_xmech03_gear_state", ...
    [760 420 900 450]);
end

function localAddTap(parent, source, port, name, variable, position)
destination = parent + "/" + name;
assert(getSimulinkBlockHandle(source) > 0, ...
    "SimuVerity:F90:XMECH03:SemanticLocator", ...
    "Required semantic source block is missing: %s", source);
assert(getSimulinkBlockHandle(destination) < 0, ...
    "SimuVerity:F90:XMECH03:TapCollision", ...
    "Evaluation tap already exists: %s", destination);
add_block("simulink/Sinks/To Workspace", destination, ...
    "VariableName", variable, ...
    "SaveFormat", "Timeseries", ...
    "MaxDataPoints", "inf", ...
    "Decimation", "1", ...
    "Position", position);
sourcePorts = get_param(source, "PortHandles");
destinationPorts = get_param(destination, "PortHandles");
assert(numel(sourcePorts.Outport) >= port, ...
    "SimuVerity:F90:XMECH03:SemanticPort", ...
    "Required output port is missing at %s#out:%d.", source, port);
add_line(parent, sourcePorts.Outport(port), ...
    destinationPorts.Inport(1), "autorouting", "on");
end

function audit = localStaticAudit(model, isReference)
blocks = string(find_system(model, "LookUnderMasks", "all", ...
    "FollowLinks", "on", "Type", "Block"));
topology = localConnectivityTopology(blocks);
audit = struct( ...
    "semantic_locator_basis", true, ...
    "fixed_sid_used", false, ...
    "generic_connectivity_audit", topology, ...
    "connected_dual_path_gate", ...
        topology.connected_dual_path_gate, ...
    "feedback_connectivity_gate", ...
        topology.feedback_connectivity_gate, ...
    "reference_subject", logical(isReference));
if isReference
    % Exact component identities are checked only for the pinned reference.
    % They never gate a different legal Agent implementation.
    description = strings(size(blocks));
    for index = 1:numel(blocks)
        description(index) = lower(blocks(index) + " " + ...
            localParam(blocks(index), "SourceBlock") + " " + ...
            localParam(blocks(index), "ReferenceBlock") + " " + ...
            localParam(blocks(index), "MaskType"));
    end
    audit.reference_friction_clutch_count = ...
        nnz(contains(description, "friction clutch"));
    audit.reference_dog_clutch_count = ...
        nnz(contains(description, "dog clutch"));
    audit.reference_gear_component_count = ...
        nnz(contains(description, "simple gear"));
    transmission = localResolveChild(model, ...
        "Dual Clutch Transmission");
    engine = localResolveChild(model, "Engine");
    vehicle = localResolveChild(model, "Vehicle Dynamics");
    controller = localResolveChild(model, ...
        "Transmission Controller");
    audit.active_transmission = string(get_param( ...
        transmission, ...
        "LabelModeActiveChoice"));
    audit.active_engine = string(get_param( ...
        engine, "LabelModeActiveChoice"));
    audit.active_vehicle = string(get_param( ...
        vehicle, "LabelModeActiveChoice"));
    audit.controller_input_ports_connected = ...
        localConnectedPortFraction( ...
        controller, "Inport") == 1;
    audit.controller_output_ports_connected = ...
        localConnectedPortFraction( ...
        controller, "Outport") == 1;
    audit.reference_configuration_gate = ...
        audit.active_transmission == "Detailed" && ...
        audit.active_engine == "Generic" && ...
        audit.active_vehicle == "Simple" && ...
        audit.reference_friction_clutch_count >= 2 && ...
        audit.reference_dog_clutch_count >= 6 && ...
        audit.reference_gear_component_count >= 6 && ...
        audit.controller_input_ports_connected && ...
        audit.controller_output_ports_connected;
    audit.implementation_gate = ...
        audit.reference_configuration_gate && ...
        audit.connected_dual_path_gate && ...
        audit.feedback_connectivity_gate;
else
    audit.reference_configuration_gate = true;
    audit.implementation_gate = ...
        audit.connected_dual_path_gate && ...
        audit.feedback_connectivity_gate;
end
end

function block = localResolveChild(parent, expectedName)
children = string(find_system(parent, "SearchDepth", 1, ...
    "Type", "Block"));
children(children == parent) = [];
actualNames = strings(size(children));
for index = 1:numel(children)
    actualNames(index) = string(get_param(children(index), "Name"));
end
normalize = @(value) regexprep(strtrim(string(value)), "\s+", " ");
matches = normalize(actualNames) == normalize(expectedName);
assert(nnz(matches) == 1, "SimuVerity:F90:XMECH03:SemanticLocator", ...
    "Expected one direct child named %s under %s; found %d.", ...
    expectedName, parent, nnz(matches));
block = children(matches);
end

function audit = localConnectivityTopology(blocks)
% Build topology from actual port connections. No block, library, mask, or
% component name participates in this generic implementation gate.
count = numel(blocks);
handles = zeros(count, 1);
physicalPorts = zeros(count, 1);
signalInputs = zeros(count, 1);
signalOutputs = zeros(count, 1);
types = strings(count, 1);
parents = strings(count, 1);
indexByHandle = containers.Map("KeyType", "double", ...
    "ValueType", "double");
for index = 1:count
    handles(index) = get_param(blocks(index), "Handle");
    indexByHandle(handles(index)) = index;
    ports = get_param(handles(index), "PortHandles");
    physicalPorts(index) = numel(ports.LConn) + numel(ports.RConn);
    signalInputs(index) = numel(ports.Inport);
    signalOutputs(index) = numel(ports.Outport);
    types(index) = string(get_param(handles(index), "BlockType"));
    parents(index) = string(get_param(handles(index), "Parent"));
end

physicalLeft = zeros(0, 1);
physicalRight = zeros(0, 1);
signalLeft = zeros(0, 1);
signalRight = zeros(0, 1);
for index = 1:count
    ports = get_param(handles(index), "PortHandles");
    conserving = [ports.LConn(:); ports.RConn(:)];
    for port = conserving'
        [physicalLeft, physicalRight] = localLineEdges( ...
            index, port, indexByHandle, physicalLeft, physicalRight);
    end
    for port = ports.Outport(:)'
        [signalLeft, signalRight] = localLineEdges( ...
            index, port, indexByHandle, signalLeft, signalRight, true);
    end
end

% Join subsystem boundary ports to their parent blocks so the topology spans
% hierarchy levels instead of treating each masked subsystem as an island.
for index = 1:count
    parentHandle = getSimulinkBlockHandle(parents(index));
    if parentHandle < 0 || ~isKey(indexByHandle, parentHandle)
        continue;
    end
    parentIndex = indexByHandle(parentHandle);
    if types(index) == "PMIOPort"
        physicalLeft(end + 1, 1) = index; %#ok<AGROW>
        physicalRight(end + 1, 1) = parentIndex; %#ok<AGROW>
    elseif types(index) == "Inport"
        signalLeft(end + 1, 1) = parentIndex; %#ok<AGROW>
        signalRight(end + 1, 1) = index; %#ok<AGROW>
    elseif types(index) == "Outport"
        signalLeft(end + 1, 1) = index; %#ok<AGROW>
        signalRight(end + 1, 1) = parentIndex; %#ok<AGROW>
    end
end

physicalKeep = physicalLeft ~= physicalRight;
physicalLeft = physicalLeft(physicalKeep);
physicalRight = physicalRight(physicalKeep);
if isempty(physicalLeft)
    components = (1:count)';
    largest = 1;
    physicalGraph = graph([], [], [], count);
else
    pairs = unique(sort([physicalLeft, physicalRight], 2), "rows");
    physicalGraph = graph(pairs(:, 1), pairs(:, 2), [], count);
    components = conncomp(physicalGraph)';
    sizes = accumarray(components, 1);
    [~, largest] = max(sizes);
end
inLargest = components == largest & physicalPorts > 0;
branchCandidates = inLargest & physicalPorts >= 3;
terminals = inLargest & physicalPorts == 1;

if isempty(signalLeft)
    signalGraph = digraph([], [], [], count);
else
    signalPairs = unique([signalLeft, signalRight], "rows");
    signalGraph = digraph(signalPairs(:, 1), signalPairs(:, 2), [], count);
end
measurementBridges = find(inLargest & signalOutputs > 0);
% A standard Simulink-PS Converter has one conserving port, not two.  It is
% nevertheless the control bridge into the physical network.
controlBridges = find(inLargest & signalInputs > 0 & physicalPorts >= 1);
feedbackPathCount = 0;
for source = measurementBridges'
    if isempty(controlBridges), break; end
    distance = distances(signalGraph, source, controlBridges);
    feedbackPathCount = feedbackPathCount + nnz(isfinite(distance));
end

audit = struct( ...
    "physical_block_count", nnz(physicalPorts > 0), ...
    "largest_connected_physical_component_blocks", nnz(inLargest), ...
    "parallel_or_branching_physical_nodes", nnz(branchCandidates), ...
    "physical_terminal_nodes", nnz(terminals), ...
    "measurement_bridge_nodes", numel(measurementBridges), ...
    "controlled_physical_bridge_nodes", numel(controlBridges), ...
    "measurement_to_control_signal_paths", feedbackPathCount, ...
    "connected_dual_path_gate", ...
        nnz(inLargest) >= 8 && nnz(branchCandidates) >= 2 && ...
        nnz(terminals) >= 2, ...
    "feedback_connectivity_gate", feedbackPathCount >= 1, ...
    "basis", ...
        "conserving-port graph plus directed signal graph across hierarchy");
end

function [left, right] = localLineEdges(index, port, indexByHandle, ...
        left, right, directed)
if nargin < 6, directed = false; end
line = get_param(port, "Line");
if isempty(line) || any(line < 0), return; end
lineFamily = localLineFamily(double(line(:)));
peers = zeros(0, 1);
for lineHandle = lineFamily(:)'
    peers = [peers; localLineBlockHandles(lineHandle)]; %#ok<AGROW>
end
peers = unique(peers);
for peer = peers'
    if peer <= 0 || ~isKey(indexByHandle, peer)
        continue;
    end
    peerIndex = indexByHandle(peer);
    if directed
        left(end + 1, 1) = index; %#ok<AGROW>
        right(end + 1, 1) = peerIndex; %#ok<AGROW>
    else
        left(end + 1, 1) = index; %#ok<AGROW>
        right(end + 1, 1) = peerIndex; %#ok<AGROW>
    end
end
end

function family = localLineFamily(seed)
% Include a branched line's root, siblings and descendants.  Simscape
% conserving connections are frequently represented by nested line
% branches; inspecting only the seed branch loses most physical endpoints.
family = zeros(0, 1);
pending = unique(seed(seed > 0));
while ~isempty(pending)
    current = pending(1);
    pending(1) = [];
    if any(family == current), continue; end
    family(end + 1, 1) = current; %#ok<AGROW>
    relatives = zeros(0, 1);
    for property = ["LineParent", "LineChildren"]
        try
            value = double(get_param(current, property));
            relatives = [relatives; value(:)]; %#ok<AGROW>
        catch
        end
    end
    relatives = relatives(isfinite(relatives) & relatives > 0);
    pending = unique([pending(:); relatives(:)]);
end
end

function handles = localLineBlockHandles(line)
handles = zeros(0, 1);
for property = ["SrcBlockHandle", "DstBlockHandle"]
    try
        value = double(get_param(line, property));
        handles = [handles; value(:)]; %#ok<AGROW>
    catch
    end
end
% Some conserving-line branches expose reliable port handles even when
% their block-handle fields are empty.  Resolve those endpoints as well.
for property = ["SrcPortHandle", "DstPortHandle"]
    try
        ports = double(get_param(line, property));
    catch
        ports = zeros(0, 1);
    end
    for port = ports(:)'
        if ~isfinite(port) || port <= 0, continue; end
        try
            parent = get_param(port, "Parent");
            handle = getSimulinkBlockHandle(parent);
            if handle > 0
                handles(end + 1, 1) = handle; %#ok<AGROW>
            end
        catch
        end
    end
end
handles = unique(handles(isfinite(handles) & handles > 0));
end

function fraction = localConnectedPortFraction(block, field)
ports = get_param(block, "PortHandles");
handles = ports.(field);
connected = false(size(handles));
for index = 1:numel(handles)
    connected(index) = get_param(handles(index), "Line") >= 0;
end
fraction = nnz(connected) / max(numel(connected), 1);
end

function command = localScenarioCommand(sourceRoot, scenario)
variable = string(scenario.source_cycle_variable);
file = fullfile(sourceRoot, "Scripts_Data", variable + ".mat");
assert(isfile(file), "SimuVerity:F90:XMECH03:CycleFile", ...
    "Official source cycle file is missing: %s", file);
loaded = load(file);
assert(isfield(loaded, variable), "SimuVerity:F90:XMECH03:CycleVariable", ...
    "Cycle file does not contain %s.", variable);
cycle = loaded.(variable);
time = double(cycle.time(:));
speed = double(cycle.SpdKph(:));
assert(numel(time) == numel(speed) && numel(time) >= 2 && ...
    all(isfinite(time)) && all(isfinite(speed)) && ...
    all(diff(time) > 0), "SimuVerity:F90:XMECH03:CycleShape", ...
    "Official source cycle is invalid.");
time = time - time(1);
limit = min(double(scenario.maximum_duration_s), time(end));
inside = time < limit;
timeOut = time(inside);
speedOut = speed(inside);
if isempty(timeOut) || timeOut(1) > 0
    timeOut = [0; timeOut]; %#ok<AGROW>
    speedOut = [speed(1); speedOut]; %#ok<AGROW>
end
if timeOut(end) < limit
    speedLimit = interp1(time, speed, limit, "linear");
    timeOut(end + 1, 1) = limit;
    speedOut(end + 1, 1) = speedLimit;
end
command = timeseries(speedOut, timeOut);
command.Name = "speed_command";
end

function simInput = localSimulationInput(model, command, scenario, ...
        isReference, baseline)
mass = double(scenario.vehicle_mass_kg);
capacity = double(scenario.clutch_capacity_scale);
simInput = Simulink.SimulationInput(model);
simInput = simInput.setVariable("speed_command", command);
simInput = simInput.setVariable("vehicle_mass_kg", mass);
simInput = simInput.setVariable("clutch_capacity_scale", capacity);
if isReference
    parameters = baseline;
    parameters.Vehicle.Mass = mass;
    parameters.Clutch.Derating_Factor = capacity;
    selectedCycle = struct( ...
        "time", double(command.Time(:)), ...
        "SpdKph", double(command.Data(:)));
    simInput = simInput.setVariable("DCT_Param", parameters);
    simInput = simInput.setVariable("Drive_Cycle_Num", 7);
    simInput = simInput.setVariable("UrbanCycle7", selectedCycle);
end
simInput = simInput.setModelParameter( ...
    "StopTime", string(double(command.Time(end))), ...
    "ReturnWorkspaceOutputs", "on", ...
    "LimitDataPoints", "off");
end

function outputs = localExtractOutputs(simOut, command, isReference)
stopTime = double(command.Time(end));
grid = (0:0.05:stopTime).';
if abs(grid(end) - stopTime) > 1e-10
    grid(end + 1, 1) = stopTime;
end

if isReference
    commandSeries = localSeries(localGet(simOut, ...
        "f90_xmech03_speed_command"));
    vehicleSeries = localSeries(localGet(simOut, ...
        "f90_xmech03_vehicle_speed"));
    engineSeries = localSeries(localGet(simOut, ...
        "f90_xmech03_engine_speed"));
    gearSeries = localSeries(localGet(simOut, ...
        "f90_xmech03_gear_state"));
    pressureSeries = localSeries(localGet(simOut, ...
        "f90_xmech03_clutch_pressure"));
    slipSeries = localSeries(localGet(simOut, ...
        "f90_xmech03_clutch_slip"));
    torqueSeries = localSeries(localGet(simOut, ...
        "f90_xmech03_torque_demand"));
    outputs = struct;
    outputs.time_s = grid;
    outputs.speed_response = [ ...
        localSample(commandSeries, grid, "linear"), ...
        localSample(vehicleSeries, grid, "linear")];
    outputs.engine_speed = ...
        localSample(engineSeries, grid, "linear");
    outputs.transmission_state = [ ...
        localSample(gearSeries, grid, "previous"), ...
        localSample(pressureSeries, grid, "linear"), ...
        localSample(slipSeries, grid, "linear")];
    outputs.engine_torque_demand = ...
        localSample(torqueSeries, grid, "linear");
else
    speed = localSeries(simuverity_public_output_compatibility( ...
        simOut, "speed_response", 2, AllowBaseWorkspace=true));
    engine = localSeries(simuverity_public_output_compatibility( ...
        simOut, "engine_speed", 1, AllowBaseWorkspace=true));
    transmission = localSeries(simuverity_public_output_compatibility( ...
        simOut, "transmission_state", 5, AllowBaseWorkspace=true));
    torque = localSeries(simuverity_public_output_compatibility( ...
        simOut, "engine_torque_demand", 1, AllowBaseWorkspace=true));
    outputs = struct;
    outputs.time_s = grid;
    outputs.speed_response = localSample(speed, grid, "linear");
    outputs.engine_speed = localSample(engine, grid, "linear");
    outputs.transmission_state = ...
        localSample(transmission, grid, "linear");
    outputs.engine_torque_demand = ...
        localSample(torque, grid, "linear");
end
end

function localValidateOutputs(outputs, stopTime)
requirements = struct( ...
    "speed_response", 2, ...
    "engine_speed", 1, ...
    "transmission_state", 5, ...
    "engine_torque_demand", 1);
fields = string(fieldnames(requirements));
n = numel(outputs.time_s);
assert(n > 1024 && abs(outputs.time_s(1)) <= 1e-9 && ...
    outputs.time_s(end) >= stopTime - 1e-9, ...
    "SimuVerity:F90:XMECH03:TimeCoverage", ...
    "Evidence must be untruncated and cover the complete command interval.");
for index = 1:numel(fields)
    data = outputs.(fields(index));
    assert(size(data, 1) == n && ...
        size(data, 2) == requirements.(fields(index)) && ...
        all(isfinite(data), "all"), ...
        "SimuVerity:F90:XMECH03:OutputContract", ...
        "Output %s has the wrong shape or non-finite values.", ...
        fields(index));
end
end

function value = localGet(simOut, name)
value = [];
try, value = simOut.get(char(name)); catch, end
if isempty(value)
    try
        if evalin("base", "exist('" + name + "','var') == 1")
            value = evalin("base", name);
        end
    catch
    end
end
assert(~isempty(value), "SimuVerity:F90:XMECH03:OutputMissing", ...
    "Required simulation output is missing: %s.", name);
end

function series = localSeries(value)
if isa(value, "Simulink.SimulationData.Signal")
    value = value.Values;
end
assert(isa(value, "timeseries"), "SimuVerity:F90:XMECH03:OutputType", ...
    "Required output is not a Timeseries.");
time = double(value.Time(:));
data = double(value.Data);
data = reshape(data, numel(time), []);
valid = isfinite(time) & all(isfinite(data), 2);
time = time(valid);
data = data(valid, :);
[time, keep] = unique(time, "stable");
data = data(keep, :);
assert(numel(time) >= 2 && all(diff(time) > 0), ...
    "SimuVerity:F90:XMECH03:OutputTime", ...
    "Required Timeseries has no usable time base.");
series = struct("time", time, "data", data);
end

function sampled = localSample(series, grid, method)
assert(series.time(1) <= grid(1) + 1e-6 && ...
    series.time(end) >= grid(end) - 0.1, ...
    "SimuVerity:F90:XMECH03:OutputCoverage", ...
    "A required Timeseries does not cover the complete command interval.");
sampled = interp1(series.time, series.data, grid, method, "extrap");
sampled = reshape(sampled, numel(grid), []);
end

function value = localParam(block, name)
value = "";
try, value = string(get_param(block, name)); catch, end
end

function row = localEmptyScenario
row = struct( ...
    "id", "", ...
    "class", "", ...
    "requested_inputs", struct, ...
    "success", false, ...
    "output_file", "", ...
    "output_file_presence", "", ...
    "samples", 0, ...
    "time_start_s", NaN, ...
    "time_end_s", NaN, ...
    "wall_clock_seconds", NaN, ...
    "started_at", "", ...
    "finished_at", "", ...
    "error", struct);
end

function identity = localRuntimeIdentity
identity = struct( ...
    "matlab_release", string(version("-release")), ...
    "matlab_version", string(version), ...
    "matlab_prefdir", string(getenv("MATLAB_PREFDIR")), ...
    "appdata", string(getenv("APPDATA")), ...
    "temp", string(getenv("TEMP")), ...
    "cache", string(getenv("SIMULINK_CACHE_FOLDER")), ...
    "codegen", string(getenv("SIMULINK_CODEGEN_FOLDER")), ...
    "mcp_port", string(getenv("SIMUVERITY_MCP_PORT")));
end

function value = localError(ME)
value = struct( ...
    "identifier", string(ME.identifier), ...
    "message", string(ME.message));
end

function value = localNow
value = string(datetime("now", "TimeZone", "local", ...
    "Format", "yyyy-MM-dd'T'HH:mm:ssXXX"));
end

function localWriteJson(file, value)
fid = fopen(file, "w", "n", "UTF-8");
assert(fid >= 0, "SimuVerity:F90:XMECH03:JsonWrite", ...
    "Cannot write JSON file: %s", file);
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fwrite(fid, jsonencode(value, PrettyPrint=true), "char");
end

function root = localProjectRoot
root = fileparts(mfilename("fullpath"));
for level = 1:4
    root = fileparts(root);
end
end
