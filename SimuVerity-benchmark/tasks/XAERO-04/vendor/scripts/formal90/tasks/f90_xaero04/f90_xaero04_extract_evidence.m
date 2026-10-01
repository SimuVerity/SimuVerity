function evidence = f90_xaero04_extract_evidence(modelPath, outDir)
%F90_XAERO04_EXTRACT_EVIDENCE Extract score-free evidence in one session.
arguments
    modelPath (1,1) string = ""
    outDir (1,1) string = ""
end

def = f90_xaero04_definition;
root = localProjectRoot;
official = jsondecode(fileread(def.official_scenarios));
generationRunId = string(getenv("SIMUVERITY_GENERATION_RUN_ID"));
assert(strlength(generationRunId) > 0, "SimuVerity:F90:XAERO04:GenerationRunId", ...
    "SIMUVERITY_GENERATION_RUN_ID is required.");
if strlength(modelPath) == 0, modelPath = def.reference_model; end
assert(isfile(modelPath), "SimuVerity:F90:XAERO04:ModelMissing", ...
    "Model is missing: %s", modelPath);
if strlength(outDir) == 0
    outDir = fullfile(root, "results", "cross_domain", ...
        "simuverity_public", def.formal_id, "fixed_evidence", generationRunId);
end
assert(~isfolder(outDir), "SimuVerity:F90:XAERO04:OutputReuse", ...
    "Output directory already exists: %s", outDir);
mkdir(outDir);

cacheDir = string(getenv("SIMULINK_CACHE_FOLDER"));
codegenDir = string(getenv("SIMULINK_CODEGEN_FOLDER"));
assert(strlength(cacheDir) > 0 && strlength(codegenDir) > 0, ...
    "SimuVerity:F90:XAERO04:Isolation", ...
    "SIMULINK_CACHE_FOLDER and SIMULINK_CODEGEN_FOLDER are required.");
Simulink.fileGenControl("set", "CacheFolder", cacheDir, ...
    "CodeGenFolder", codegenDir, "createDir", true);
set(groot, "defaultFigureVisible", "off");

wallClock = tic;
bindingBefore = localFilePresence(modelPath);
isReference = lower(strtrim(string(getenv("SIMUVERITY_EVALUATION_SUBJECT")))) == "reference";
controllerBindingBefore = "";
plantBindingBefore = "";
if isReference
    controllerBindingBefore = localFilePresence(def.reference_controller);
    plantBindingBefore = localFilePresence(def.reference_plant);
end
evidence = localEmptyEvidence(def, modelPath, bindingBefore, isReference, ...
    generationRunId, cacheDir, codegenDir);
rows = repmat(localEmptyScenario, numel(official.scenarios), 1);
scenarioArtifacts = repmat(struct( ...
    "id", "", "PositionTracking", struct, "TransitionState", struct, ...
    "VehicleState", struct, "ActuatorCommand", struct), ...
    numel(official.scenarios), 1);

oldPath = path;
oldDir = string(pwd);
restore = onCleanup(@() localRestore(oldPath, oldDir)); %#ok<NASGU>
project = [];
model = "";
runtimeConfig = [];
oldConfig = struct;
fatal = [];
try
    if isReference
        project = openProject(def.reference_root);
        load_system(def.reference_model);
        load_system(def.reference_controller);
        load_system(def.reference_plant);
        model = "VTOLTiltrotor";
    else
        [modelDir, modelStem] = fileparts(modelPath);
        addpath(modelDir, "-begin");
        load_system(modelPath);
        model = string(modelStem);
    end
    evidence.load_pass = true;
    runtimeConfig = localRuntimeConfig(model);
    oldConfig = localCaptureConfig(runtimeConfig);
    configCleanup = onCleanup( ...
        @() localRestoreConfig(runtimeConfig, oldConfig)); %#ok<NASGU>
    set_param(runtimeConfig, ...
        "ReturnWorkspaceOutputs", "on", ...
        "SignalLogging", "on", ...
        "LimitDataPoints", "off");
    if isReference, localAttachReferenceTaps(model); end

    localApplyScenario(model, official.scenarios(1), isReference);
    set_param(runtimeConfig, "StopTime", ...
        string(official.scenarios(1).SimulationDuration_s));
    evidence.static_audit = localStaticAudit(model, isReference);
    set_param(model, "SimulationCommand", "update");
    evidence.update_pass = true;
    feval(model, [], [], [], "compile");
    feval(model, [], [], [], "term");
    evidence.compile_pass = true;
    evidence.compile_method = "direct model compile and term";

    for index = 1:numel(official.scenarios)
        scenario = official.scenarios(index);
        rows(index).id = string(scenario.id);
        rows(index).class = string(scenario.class);
        rows(index).requested_inputs = localRequestedInputs(scenario);
        scenarioArtifacts(index).id = string(scenario.id);
        try
            localApplyScenario(model, scenario, isReference);
            set_param(runtimeConfig, "StopTime", ...
                string(scenario.SimulationDuration_s));
            localClearOutputs;
            simulationClock = tic;
            if isReference
                simulationInput = Simulink.SimulationInput(model);
                simulationInput = simulationInput.setVariable( ...
                    "w_trim", localTrimRotorSpeed(scenario.PayloadScale));
                simOut = sim(simulationInput);
            else
                simOut = sim(model);
            end
            rows(index).simulation_wall_clock_s = toc(simulationClock);
            if isReference
                signals = localReferenceSignals(simOut);
            else
                signals = localCandidateSignals(simOut);
            end
            rows(index).simulation_pass = true;
            rows(index).sample_counts = struct( ...
                "PositionTracking", numel(signals.PositionTracking.time), ...
                "TransitionState", numel(signals.TransitionState.time), ...
                "VehicleState", numel(signals.VehicleState.time), ...
                "ActuatorCommand", numel(signals.ActuatorCommand.time));
            rows(index).end_time_s = min([ ...
                signals.PositionTracking.time(end), ...
                signals.TransitionState.time(end), ...
                signals.VehicleState.time(end), ...
                signals.ActuatorCommand.time(end)]);
            rows(index).time_coverage_pass = localTimeCoverage( ...
                signals, double(scenario.SimulationDuration_s));
            rows(index).required_evidence_pass = localSignalsValid(signals);
            rows(index).valid = rows(index).time_coverage_pass && ...
                rows(index).required_evidence_pass;
            [rows(index).metrics, rows(index).profiles] = ...
                localMetrics(signals, scenario);
            scenarioArtifacts(index) = localArtifact(string(scenario.id), signals);
        catch ME
            rows(index).error = localError(ME);
        end
    end
    evidence.scenarios = rows;
    rawPath = fullfile(outDir, "raw_evidence.mat");
    save(rawPath, "scenarioArtifacts", "-v7.3");
    evidence.raw_artifact = struct( ...
        "path", string(rawPath), "format", "MAT-v7.3", ...
        "variable", "scenarioArtifacts");
catch ME
    fatal = ME;
    evidence.errors = localError(ME);
    try, feval(model, [], [], [], "term"); catch, end
end

try
    if strlength(model) > 0 && bdIsLoaded(model)
        close_system(model, 0);
        evidence.model_closed_without_save = true;
    end
    if isReference
        if bdIsLoaded("VTOLAutopilotController")
            close_system("VTOLAutopilotController", 0);
        end
        if bdIsLoaded("VTOLDynamics"), close_system("VTOLDynamics", 0); end
    end
catch ME
    evidence.model_close_error = localError(ME);
end
try
    if ~isempty(project), close(project); end
catch ME
    evidence.project_close_error = localError(ME);
end
evidence.reference_binding_preserved = ...
    (~isReference) || localFilePresence(modelPath) == bindingBefore;
evidence.controller_binding_preserved = ...
    (~isReference) || localFilePresence(def.reference_controller) == controllerBindingBefore;
evidence.plant_binding_preserved = ...
    (~isReference) || localFilePresence(def.reference_plant) == plantBindingBefore;
evidence.finished_at = localNow;
evidence.runtime.wall_clock_s = toc(wallClock);
evidencePath = fullfile(outDir, "evidence.json");
localWriteJson(evidencePath, evidence);
if ~isempty(fatal), rethrow(fatal); end
end

function evidence = localEmptyEvidence(def, modelPath, modelBinding, ...
        isReference, generationRunId, cacheDir, codegenDir)
evidence = struct;
evidence.schema = "simuverity.f90-xaero04-evidence.v1";
evidence.task_id = def.formal_id;
evidence.generation_run_id = generationRunId;
evidence.model_path = modelPath;
evidence.model_file_presence = modelBinding;
evidence.reference_subject = logical(isReference);
evidence.adapter = localTernary(isReference, ...
    "native_vtol_bus_unsaved_taps_and_native_tracking_logs", ...
    "public_timeseries_contract");
evidence.reference_substantive_modifications = 0;
evidence.extraction_only = true;
evidence.contains_score_decisions = false;
evidence.load_pass = false;
evidence.update_pass = false;
evidence.compile_pass = false;
evidence.static_audit = struct;
evidence.scenarios = struct([]);
evidence.errors = struct;
evidence.model_closed_without_save = false;
evidence.reference_binding_preserved = false;
evidence.controller_binding_preserved = false;
evidence.plant_binding_preserved = false;
evidence.started_at = localNow;
evidence.runtime = struct( ...
    "matlab_start_count", 1, ...
    "generation_run_id", generationRunId, ...
    "one_session_all_scenarios", true, ...
    "matlab_release", string(version("-release")), ...
    "matlab_prefdir", string(prefdir), ...
    "appdata", string(getenv("APPDATA")), ...
    "temp", string(getenv("TEMP")), ...
    "cache", cacheDir, ...
    "codegen", codegenDir, ...
    "mcp_port", string(getenv("SIMUVERITY_MCP_PORT")));
end

function row = localEmptyScenario
row = struct( ...
    "id", "", "class", "", "requested_inputs", struct, ...
    "simulation_pass", false, "simulation_wall_clock_s", 0, ...
    "sample_counts", struct, "end_time_s", 0, ...
    "time_coverage_pass", false, ...
    "required_evidence_pass", false, "valid", false, ...
    "metrics", struct, "profiles", struct, "error", struct);
end

function config = localRuntimeConfig(model)
config = getActiveConfigSet(model);
if isa(config, "Simulink.ConfigSetRef"), config = getRefConfigSet(config); end
end

function value = localCaptureConfig(config)
value = struct( ...
    "ReturnWorkspaceOutputs", get_param(config, "ReturnWorkspaceOutputs"), ...
    "SignalLogging", get_param(config, "SignalLogging"), ...
    "LimitDataPoints", get_param(config, "LimitDataPoints"), ...
    "StopTime", get_param(config, "StopTime"));
end

function localRestoreConfig(config, value)
try
    set_param(config, ...
        "ReturnWorkspaceOutputs", value.ReturnWorkspaceOutputs, ...
        "SignalLogging", value.SignalLogging, ...
        "LimitDataPoints", value.LimitDataPoints, ...
        "StopTime", value.StopTime);
catch
end
end

function localApplyScenario(model, scenario, isReference)
names = [ ...
    "MissionKind", "InitialFlightMode", "MissionProfile", ...
    "PayloadScale", "EnableWind", "SimulationDuration_s"];
for index = 1:numel(names)
    name = names(index);
    assignin("base", name, scenario.(char(name)));
end
if ~isReference, return; end

assignin("base", "Visualization", 0);
assignin("base", "SensorType", 0);
assignin("base", "ElectricPropulsion", 0);
assignin("base", "useQGC", 0);
assignin("base", "TuningMode", 0);
assignin("base", "TestMode", 1);
assignin("base", "percWeightGain", double(scenario.PayloadScale));
assignin("base", "Wind", double(logical(scenario.EnableWind)));

profile = double(scenario.MissionProfile);
mission = repmat(struct("mode", 0, "position", zeros(3, 1), ...
    "params", zeros(4, 1)), size(profile, 1), 1);
for index = 1:size(profile, 1)
    mission(index).mode = profile(index, 1);
    mission(index).position = profile(index, 2:4).';
    mission(index).params = profile(index, 5:8).';
end
switch double(scenario.MissionKind)
    case 1
        assignin("base", "guidanceType", 2);
        assignin("base", "HoverMission", mission);
    case 2
        assignin("base", "guidanceType", 3);
        assignin("base", "TransitionMission", mission);
    case 3
        assignin("base", "guidanceType", 1);
        assignin("base", "FixedWingMission", mission);
    otherwise
        error("SimuVerity:F90:XAERO04:MissionKind", "Unsupported MissionKind.");
end
if double(scenario.InitialFlightMode) == 2
    state = flightState.FixedWing;
    initialVelocity = 16;
    initialTilt = pi / 2;
else
    state = flightState.Hover;
    initialVelocity = 0;
    initialTilt = 0;
end
assignin("base", "FSState", state);
assignin("base", "vIni", initialVelocity);
assignin("base", "tiltIni", initialTilt);
set_param("VTOLAutopilotController/Mission", ...
    "PortDimensions", string(size(profile, 1)));
end

function speed = localTrimRotorSpeed(payloadScale)
uavParam = evalin("base", "uavParam");
thrustCoefficient = 4 / pi^3 * 0.1142;
airDensity = 1.225;
rotorRadius = 0.1526;
mass = double(uavParam.geom.mass) * double(payloadScale);
requiredThrustPerRotor = mass * 9.81 / 4;
speed = sqrt(requiredThrustPerRotor / ...
    (thrustCoefficient * airDensity * pi * rotorRadius^4)) / (2 * pi);
end

function localAttachReferenceTaps(model)
prefix = "F90_XAERO04_";
localAddBusVectorTap(model, model + "/Digital Twin", 1, ...
    ["Xe", "Ve", "Euler", "pqr", "airspeed"], ...
    prefix + "Vehicle", "F90_XAERO04_VehicleStateTap", ...
    [1040 60 1210 235]);

motorSelector = model + "/" + prefix + "MotorSelector";
motorMux = model + "/" + prefix + "MotorMux";
surfaceSelector = model + "/" + prefix + "SurfaceSelector";
surfaceMux = model + "/" + prefix + "SurfaceMux";
allMux = model + "/" + prefix + "ActuatorMux";
sink = model + "/" + prefix + "ActuatorSink";
add_block("simulink/Signal Routing/Bus Selector", motorSelector, ...
    "OutputSignals", "w1,w2,w3,w4,Tilt1,Tilt2", ...
    "Position", [1040 280 1050 440]);
add_block("simulink/Signal Routing/Mux", motorMux, ...
    "Inputs", "6", "Position", [1100 290 1105 430]);
add_block("simulink/Signal Routing/Bus Selector", surfaceSelector, ...
    "OutputSignals", "dA,dE,dR,dT", ...
    "Position", [1040 470 1050 580]);
add_block("simulink/Signal Routing/Mux", surfaceMux, ...
    "Inputs", "4", "Position", [1100 475 1105 575]);
add_block("simulink/Signal Routing/Mux", allMux, ...
    "Inputs", "2", "Position", [1160 365 1165 475]);
add_block("simulink/Sinks/To Workspace", sink, ...
    "VariableName", "F90_XAERO04_ActuatorTap", ...
    "SaveFormat", "Timeseries", "MaxDataPoints", "inf", ...
    "Position", [1220 395 1360 425]);
source = get_param(model + "/Autopilot", "PortHandles");
motorPorts = get_param(motorSelector, "PortHandles");
surfacePorts = get_param(surfaceSelector, "PortHandles");
add_line(model, source.Outport(1), motorPorts.Inport(1), "autorouting", "on");
add_line(model, source.Outport(2), surfacePorts.Inport(1), "autorouting", "on");
localConnectOutputs(model, motorSelector, motorMux);
localConnectOutputs(model, surfaceSelector, surfaceMux);
motorMuxPorts = get_param(motorMux, "PortHandles");
surfaceMuxPorts = get_param(surfaceMux, "PortHandles");
allMuxPorts = get_param(allMux, "PortHandles");
sinkPorts = get_param(sink, "PortHandles");
add_line(model, motorMuxPorts.Outport(1), allMuxPorts.Inport(1), ...
    "autorouting", "on");
add_line(model, surfaceMuxPorts.Outport(1), allMuxPorts.Inport(2), ...
    "autorouting", "on");
add_line(model, allMuxPorts.Outport(1), sinkPorts.Inport(1), ...
    "autorouting", "on");
end

function localAddBusVectorTap(model, sourceBlock, sourcePortIndex, ...
        elements, blockStem, variableName, position)
selector = model + "/" + blockStem + "Selector";
mux = model + "/" + blockStem + "Mux";
sink = model + "/" + blockStem + "Sink";
add_block("simulink/Signal Routing/Bus Selector", selector, ...
    "OutputSignals", strjoin(elements, ","), ...
    "Position", position);
add_block("simulink/Signal Routing/Mux", mux, ...
    "Inputs", string(numel(elements)), ...
    "Position", position + [190 0 195 0]);
add_block("simulink/Sinks/To Workspace", sink, ...
    "VariableName", variableName, "SaveFormat", "Timeseries", ...
    "MaxDataPoints", "inf", ...
    "Position", position + [275 55 390 -55]);
source = get_param(sourceBlock, "PortHandles");
selectorPorts = get_param(selector, "PortHandles");
add_line(model, source.Outport(sourcePortIndex), ...
    selectorPorts.Inport(1), "autorouting", "on");
localConnectOutputs(model, selector, mux);
muxPorts = get_param(mux, "PortHandles");
sinkPorts = get_param(sink, "PortHandles");
add_line(model, muxPorts.Outport(1), sinkPorts.Inport(1), ...
    "autorouting", "on");
end

function localConnectOutputs(model, sourceBlock, destinationBlock)
source = get_param(sourceBlock, "PortHandles");
destination = get_param(destinationBlock, "PortHandles");
assert(numel(source.Outport) == numel(destination.Inport), ...
    "SimuVerity:F90:XAERO04:TapWidth", "Tap port count mismatch.");
for index = 1:numel(source.Outport)
    add_line(model, source.Outport(index), destination.Inport(index), ...
        "autorouting", "on");
end
end

function audit = localStaticAudit(model, isReference)
blocks = find_system(model, "LookUnderMasks", "all", ...
    "FollowLinks", "on", "Type", "Block");
types = string(get_param(blocks, "BlockType"));
stateCount = sum(ismember(types, [ ...
    "Integrator", "DiscreteIntegrator", "StateSpace", ...
    "DiscreteStateSpace", "S-Function"]));
modelReferenceCount = sum(types == "ModelReference");
audit = struct;
audit.block_count = numel(blocks);
audit.dynamic_state_block_count = stateCount;
audit.model_reference_count = modelReferenceCount;
if isReference
    audit.full_tiltrotor_mechanism = true;
    audit.closed_loop_feedback_mechanism = true;
    audit.independent_actuator_mechanism = true;
    audit.wind_environment_mechanism = true;
    audit.mission_manager_mechanism = true;
else
    audit.full_tiltrotor_mechanism = ...
        numel(blocks) >= 45 && stateCount >= 3;
    audit.closed_loop_feedback_mechanism = ...
        numel(blocks) >= 35 && stateCount >= 2;
    audit.independent_actuator_mechanism = numel(blocks) >= 35;
    audit.wind_environment_mechanism = numel(blocks) >= 35;
    audit.mission_manager_mechanism = numel(blocks) >= 35;
end
audit.minimum_dynamic_vtol_signature = ...
    audit.full_tiltrotor_mechanism && ...
    audit.closed_loop_feedback_mechanism && ...
    audit.independent_actuator_mechanism && ...
    audit.mission_manager_mechanism;
end

function signals = localReferenceSignals(simOut)
signals = struct;
signals.PositionTracking = localSignal( ...
    localGetOutput(simOut, "PositionCmdFdbk"), 6, "PositionTracking");
signals.TransitionState = localSignal( ...
    localGetOutput(simOut, "TransitionFeedback"), 4, "TransitionState");
signals.VehicleState = localSignal( ...
    localGetOutput(simOut, "F90_XAERO04_VehicleStateTap"), 13, ...
    "VehicleState");
signals.ActuatorCommand = localSignal( ...
    localGetOutput(simOut, "F90_XAERO04_ActuatorTap"), 10, ...
    "ActuatorCommand");
end

function signals = localCandidateSignals(simOut)
signals = struct;
signals.PositionTracking = localSignal( ...
    simuverity_public_output_compatibility(simOut, "PositionTracking", 6, ...
        AllowBaseWorkspace=true), 6, "PositionTracking");
signals.TransitionState = localSignal( ...
    simuverity_public_output_compatibility(simOut, "TransitionState", 4, ...
        AllowBaseWorkspace=true), 4, "TransitionState");
signals.VehicleState = localSignal( ...
    simuverity_public_output_compatibility(simOut, "VehicleState", 13, ...
        AllowBaseWorkspace=true), 13, "VehicleState");
signals.ActuatorCommand = localSignal( ...
    simuverity_public_output_compatibility(simOut, "ActuatorCommand", 10, ...
        AllowBaseWorkspace=true), 10, "ActuatorCommand");
end

function value = localGetOutput(simOut, name)
value = [];
try, value = simOut.get(name); catch, end
if isempty(value)
    exists = evalin("base", sprintf("exist('%s','var')", name));
    if exists, value = evalin("base", name); end
end
assert(~isempty(value), "SimuVerity:F90:XAERO04:MissingOutput", ...
    "Required output %s is missing.", name);
end

function signal = localSignal(value, channels, name)
if isa(value, "Simulink.SimulationData.Signal")
    value = value.Values;
end
if isa(value, "timeseries")
    time = double(value.Time(:));
    data = value.Data;
elseif isstruct(value) && isfield(value, "time") && isfield(value, "signals")
    time = double(value.time(:));
    data = value.signals.values;
elseif isstruct(value) && isfield(value, "Time") && isfield(value, "Data")
    time = double(value.Time(:));
    data = value.Data;
else
    error("SimuVerity:F90:XAERO04:OutputType", ...
        "Required output %s is not a Timeseries-compatible value.", name);
end
data = localNormalizeData(data, numel(time), channels, name);
[time, uniqueIndex] = unique(time, "stable");
data = data(uniqueIndex, :);
signal = struct("time", time, "data", data);
end

function data = localNormalizeData(data, sampleCount, channels, name)
data = double(data);
dimensions = size(data);
timeDimension = find(dimensions == sampleCount, 1, "last");
if isempty(timeDimension)
    if isvector(data) && channels == 1 && numel(data) == sampleCount
        data = data(:);
    else
        error("SimuVerity:F90:XAERO04:OutputShape", ...
            "%s has no dimension matching its time vector.", name);
    end
else
    order = [timeDimension, setdiff(1:ndims(data), timeDimension, "stable")];
    data = permute(data, order);
    data = reshape(data, sampleCount, []);
end
assert(size(data, 2) == channels, "SimuVerity:F90:XAERO04:OutputChannels", ...
    "%s must contain %d channels; found %d.", ...
    name, channels, size(data, 2));
end

function pass = localSignalsValid(signals)
names = ["PositionTracking", "TransitionState", ...
    "VehicleState", "ActuatorCommand"];
pass = true;
for index = 1:numel(names)
    signal = signals.(names(index));
    pass = pass && numel(signal.time) >= 20 && ...
        all(isfinite(signal.time)) && ...
        all(diff(signal.time) > 0) && ...
        all(isfinite(signal.data), "all");
end
end

function pass = localTimeCoverage(signals, duration)
names = ["PositionTracking", "TransitionState", ...
    "VehicleState", "ActuatorCommand"];
pass = true;
minimumCompleteTrace = min(5.0, duration);
for index = 1:numel(names)
    signal = signals.(names(index));
    pass = pass && signal.time(1) <= 0.05 && ...
        signal.time(end) >= minimumCompleteTrace - 0.05;
end
end

function [metrics, profiles] = localMetrics(signals, scenario)
startTime = max([ ...
    signals.PositionTracking.time(1), signals.TransitionState.time(1), ...
    signals.VehicleState.time(1), signals.ActuatorCommand.time(1)]);
endTime = min([ ...
    signals.PositionTracking.time(end), signals.TransitionState.time(end), ...
    signals.VehicleState.time(end), signals.ActuatorCommand.time(end)]);
time = linspace(startTime, endTime, 601).';
position = interp1(signals.PositionTracking.time, ...
    signals.PositionTracking.data, time, "linear", "extrap");
transition = interp1(signals.TransitionState.time, ...
    signals.TransitionState.data, time, "linear", "extrap");
vehicle = interp1(signals.VehicleState.time, ...
    signals.VehicleState.data, time, "linear", "extrap");
actuator = interp1(signals.ActuatorCommand.time, ...
    signals.ActuatorCommand.data, time, "linear", "extrap");

command = position(:, 1:3);
measured = position(:, 4:6);
errorNorm = vecnorm(command - measured, 2, 2);
tail = time >= startTime + 0.80 * (endTime - startTime);
middle = time >= startTime + 0.25 * (endTime - startTime);
altitude = -vehicle(:, 3);
attitude = vehicle(:, 7:9);
bodyRate = vehicle(:, 10:12);
airspeed = vehicle(:, 13);
pathTravel = sum(vecnorm(diff(vehicle(:, 1:3), 1, 1), 2, 2));

actuatorRange = max(actuator, [], 1) - min(actuator, [], 1);
actuatorScale = max(max(abs(actuator), [], 1), 1e-6);
dynamicChannels = actuatorRange > max(0.005 * actuatorScale, 1e-5);
normalizedActuator = (actuator - min(actuator, [], 1)) ./ ...
    max(actuatorRange, 1e-9);
edgeResidence = mean( ...
    normalizedActuator <= 0.01 | normalizedActuator >= 0.99, "all");
normalizedStep = abs(diff(actuator, 1, 1)) ./ max(actuatorRange, 1e-9);
velocityStep = vecnorm(diff(vehicle(:, 4:6), 1, 1), 2, 2);

transitionAirspeed = transition(:, 1);
frontTilt = transition(:, 2);
transitionAltitude = transition(:, 4);
early = time <= startTime + 0.15 * (endTime - startTime);
late = time >= startTime + 0.60 * (endTime - startTime);
airspeedGain = max(transitionAirspeed(late)) - median(transitionAirspeed(early));
maximumAltitude = max(transitionAltitude);
retained = find(transitionAltitude >= 0.75 * maximumAltitude, 1, "first");
if isempty(retained)
    altitudeLoss = max(transitionAltitude) - min(transitionAltitude);
else
    altitudeLoss = max(0, maximumAltitude - min(transitionAltitude(retained:end)));
end

peakError = max(errorNorm(middle));
tailError = sqrt(mean(errorNorm(tail).^2));
recovery = 1 - tailError / max(peakError, 1e-6);
commandDifference = vecnorm(command - measured, 2, 2);
metrics = struct;
metrics.all_values_finite = all(isfinite([ ...
    position(:); transition(:); vehicle(:); actuator(:)]));
metrics.position_error_rms_m = sqrt(mean(errorNorm.^2));
metrics.tail_position_error_rms_m = tailError;
metrics.terminal_position_error_m = errorNorm(end);
metrics.maximum_position_error_m = max(errorNorm);
metrics.command_copy_fraction = mean(commandDifference < 1e-7);
metrics.command_path_travel_m = ...
    sum(vecnorm(diff(command, 1, 1), 2, 2));
metrics.path_travel_m = pathTravel;
metrics.maximum_altitude_m = max(altitude);
metrics.minimum_altitude_m = min(altitude);
metrics.final_altitude_m = altitude(end);
metrics.maximum_airspeed_mps = max(airspeed);
metrics.final_airspeed_mps = airspeed(end);
metrics.maximum_abs_attitude_rad = max(abs(attitude), [], "all");
metrics.maximum_abs_body_rate_radps = max(abs(bodyRate), [], "all");
metrics.velocity_step_p99_mps = localPercentile(velocityStep, 99);
metrics.dynamic_actuator_channel_fraction = mean(dynamicChannels);
metrics.actuator_normalized_step_p99 = ...
    localPercentile(normalizedStep(:), 99);
metrics.actuator_edge_residence_fraction = edgeResidence;
metrics.front_tilt_pair_rms_difference = ...
    sqrt(mean((actuator(:, 5) - actuator(:, 6)).^2));
metrics.rotor_cross_channel_spread = ...
    mean(std(actuator(:, 1:4), 0, 2) ./ ...
    max(mean(abs(actuator(:, 1:4)), 2), 1e-6));
metrics.tracking_recovery_fraction = recovery;
metrics.front_tilt_range_rad = max(frontTilt) - min(frontTilt);
metrics.transition_airspeed_gain_mps = airspeedGain;
metrics.transition_altitude_loss_m = altitudeLoss;
metrics.transition_maximum_pitch_rad = max(abs(transition(:, 3)));
metrics.scenario_duration_s = double(scenario.SimulationDuration_s);

profiles = struct;
profiles.position = localProfile(measured, 120);
profiles.vehicle = localProfile(vehicle, 120);
profiles.actuator = localProfile(actuator, 120);
profiles.transition = localProfile(transition, 120);
end

function profile = localProfile(data, count)
source = linspace(0, 1, size(data, 1)).';
target = linspace(0, 1, count).';
profile = interp1(source, data, target, "linear");
end

function value = localPercentile(data, percentile)
data = sort(double(data(isfinite(data))));
if isempty(data), value = inf; return; end
index = 1 + (numel(data) - 1) * percentile / 100;
lowerIndex = floor(index);
upperIndex = ceil(index);
if lowerIndex == upperIndex
    value = data(lowerIndex);
else
    fraction = index - lowerIndex;
    value = data(lowerIndex) * (1 - fraction) + data(upperIndex) * fraction;
end
end

function requested = localRequestedInputs(scenario)
requested = struct( ...
    "MissionKind", double(scenario.MissionKind), ...
    "InitialFlightMode", double(scenario.InitialFlightMode), ...
    "MissionProfile", double(scenario.MissionProfile), ...
    "PayloadScale", double(scenario.PayloadScale), ...
    "EnableWind", logical(scenario.EnableWind), ...
    "SimulationDuration_s", double(scenario.SimulationDuration_s));
end

function artifact = localArtifact(id, signals)
artifact = struct( ...
    "id", id, ...
    "PositionTracking", signals.PositionTracking, ...
    "TransitionState", signals.TransitionState, ...
    "VehicleState", signals.VehicleState, ...
    "ActuatorCommand", signals.ActuatorCommand);
end

function localClearOutputs
names = [ ...
    "PositionCmdFdbk", "TransitionFeedback", ...
    "F90_XAERO04_VehicleStateTap", "F90_XAERO04_ActuatorTap", ...
    "PositionTracking", "TransitionState", ...
    "VehicleState", "ActuatorCommand"];
for index = 1:numel(names)
    evalin("base", "clear " + names(index));
end
end

function binding = localFilePresence(pathValue)
assert(isfile(pathValue), "SimuVerity:FileMissing", "Required file is missing: %s", pathValue);
binding = "present";
end

function value = localError(ME)
value = struct("identifier", string(ME.identifier), ...
    "message", string(ME.message), ...
    "stack", string({ME.stack.name}));
end

function value = localNow
value = string(datetime("now", ...
    "TimeZone", "Asia/Shanghai", ...
    "Format", "yyyy-MM-dd'T'HH:mm:ssXXX"));
end

function localWriteJson(pathValue, value)
fid = fopen(pathValue, "w", "n", "UTF-8");
assert(fid >= 0, "SimuVerity:F90:XAERO04:JsonOpen", ...
    "Could not open JSON output.");
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, "%s\n", jsonencode(value, PrettyPrint=true));
end

function value = localTernary(condition, yesValue, noValue)
if condition, value = yesValue; else, value = noValue; end
end

function root = localProjectRoot
root = fileparts(mfilename("fullpath"));
for level = 1:4
    root = fileparts(root);
end
end

function localRestore(oldPath, oldDir)
try, path(oldPath); catch, end
try, cd(oldDir); catch, end
end
