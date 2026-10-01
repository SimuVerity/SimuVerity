function result = f90_xaero02_extract_reference_evidence(modelPath, outputRoot, officialScenarios, evaluatorAssetRoot)
% Extract complete fixed reference evidence from the public asset closure.

modelPath = string(modelPath);
outputRoot = string(outputRoot);
runtimeRoot = string(evaluatorAssetRoot);
assert(isfolder(runtimeRoot), "SimuVerity:XAERO02:MissingAssetRoot", ...
    "Evaluator-owned reference asset root is absent: %s", runtimeRoot);
model = "AirplaneSimModel_LindiPlane";
boundModelPath = fullfile(runtimeRoot, "Plane", "models", model + ".slx");
assert(isfile(boundModelPath), "SimuVerity:XAERO02:MissingModel", ...
    "Reference model is absent from the evaluator asset root.");
assert(localFilePresence(modelPath) == localFilePresence(boundModelPath), ...
    "SimuVerity:XAERO02:ReferenceAliasIdentity", ...
    "The staged reference alias differs from the asset-root entrypoint.");
scenarioContract = localOfficialScenarios(officialScenarios);
scenarios = scenarioContract.scenarios;
scoringRunId = strtrim(string(getenv("SIMUVERITY_SCORING_RUN_ID")));
assert(strlength(scoringRunId) > 0, "SimuVerity:XAERO02:ScoringRunIdRequired", ...
    "Reference extraction requires a fresh SimuVerity ScoringRunId.");

if isfolder(outputRoot)
    error("SimuVerity:XAERO02:OutputExists", "Fresh output root already exists: %s", outputRoot);
end
mkdir(outputRoot);
diary(fullfile(outputRoot, "extractor.log"));
cleanupDiary = onCleanup(@() diary("off")); %#ok<NASGU>

oldPath = path;
pathCleanup = onCleanup(@() path(oldPath)); %#ok<NASGU>
restoredefaultpath;
funrayRoot = fullfile(runtimeRoot, "Plane", "Funray");
assert(isfolder(funrayRoot), "SimuVerity:XAERO02:MissingFunrayRoot", ...
    "Evaluator-owned Plane/Funray closure is absent: %s", funrayRoot);
addpath(funrayRoot, "-begin");
scratchRoot = string(tempname);
assert(~isfolder(scratchRoot), "SimuVerity:XAERO02:ScratchExists", ...
    "Fresh evaluator scratch path already exists: %s", scratchRoot);
mkdir(scratchRoot);
scratchCleanup = onCleanup(@() localRemoveTree(scratchRoot)); %#ok<NASGU>
cacheDir = fullfile(scratchRoot, "c");
codegenDir = fullfile(scratchRoot, "g");
mkdir(cacheDir); mkdir(codegenDir);
Simulink.fileGenControl("set", "CacheFolder", cacheDir, ...
    "CodeGenFolder", codegenDir, "createDir", true);

assignin("base", "TEST_LADAC", true);
initPath = fullfile(runtimeRoot, "Plane", "Funray", "init_Funray_LindiPlane.m");
assert(isfile(initPath), "SimuVerity:XAERO02:MissingInit", "Reference initializer is absent.");
evalin("base", "run('" + replace(initPath, "\", "/") + "')");

load_system(model);
cleanupModel = onCleanup(@() localClose(model)); %#ok<NASGU>
loadPass = true;
tapNames = localAddTaps(model);
set_param(model, "SimulationCommand", "update");
updatePass = true;
feval(model, [], [], [], "compile");
compilePass = true;
feval(model, [], [], [], "term");

baseWaypoints = evalin("base", "waypoints");
baseAirplane = evalin("base", "airplane");
center = mean(baseWaypoints, 2);
grid = (0:0.2:60).';
scenarioCells = cell(1, numel(scenarios));
suiteTimer = tic;

for index = 1:numel(scenarios)
    scenario = scenarios(index);
    waypoints = center + double(scenario.waypoint_scale) .* (baseWaypoints - center);
    airplane = baseAirplane;
    airplane.ic.V_Kb = [double(scenario.initial_airspeed_mps); 0; 0];
    assignin("base", "waypoints", waypoints);
    assignin("base", "airplane", airplane);
    set_param(model + "/Environment/Gain", "Gain", ...
        sprintf("%.17g", double(scenario.crosswind_step_mps) / 9.0));
    timer = tic;
    out = sim(model, "StopTime", "60", "ReturnWorkspaceOutputs", "on");
    wallSeconds = toc(timer);
    names = string(out.who);
    missing = setdiff(tapNames, names);
    assert(isempty(missing), "SimuVerity:XAERO02:MissingRuntimeTap", ...
        "Scenario %s is missing runtime taps: %s", scenario.id, strjoin(missing, ","));
    signals = localExtract(out, grid);
    valid = localFiniteSignals(signals) && ...
        size(signals.flight_state,2) == 10 && ...
        size(signals.tracking_state,2) == 7 && ...
        size(signals.actuator_state,2) == 8;
    assert(valid, "SimuVerity:XAERO02:InvalidEvidence", ...
        "Scenario %s evidence is invalid.", scenario.id);
    scenarioCells{index} = localScenarioEvidence(scenario, grid, signals, wallSeconds);
    fprintf("XAERO02_SCENARIO_PASS|%s|WALL=%.6f\n", scenario.id, wallSeconds);
end

scenarioEvidence = [scenarioCells{:}];
evidence = struct();
evidence.schema = "simuverity.formal90-xaero02-evidence.v1";
evidence.task_id = "F90-XAERO-02";
evidence.scoring_run_id = char(scoringRunId);
evidence.evidence_complete = true;
evidence.matlab_release = version("-release");
evidence.reference_source_modified_or_saved = false;
evidence.reference_model_file_presence = localFilePresence(boundModelPath);
evidence.load_pass = loadPass;
evidence.update_pass = updatePass;
evidence.compile_pass = compilePass;
evidence.simulate_pass = all([scenarioEvidence.simulate_pass]);
evidence.all_official_evidence_valid = all([scenarioEvidence.valid]);
evidence.scenario_count = numel(scenarioEvidence);
evidence.grid_step_s = 0.2;
evidence.suite_wall_seconds = toc(suiteTimer);
evidence.measurement_policy = ...
    "Evaluator-only in-memory To Workspace branches; source model never saved";
evidence.scenarios = scenarioEvidence;

save(fullfile(outputRoot, "evidence_complete.mat"), "evidence", "-v7.3");
fid = fopen(fullfile(outputRoot, "evidence.json"), "w", "n", "UTF-8");
assert(fid >= 0, "Unable to create evidence JSON.");
cleanupFile = onCleanup(@() fclose(fid)); %#ok<NASGU>
fwrite(fid, jsonencode(evidence, PrettyPrint=true), "char");
fwrite(fid, newline, "char");
fprintf("XAERO02_EVIDENCE_COMPLETE=1\n");
fprintf("SUITE_WALL_SECONDS=%.6f\n", evidence.suite_wall_seconds);
result = evidence;
end

function contract = localOfficialScenarios(value)
if isstruct(value)
    contract = value;
else
    scenarioPath = string(value);
    assert(isfile(scenarioPath), "SimuVerity:XAERO02:OfficialScenariosMissing", ...
        "Official scenarios are absent: %s", scenarioPath);
    contract = jsondecode(fileread(scenarioPath));
end
assert(string(contract.task_id) == "F90-XAERO-02" && ...
    isfield(contract, "scenarios") && numel(contract.scenarios) == 5, ...
    "SimuVerity:XAERO02:OfficialScenarioContract", ...
    "The public official scenario contract is invalid.");
required = ["id", "waypoint_scale", "crosswind_step_mps", ...
    "initial_airspeed_mps"];
assert(all(isfield(contract.scenarios, required)), ...
    "SimuVerity:XAERO02:OfficialScenarioFields", ...
    "An official scenario is missing a required input field.");
end

function item = localScenarioEvidence(scenario, grid, signals, wallSeconds)
item = struct();
item.id = char(scenario.id);
item.input = struct( ...
    "waypoint_scale", scenario.waypoint_scale, ...
    "crosswind_step_mps", scenario.crosswind_step_mps, ...
    "initial_airspeed_mps", scenario.initial_airspeed_mps);
item.simulate_pass = true;
item.valid = true;
item.wall_seconds = wallSeconds;
item.logs = struct();
item.logs.flight_state = localLog(grid, signals.flight_state, ...
    {"position_x_m","position_y_m","position_z_m", ...
     "velocity_x_mps","velocity_y_mps","velocity_z_mps", ...
     "body_rate_p_radps","body_rate_q_radps","body_rate_r_radps","airspeed_mps"}, ...
    {"m","m","m","m/s","m/s","m/s","rad/s","rad/s","rad/s","m/s"});
item.logs.tracking_state = localLog(grid, signals.tracking_state, ...
    {"reference_position_x_m","reference_position_y_m","reference_position_z_m", ...
     "tracking_error_x_m","tracking_error_y_m","tracking_error_z_m","active_waypoint_index"}, ...
    {"m","m","m","m","m","m","1"});
item.logs.actuator_state = localLog(grid, signals.actuator_state, ...
    {"left_aileron_deflection_rad","right_aileron_deflection_rad", ...
     "left_elevator_deflection_rad","right_elevator_deflection_rad", ...
     "rudder_deflection_rad","horizontal_tail_trim_rad", ...
     "left_motor_angular_speed_radps","right_motor_angular_speed_radps"}, ...
    {"rad","rad","rad","rad","rad","rad","rad/s","rad/s"});
end

function log = localLog(grid, data, channels, units)
log = struct();
log.format = "Timeseries";
log.channels = channels;
log.units = units;
log.time = grid;
log.data = data;
end

function names = localAddTaps(model)
demux = model + "/Output demux";
localTapPort(demux, 2, "xaero02_body_rate_radps", 1);
localTapPort(demux, 3, "xaero02_position_m", 2);
localTapPort(demux, 4, "xaero02_velocity_mps", 3);
localTapPort(demux, 6, "xaero02_airspeed_mps", 4);
scopeRoot = model + "/scopes";
trackingSelector = localSelector(scopeRoot, "pos_control.reference.s_g_ref");
localTapPort(trackingSelector, 1, "xaero02_reference_position_m", 1);
localTapPort(trackingSelector, 2, "xaero02_measured_position_m", 2);
errorSelector = localSelector(scopeRoot, "pos_control.error.e_s_g");
localTapPort(errorSelector, 1, "xaero02_tracking_error_m", 3);
localTapPort(errorSelector, 2, "xaero02_waypoint_index", 4);
actuatorRoot = model + "/scopes/actuator scopes";
actuatorSelector = localSelector(actuatorRoot, "aileronsBus.deflection_in_rad");
localTapPort(actuatorSelector, 1, "xaero02_aileron_rad", 1);
localTapPort(actuatorSelector, 2, "xaero02_elevator_rad", 2);
localTapPort(actuatorSelector, 3, "xaero02_rudder_rad", 3);
localTapPort(actuatorSelector, 4, "xaero02_trim_rad", 4);
localTapPort(actuatorSelector, 5, "xaero02_motor_radps", 5);
names = ["xaero02_body_rate_radps", "xaero02_position_m", ...
    "xaero02_velocity_mps", "xaero02_airspeed_mps", ...
    "xaero02_reference_position_m", "xaero02_measured_position_m", ...
    "xaero02_tracking_error_m", "xaero02_waypoint_index", ...
    "xaero02_aileron_rad", "xaero02_elevator_rad", "xaero02_rudder_rad", ...
    "xaero02_trim_rad", "xaero02_motor_radps"];
end

function block = localSelector(system, token)
blocks = string(find_system(system, "LookUnderMasks", "all", ...
    "FollowLinks", "on", "BlockType", "BusSelector"));
block = "";
for index = 1:numel(blocks)
    if contains(string(get_param(blocks(index), "OutputSignals")), token)
        block = blocks(index);
        break;
    end
end
assert(strlength(block) > 0, "Unable to find source selector for %s", token);
end

function localTapPort(block, index, name, verticalIndex)
ports = get_param(block, "PortHandles");
sourcePort = ports.Outport(index);
parent = string(get_param(block, "Parent"));
tap = parent + "/__" + name;
position = [20, 20 + 42 * verticalIndex, 135, 40 + 42 * verticalIndex];
add_block("simulink/Sinks/To Workspace", tap, ...
    "VariableName", name, "SaveFormat", "Timeseries", ...
    "MaxDataPoints", "inf", "Position", position);
tapPorts = get_param(tap, "PortHandles");
add_line(parent, sourcePort, tapPorts.Inport, "autorouting", "on");
end

function signals = localExtract(out, grid)
position = localSeries(out, "xaero02_position_m", grid);
velocity = localSeries(out, "xaero02_velocity_mps", grid);
bodyRates = localSeries(out, "xaero02_body_rate_radps", grid);
airspeed = localSeries(out, "xaero02_airspeed_mps", grid);
reference = localSeries(out, "xaero02_reference_position_m", grid);
trackingError = localSeries(out, "xaero02_tracking_error_m", grid);
waypointIndex = localSeries(out, "xaero02_waypoint_index", grid, "previous");
aileron = localSeries(out, "xaero02_aileron_rad", grid);
elevator = localSeries(out, "xaero02_elevator_rad", grid);
rudder = localSeries(out, "xaero02_rudder_rad", grid);
trim = localSeries(out, "xaero02_trim_rad", grid);
motor = localSeries(out, "xaero02_motor_radps", grid);
signals = struct();
signals.flight_state = [position, velocity, bodyRates, airspeed];
signals.tracking_state = [reference, trackingError, waypointIndex];
signals.actuator_state = [aileron, elevator, rudder, trim, motor];
end

function data = localSeries(out, name, grid, method)
if nargin < 4, method = "linear"; end
ts = out.get(name);
assert(isa(ts, "timeseries"), "Runtime tap %s is not a timeseries", name);
time = double(ts.Time(:));
data = squeeze(double(ts.Data));
if isvector(data) && numel(data) == numel(time)
    data = reshape(data, numel(time), 1);
elseif size(data,1) ~= numel(time) && size(data,2) == numel(time)
    data = data.';
end
assert(size(data,1) == numel(time), "Time dimension mismatch for %s", name);
data = interp1(time, data, grid, method, "extrap");
end

function valid = localFiniteSignals(signals)
fields = fieldnames(signals);
valid = true;
for index = 1:numel(fields)
    value = signals.(fields{index});
    valid = valid && ~isempty(value) && all(isfinite(value), "all");
end
end

function value = localFilePresence(pathValue)
assert(isfile(pathValue), "SimuVerity:FileMissing", "Required file is missing: %s", pathValue);
value = "present";
end

function localClose(model)
try, close_system(model, 0); catch, end
end

function localRemoveTree(pathValue)
if isfolder(pathValue), rmdir(pathValue, "s"); end
end
