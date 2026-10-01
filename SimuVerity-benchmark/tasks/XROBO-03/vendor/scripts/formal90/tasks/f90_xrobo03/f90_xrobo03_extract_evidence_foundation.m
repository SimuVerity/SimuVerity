function evidence = f90_xrobo03_extract_evidence_foundation(modelPath, outDir)
%f90_xrobo03_extract_evidence_foundation Run scenarios and emit score-free evidence.
%
% The exact-file binding direct-golden adapter initializes the documented pretrained
% agent and logs existing native lines in memory. It never saves the model.
% Thresholds, utilities, weights, reductions, and score decisions belong
% only to the Python offline scorer.
arguments
    modelPath (1,1) string
    outDir (1,1) string
end

root = localProjectRoot;
taskRoot = string(getenv("SIMUVERITY_TASK_ROOT"));
officialPath = simuverity_official_scenarios_path();
official = jsondecode(fileread(officialPath));
assetRoot = string(fileparts(modelPath));
referenceModelPath = string(modelPath);
referencePresence = ...
    "present";
runtimeFiles = [ ...
    "initializeRobotParameters.m"; ...
    "quadrupedInverseKinematics.m"; ...
    "rlQuadrupedAgentParams.mat"; ...
    "Extr_Data_Mesh.m"; ...
    "Extr_Data_LinkEndHole.m"];
assert(isfile(modelPath), "SimuVerity:F90:XROBO03:ModelMissing", ...
    "Model under score is missing: %s", modelPath);
if ~isfolder(outDir), mkdir(outDir); end

addpath(fullfile(root, "scripts", "xp9"));
addpath(fullfile(root, "scripts", "formal90", "tasks", ...
    "f90_xrobo03"));
modelPresence = lower(string(xp9_file_presence_file(modelPath)));
evaluationSubject = lower(strtrim(string(getenv( ...
    "SIMUVERITY_EVALUATION_SUBJECT"))));
if strlength(evaluationSubject) == 0, evaluationSubject = "candidate"; end
assert(any(evaluationSubject == ["candidate", "reference"]), ...
    "SimuVerity:F90:XROBO03:EvaluationSubject", ...
    "SIMUVERITY_EVALUATION_SUBJECT must be candidate or reference.");
isDirectReference = evaluationSubject == "reference";
if isDirectReference
    assert(isfile(referenceModelPath) && ...
        all(isfile(fullfile(assetRoot, runtimeFiles))), ...
        "SimuVerity:F90:XROBO03:RuntimeSupportMissing", ...
        "The direct-golden model or required runtime support is missing.");
end
[~, model] = fileparts(modelPath);

evidence = struct;
evidence.schema = "simuverity.f90-xrobo03-evidence.v1";
evidence.formal_id = "F90-XROBO-03";
evidence.design_revision = "rl-quadruped-direct-golden-static";
evidence.policy_id = string(official.score_policy_id);
evidence.metadata = struct( ...
    "purpose", "public benchmark simulation and evidence extraction");
evidence.official_scenarios_file_presence = lower(string( ...
    xp9_file_presence_file(officialPath)));
evidence.model_path = modelPath;
evidence.model_file_presence = modelPresence;
evidence.adapter = "candidate_submission";
if isDirectReference
    evidence.adapter = "reference_direct";
end
evidence.evaluation_subject = evaluationSubject;
evidence.load_pass = false;
evidence.update_pass = false;
evidence.compile_pass = false;
evidence.scenarios = struct([]);
evidence.static_audit = struct;
evidence.errors = struct;
evidence.extraction_only = true;
evidence.contains_score_or_threshold_decisions = false;
evidence.started_at = localNow;
evidence.runtime_identity = struct( ...
    "generation_run_id", string(getenv("SIMUVERITY_GENERATION_RUN_ID")), ...
    "mcp_port", string(getenv("SIMUVERITY_MCP_PORT")), ...
    "matlab_release", string(version("-release")), ...
    "matlab_prefdir", string(getenv("MATLAB_PREFDIR")), ...
    "appdata", string(getenv("APPDATA")), ...
    "temp", string(getenv("TEMP")), ...
    "cache", string(getenv("SIMULINK_CACHE_FOLDER")), ...
    "codegen", string(getenv("SIMULINK_CODEGEN_FOLDER")));

cacheDir = string(getenv("SIMULINK_CACHE_FOLDER"));
codegenDir = string(getenv("SIMULINK_CODEGEN_FOLDER"));
assert(strlength(cacheDir) > 0 && strlength(codegenDir) > 0, ...
    "SimuVerity:F90:XROBO03:Isolation", ...
    "Isolated Simulink cache and codegen folders are required.");
Simulink.fileGenControl("set", "CacheFolder", cacheDir, ...
    "CodeGenFolder", codegenDir, "createDir", true);
set(groot, "defaultFigureVisible", "off");

sourceBindingBefore = "";
sourceBindingAfter = "";
modelClosed = true;
scenarioArtifacts = repmat(struct("id", "", "outputs", struct), ...
    numel(official.scenarios), 1);
try
    if isDirectReference
        sourceBindingBefore = lower(string(xp9_file_presence_file(modelPath)));
        assert(sourceBindingBefore == referencePresence, ...
            "SimuVerity:F90:XROBO03:DirectReferenceIdentity", ...
            "Direct-reference model file binding is not current before extraction.");
        addpath(assetRoot, "-begin");
    end

    load_system(modelPath);
    modelCleanup = onCleanup(@() localCloseModel(model)); %#ok<NASGU>
    evidence.load_pass = true;
    set_param(model, "ReturnWorkspaceOutputs", "on", ...
        "SignalLogging", "on", "SignalLoggingName", "logsout");
    if isDirectReference
        localInitializeDirectReference(assetRoot);
        localEnableDirectLogging(model);
    end

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
    rows = repmat(localEmptyScenarioRow, ...
        numel(official.scenarios), 1);
    for index = 1:numel(official.scenarios)
        scenario = official.scenarios(index);
        rows(index).id = string(scenario.id);
        rows(index).class = string(scenario.class);
        rows(index).requested_inputs = localScenarioInputs(scenario);
        scenarioArtifacts(index).id = string(scenario.id);
        try
            if isDirectReference
                localApplyDirectScenario(scenario);
            else
                localApplyPublicScenario(scenario);
            end
            rows(index).scenario_applied = ...
                localScenarioBindingPass(scenario, isDirectReference);
            simOut = sim(model, ...
                "StartTime", "0", "StopTime", "10", ...
                "ReturnWorkspaceOutputs", "on");
            if isDirectReference
                outputs = localDirectOutputs(simOut);
            else
                outputs = localPublicOutputs(simOut);
            end
            rows(index) = localScenarioMetrics( ...
                rows(index), outputs, scenario);
            scenarioArtifacts(index).outputs = outputs;
        catch ME
            rows(index).valid = false;
            rows(index).simulation_pass = false;
            rows(index).error = localError(ME);
        end
    end
    evidence.scenarios = rows;

    rawPath = fullfile(outDir, "raw_evidence.mat");
    save(rawPath, "scenarioArtifacts", "-v7.3");
    evidence.raw_artifact = struct( ...
        "path", string(rawPath), ...
        "file_presence", lower(string(xp9_file_presence_file(rawPath))), ...
        "format", "MAT-v7.3", ...
        "variable", "scenarioArtifacts");

    if isDirectReference
        modelClosed = localCloseModel(model);
        sourceBindingAfter = lower(string(xp9_file_presence_file(modelPath)));
        evidence.direct_reference_integrity = localIntegrity( ...
            referencePresence, sourceBindingBefore, sourceBindingAfter, modelClosed);
        assert(evidence.direct_reference_integrity.unchanged && ...
            evidence.direct_reference_integrity.closed_without_save, ...
            "SimuVerity:F90:XROBO03:ReferenceIntegrity", ...
            "The direct golden changed or did not close before after-binding.");
    end
catch ME
    evidence.errors.setup_or_extraction = localError(ME);
    if isDirectReference && isfile(modelPath)
        modelClosed = localCloseModel(model);
        sourceBindingAfter = lower(string(xp9_file_presence_file(modelPath)));
        evidence.direct_reference_integrity = localIntegrity( ...
            referencePresence, sourceBindingBefore, sourceBindingAfter, modelClosed);
    end
end

evidence.finished_at = localNow;
evidencePath = fullfile(outDir, "evidence.json");
localWriteJson(evidencePath, evidence);
fprintf("F90_XROBO03_EVIDENCE adapter=%s scenarios=%d path=%s\n", ...
    evidence.adapter, numel(evidence.scenarios), evidencePath);
end

function localInitializeDirectReference(assetRoot)
initializer = fullfile(assetRoot, "initializeRobotParameters.m");
escaped = replace(initializer, "'", "''");
evalin("base", "run('" + escaped + "')");

previousRng = rng;
cleanupRng = onCleanup(@() rng(previousRng)); %#ok<NASGU>
rng(0, "twister");
obsInfo = rlNumericSpec([44 1]);
obsInfo.Name = "observations";
actInfo = rlNumericSpec([8 1], LowerLimit=-1, UpperLimit=1);
actInfo.Name = "torque";
agentOptions = rlDDPGAgentOptions;
agentOptions.SampleTime = evalin("base", "Ts");
agentOptions.MiniBatchSize = 256;
agentOptions.ExperienceBufferLength = 1e6;
agentOptions.MaxMiniBatchPerEpoch = 200;
agentOptions.ActorOptimizerOptions.LearnRate = 1e-3;
agentOptions.ActorOptimizerOptions.GradientThreshold = 1;
agentOptions.CriticOptimizerOptions.LearnRate = 1e-3;
agentOptions.CriticOptimizerOptions.GradientThreshold = 1;
agentOptions.NoiseOptions.StandardDeviation = 0.1;
agentOptions.NoiseOptions.MeanAttractionConstant = 1.0;
initOptions = rlAgentInitializationOptions(NumHiddenUnit=256);
agent = rlDDPGAgent(obsInfo, actInfo, initOptions, agentOptions);
learned = load(fullfile(assetRoot, ...
    "rlQuadrupedAgentParams.mat"), "params");
assert(isfield(learned, "params"), ...
    "SimuVerity:F90:XROBO03:LearnableParameters", ...
    "Current pretrained learnable parameters are unavailable.");
setLearnableParameters(agent, learned.params);
assignin("base", "agent", agent);
end

function localEnableDirectLogging(model)
localMarkLine(model + "/Quadruped Robot", 1, "f90_sensors");
localMarkLine(model + "/RL Agent", 1, "f90_action");
localMarkLine(model + "/Quadruped Robot/Gain", 1, "f90_torque");
localMarkLine(model + "/Reward", 1, "f90_reward");
localMarkLine(model + "/Check If Done", 1, "f90_done");
end

function localMarkLine(block, portIndex, logName)
ports = get_param(block, "PortHandles");
assert(numel(ports.Outport) >= portIndex, ...
    "SimuVerity:F90:XROBO03:NativeLogPort", ...
    "Native logging port is unavailable: %s/%d", block, portIndex);
line = get_param(ports.Outport(portIndex), "Line");
assert(line > 0, "SimuVerity:F90:XROBO03:NativeLogLine", ...
    "Native logging line is unavailable: %s/%d", block, portIndex);
% Signal-logging parameters belong to the source Outport handle in
% R2025a.  The line handle is retained only to prove that the native
% signal is physically connected.
set_param(ports.Outport(portIndex), "DataLogging", "on", ...
    "DataLoggingNameMode", "Custom", ...
    "DataLoggingName", logName);
end

function localApplyDirectScenario(scenario)
inputs = localScenarioInputs(scenario);
names = string(fieldnames(inputs));
for name = names'
    assignin("base", name, double(inputs.(name)));
end

height = double(scenario.initial_body_height_m);
vx = double(scenario.initial_forward_velocity_mps);
vy = double(scenario.initial_vertical_velocity_mps);
mass = double(scenario.torso_mass_kg);
frictionScale = double(scenario.ground_friction_scale);
stiffness = double(scenario.ground_stiffness_npm);
damping = double(scenario.ground_damping_nspm);
torqueLimit = double(scenario.joint_torque_limit_nm);

l1 = evalin("base", "l1");
l2 = evalin("base", "l2");
d2r = evalin("base", "d2r");
angles = d2r * quadrupedInverseKinematics(0, -height, l1, l2);
footHeight = 0.05*l2*(1-sin(2*pi - ...
    (3*pi/2 + angles(1) + angles(2))));
for name = ["init_ang_FL","init_ang_FR","init_ang_RL","init_ang_RR"]
    assignin("base", name, angles);
end
assignin("base", "init_body_height", height);
assignin("base", "y_init", height + footHeight);
assignin("base", "vx_init", vx);
assignin("base", "vy_init", vy);

Lback = evalin("base", "L_back");
torsoMoi = [ ...
    (1/12)*mass*((0.1*Lback)^2 + (0.1*Lback)^2), ...
    (1/12)*mass*(Lback^2 + (0.1*Lback)^2), ...
    (1/12)*mass*(Lback^2 + (0.1*Lback)^2)];
assignin("base", "M", mass);
assignin("base", "torso_MOI", torsoMoi);

muKinetic = 0.88 * frictionScale;
muStatic = 0.90 * frictionScale;
assignin("base", "mu_kinetic", muKinetic);
assignin("base", "mu_static", muStatic);
ground = evalin("base", "ground");
ground.stiffness = stiffness;
ground.damping = damping;
assignin("base", "ground", ground);
assignin("base", "u_max", torqueLimit);

m1 = evalin("base", "m1");
m2 = evalin("base", "m2");
g = evalin("base", "g");
normalForceMax = ((mass + 4*m1 + 4*m2)*abs(g))/4;
assignin("base", "normal_force_max", normalForceMax);
assignin("base", "friction_force_max", ...
    muStatic * normalForceMax);
end

function localApplyPublicScenario(scenario)
inputs = localScenarioInputs(scenario);
names = string(fieldnames(inputs));
for name = names'
    assignin("base", name, double(inputs.(name)));
end
end

function pass = localScenarioBindingPass(scenario, isDirectReference)
inputs = localScenarioInputs(scenario);
names = string(fieldnames(inputs));
pass = true;
for name = names'
    pass = pass && localBaseNumericMatches(name, inputs.(name));
end
if ~pass || ~isDirectReference
    return;
end

height = double(scenario.initial_body_height_m);
mass = double(scenario.torso_mass_kg);
frictionScale = double(scenario.ground_friction_scale);
l1 = evalin("base", "l1");
l2 = evalin("base", "l2");
d2r = evalin("base", "d2r");
angles = d2r * quadrupedInverseKinematics(0, -height, l1, l2);
footHeight = 0.05*l2*(1-sin(2*pi - ...
    (3*pi/2 + angles(1) + angles(2))));
Lback = evalin("base", "L_back");
torsoMoi = [ ...
    (1/12)*mass*((0.1*Lback)^2 + (0.1*Lback)^2), ...
    (1/12)*mass*(Lback^2 + (0.1*Lback)^2), ...
    (1/12)*mass*(Lback^2 + (0.1*Lback)^2)];
muKinetic = 0.88 * frictionScale;
muStatic = 0.90 * frictionScale;
m1 = evalin("base", "m1");
m2 = evalin("base", "m2");
g = evalin("base", "g");
normalForceMax = ((mass + 4*m1 + 4*m2)*abs(g))/4;

for name = ["init_ang_FL","init_ang_FR","init_ang_RL","init_ang_RR"]
    pass = pass && localBaseNumericMatches(name, angles);
end
pass = pass && ...
    localBaseNumericMatches("init_body_height", height) && ...
    localBaseNumericMatches("y_init", height + footHeight) && ...
    localBaseNumericMatches("vx_init", ...
        double(scenario.initial_forward_velocity_mps)) && ...
    localBaseNumericMatches("vy_init", ...
        double(scenario.initial_vertical_velocity_mps)) && ...
    localBaseNumericMatches("M", mass) && ...
    localBaseNumericMatches("torso_MOI", torsoMoi) && ...
    localBaseNumericMatches("mu_kinetic", muKinetic) && ...
    localBaseNumericMatches("mu_static", muStatic) && ...
    localBaseNumericMatches("u_max", ...
        double(scenario.joint_torque_limit_nm)) && ...
    localBaseNumericMatches("normal_force_max", normalForceMax) && ...
    localBaseNumericMatches("friction_force_max", ...
        muStatic * normalForceMax);
if evalin("base", "exist('ground','var') == 1")
    ground = evalin("base", "ground");
    pass = pass && isstruct(ground) && ...
        isfield(ground, "stiffness") && ...
        isfield(ground, "damping") && ...
        localNumericMatches(ground.stiffness, ...
            double(scenario.ground_stiffness_npm)) && ...
        localNumericMatches(ground.damping, ...
            double(scenario.ground_damping_nspm));
else
    pass = false;
end
end

function pass = localBaseNumericMatches(name, expected)
if evalin("base", "exist('" + name + "','var') == 1")
    pass = localNumericMatches(evalin("base", name), expected);
else
    pass = false;
end
end

function pass = localNumericMatches(actual, expected)
pass = isnumeric(actual) && isnumeric(expected) && ...
    numel(actual) == numel(expected) && ...
    all(isfinite(actual), "all") && all(isfinite(expected), "all");
if pass
    actual = double(actual(:));
    expected = double(expected(:));
    tolerance = 1e-12 .* max(1, abs(expected));
    pass = all(abs(actual-expected) <= tolerance);
end
end

function inputs = localScenarioInputs(scenario)
fields = [ ...
    "initial_body_height_m", ...
    "initial_forward_velocity_mps", ...
    "initial_vertical_velocity_mps", ...
    "torso_mass_kg", ...
    "ground_friction_scale", ...
    "ground_stiffness_npm", ...
    "ground_damping_nspm", ...
    "joint_torque_limit_nm"];
inputs = struct;
for field = fields
    inputs.(field) = double(scenario.(field));
end
end

function outputs = localDirectOutputs(simOut)
sensors = localLoggedValue(simOut, "f90_sensors");
[t, pos] = localLeafSeries(sensors, ["body","pos"]);
vel = localResampleLeaf(sensors, ["body","vel"], t);
orient = localResampleLeaf(sensors, ["body","orient"], t);
angvel = localResampleLeaf(sensors, ["body","angvel"], t);
attitude = localOrientationToRpy(orient);
assert(size(pos,2) == 3 && size(vel,2) == 3 && ...
    size(attitude,2) == 3 && size(angvel,2) == 3, ...
    "SimuVerity:F90:XROBO03:NativeBodyShape", ...
    "Native body sensor bus has an unexpected shape.");
outputs.body_state = localSeriesStruct(t, ...
    [pos vel attitude angvel]);

legs = ["leg_FL","leg_FR","leg_RL","leg_RR"];
jointAngles = zeros(numel(t), 8);
jointSpeeds = zeros(numel(t), 8);
normal = zeros(numel(t), 4);
friction = zeros(numel(t), 4);
for index = 1:4
    hipAngle = localResampleLeaf(sensors, ...
        [legs(index),"hip","ang"], t);
    kneeAngle = localResampleLeaf(sensors, ...
        [legs(index),"knee","ang"], t);
    hipSpeed = localResampleLeaf(sensors, ...
        [legs(index),"hip","vel"], t);
    kneeSpeed = localResampleLeaf(sensors, ...
        [legs(index),"knee","vel"], t);
    jointAngles(:,2*index-1:2*index) = ...
        [hipAngle(:,1) kneeAngle(:,1)];
    jointSpeeds(:,2*index-1:2*index) = ...
        [hipSpeed(:,1) kneeSpeed(:,1)];
    normalRaw = localResampleLeaf(sensors, ...
        [legs(index),"foot","Normal_Force"], t);
    frictionRaw = localResampleLeaf(sensors, ...
        [legs(index),"foot","Friction_Force"], t);
    normal(:,index) = localMagnitude(normalRaw);
    friction(:,index) = localMagnitude(frictionRaw);
end
outputs.joint_state = localSeriesStruct(t, ...
    [jointAngles jointSpeeds]);
outputs.contact_state = localSeriesStruct(t, [normal friction]);

[actionTime, action] = localSeries( ...
    localLoggedValue(simOut, "f90_action"));
torque = localResampleSeries( ...
    localLoggedValue(simOut, "f90_torque"), actionTime);
assert(size(action,2) == 8 && size(torque,2) == 8, ...
    "SimuVerity:F90:XROBO03:NativeControlShape", ...
    "Native action or applied-torque vector is not eight-channel.");
outputs.control_state = localSeriesStruct(actionTime, ...
    [action torque]);

try
    [doneTime, done] = localSeries( ...
        localLoggedValue(simOut, "f90_done"));
    outputs.done = localSeriesStruct(doneTime, done(:,1));
catch
    outputs.done = struct;
end
try
    [rewardTime, reward] = localSeries( ...
        localLoggedValue(simOut, "f90_reward"));
    outputs.reward = localSeriesStruct(rewardTime, reward(:,1));
catch
    outputs.reward = struct;
end
end

function outputs = localPublicOutputs(simOut)
names = ["body_state","joint_state","contact_state","control_state"];
channels = [12 16 8 16];
outputs = struct;
for index = 1:numel(names)
    value = simuverity_public_output_compatibility( ...
        simOut, names(index), channels(index), AllowBaseWorkspace=true);
    [t, data] = localSeries(value);
    assert(size(data,2) == channels(index), ...
        "SimuVerity:F90:XROBO03:PublicOutputShape", ...
        "%s has an incorrect channel count.", names(index));
    outputs.(names(index)) = localSeriesStruct(t, data);
end
outputs.done = struct;
outputs.reward = struct;
end

function row = localScenarioMetrics(row, outputs, scenario)
t = outputs.body_state.time;
body = outputs.body_state.data;
localAssertSeries(t, body, 12);
joint = localResampleStruct(outputs.joint_state, t);
contact = localResampleStruct(outputs.contact_state, t);
control = localResampleStruct(outputs.control_state, t);
localAssertSeries(t, joint, 16);
localAssertSeries(t, contact, 8);
localAssertSeries(t, control, 16);
assert(t(1) <= 1e-9 && t(end) >= 10-1e-6, ...
    "SimuVerity:F90:XROBO03:OutputHorizon", ...
    "Public outputs do not span the complete 10 s horizon.");

x = body(:,1);
height = body(:,2);
z = body(:,3);
vx = body(:,4);
roll = body(:,7);
pitch = body(:,8);
yaw = unwrap(body(:,9));
angles = joint(:,1:8);
speeds = joint(:,9:16);
normal = contact(:,1:4);
friction = contact(:,5:8);
actions = control(:,1:8);
torques = control(:,9:16);

row.duration_s = t(end)-t(1);
row.samples = numel(t);
row.forward_displacement_m = x(end)-x(1);
row.mean_forward_speed_mps = localTimeMean(t, vx);
row.positive_forward_fraction = mean(vx > 0);
row.min_body_height_m = min(height);
row.height_ripple_m = localPercentile(height, .95) - ...
    localPercentile(height, .05);
row.max_abs_roll_rad = max(abs(roll));
row.max_abs_pitch_rad = max(abs(pitch));
row.lateral_drift_m = max(abs(z-z(1)));
row.yaw_drift_rad = max(abs(yaw-yaw(1)));
row.body_kinematic_closure_rms_mps = ...
    localRms(gradient(x,t)-vx);
row.joint_angle_max_abs_rad = max(abs(angles), [], "all");
row.joint_speed_max_abs_radps = max(abs(speeds), [], "all");
row.action_max_abs = max(abs(actions), [], "all");
row.action_range = max(max(actions,[],1)-min(actions,[],1));
row.torque_max_abs_nm = max(abs(torques), [], "all");
row.torque_range_nm = max(max(torques,[],1)-min(torques,[],1));
expectedTorque = actions * double(scenario.joint_torque_limit_nm);
row.action_torque_closure_relative_rms = ...
    localRms(torques-expectedTorque) / ...
    max(localRms(torques), 1e-9);
row.control_effort_rms_nm = localRms(torques);
positive = normal > 0;
row.positive_normal_force_fraction_4 = min(mean(positive,1));
transitions = zeros(1,4);
landings = zeros(1,4);
for foot = 1:4
    change = diff(positive(:,foot));
    transitions(foot) = nnz(change ~= 0);
    landings(foot) = nnz(change > 0);
end
row.min_contact_transitions_4 = min(transitions);
row.minimum_landing_count_4 = min(landings);
row.friction_force_rms_n = localRms(friction);
row.done_time_s = row.duration_s;
if isstruct(outputs.done) && isfield(outputs.done, "time")
    done = localResampleStruct(outputs.done, t);
    firstDone = find(done(:,1) > .5, 1, "first");
    if ~isempty(firstDone), row.done_time_s = t(firstDone)-t(1); end
end
row.reward_integral = 0;
if isstruct(outputs.reward) && isfield(outputs.reward, "time")
    reward = localResampleStruct(outputs.reward, t);
    row.reward_integral = trapz(t, reward(:,1));
end

metricNames = string(fieldnames(row));
finitePass = true;
for name = metricNames'
    value = row.(name);
    if isnumeric(value)
        finitePass = finitePass && all(isfinite(value), "all");
    end
end
row.simulation_pass = true;
row.output_contract_pass = true;
row.finite_pass = finitePass;
row.valid = row.simulation_pass && row.output_contract_pass && ...
    row.finite_pass && row.scenario_applied;
end

function audit = localStaticAudit(model)
blocks = string(find_system(model, "FollowLinks", "off", ...
    "LookUnderMasks", "all", "Type", "Block"));
types = strings(size(blocks));
sources = strings(size(blocks));
references = strings(size(blocks));
sourceTypes = strings(size(blocks));
maskTypes = strings(size(blocks));
names = strings(size(blocks));
for index = 1:numel(blocks)
    types(index) = localGet(blocks(index), "BlockType");
    sources(index) = localGet(blocks(index), "SourceBlock");
    references(index) = localGet(blocks(index), "ReferenceBlock");
    sourceTypes(index) = localGet(blocks(index), "SourceType");
    maskTypes(index) = localGet(blocks(index), "MaskType");
    names(index) = localGet(blocks(index), "Name");
end
dynamicTypes = [ ...
    "Integrator","DiscreteIntegrator","StateSpace","TransferFcn", ...
    "UnitDelay","Memory","S-Function","Reference"];
dynamic = ismember(types, dynamicTypes);
% Do not follow library links: following them replaces the task-owned
% Reference instances with library internals and can erase the physical
% block identity.  R2025a exposes that identity primarily through
% SourceBlock/SourceType; ReferenceBlock, MaskType and Name cover other
% equivalent representations.
compactSources = regexprep( ...
    sources + " " + references + " " + sourceTypes + " " + ...
    maskTypes + " " + names, ...
    "\s+", "");
compactNames = regexprep(names, "\s+", "");
physicalJoint = contains(compactSources, "RevoluteJoint", ...
    "IgnoreCase", true) | contains(compactSources, "6-DOFJoint", ...
    "IgnoreCase", true);
contact = contains(compactSources, "SpatialContactForce", ...
    "IgnoreCase", true);
actuator = contains(compactNames, "Actuator", "IgnoreCase", true) & ...
    (contains(compactNames, "Hip", "IgnoreCase", true) | ...
     contains(compactNames, "Knee", "IgnoreCase", true));
sensor = contains(compactNames, "Sensor", "IgnoreCase", true) | ...
    contains(compactSources, "TransformSensor", "IgnoreCase", true);

toWorkspace = blocks(types == "ToWorkspace");
standardNames = ["body_state","joint_state", ...
    "contact_state","control_state"];
standardCount = 0;
constantOutputCount = 0;
for block = toWorkspace'
    variable = localGet(block, "VariableName");
    if any(variable == standardNames)
        standardCount = standardCount + 1;
        ports = get_param(block, "PortHandles");
        line = get_param(ports.Inport(1), "Line");
        if line > 0
            sourcePort = get_param(line, "SrcPortHandle");
            sourceBlock = get_param(sourcePort, "Parent");
            sourceType = string(get_param(sourceBlock, "BlockType"));
            constantOutputCount = constantOutputCount + ...
                double(any(sourceType == ...
                ["Constant","FromWorkspace","SignalBuilder"]));
        end
    end
end
audit = struct( ...
    "block_count", numel(blocks), ...
    "dynamic_block_count", nnz(dynamic), ...
    "physical_joint_count", nnz(physicalJoint), ...
    "spatial_contact_count", nnz(contact), ...
    "actuated_joint_count", nnz(actuator), ...
    "physical_sensor_count", nnz(sensor), ...
    "standard_public_output_count", standardCount, ...
    "constant_or_workspace_output_count", constantOutputCount);
end

function value = localLoggedValue(simOut, name)
logs = simOut.logsout;
assert(isa(logs, "Simulink.SimulationData.Dataset"), ...
    "SimuVerity:F90:XROBO03:Logsout", "logsout is not a Dataset.");
try
    element = logs.getElement(name);
catch
    element = logs.get(name);
end
assert(~isempty(element), "SimuVerity:F90:XROBO03:LoggedElement", ...
    "Required native log is missing: %s", name);
value = element.Values;
end

function [t, data] = localLeafSeries(value, path)
leaf = value;
for field = path
    if isa(leaf, "Simulink.SimulationData.Dataset")
        element = leaf.getElement(field);
        leaf = element.Values;
    elseif isstruct(leaf)
        leaf = leaf.(field);
    else
        leaf = leaf.(field);
    end
end
[t, data] = localSeries(leaf);
end

function data = localResampleLeaf(value, path, targetTime)
[t, source] = localLeafSeries(value, path);
data = localInterpolate(t, source, targetTime);
end

function [t, data] = localSeries(series)
assert(isa(series, "timeseries"), ...
    "SimuVerity:F90:XROBO03:SeriesType", "Expected a Timeseries leaf.");
t = double(series.Time(:));
raw = squeeze(double(series.Data));
if isvector(raw)
    data = raw(:);
elseif size(raw,1) == numel(t)
    data = reshape(raw, numel(t), []);
elseif size(raw,2) == numel(t)
    order = 1:ndims(raw);
    order([1 2]) = [2 1];
    raw = permute(raw, order);
    data = reshape(raw, numel(t), []);
else
    timeDimension = find(size(raw) == numel(t), 1, "first");
    assert(~isempty(timeDimension), "SimuVerity:F90:XROBO03:SeriesShape", ...
        "Timeseries data has no time-sized dimension.");
    order = [timeDimension, setdiff(1:ndims(raw), timeDimension)];
    raw = permute(raw, order);
    data = reshape(raw, numel(t), []);
end
[t, uniqueIndex] = unique(t, "stable");
data = data(uniqueIndex,:);
assert(numel(t) >= 2 && all(isfinite(t)) && ...
    all(isfinite(data), "all"), "SimuVerity:F90:XROBO03:SeriesFinite", ...
    "Timeseries is short or nonfinite.");
end

function data = localResampleSeries(series, targetTime)
[t, source] = localSeries(series);
data = localInterpolate(t, source, targetTime);
end

function data = localResampleStruct(series, targetTime)
data = localInterpolate(series.time, series.data, targetTime);
end

function data = localInterpolate(t, source, targetTime)
assert(t(1) <= targetTime(1)+1e-9 && ...
    t(end) >= targetTime(end)-1e-9, ...
    "SimuVerity:F90:XROBO03:SeriesHorizon", ...
    "A required signal does not cover the common horizon.");
data = interp1(t, source, targetTime, "linear");
assert(all(isfinite(data), "all"), ...
    "SimuVerity:F90:XROBO03:SeriesInterpolation", ...
    "Signal interpolation produced nonfinite values.");
end

function output = localSeriesStruct(t, data)
output = struct("time", double(t(:)), "data", double(data));
end

function rpy = localOrientationToRpy(orientation)
if size(orientation,2) == 3
    rpy = orientation;
    return;
end
assert(size(orientation,2) == 4, ...
    "SimuVerity:F90:XROBO03:OrientationShape", ...
    "Native orientation must contain three angles or four quaternion values.");
q = orientation ./ max(vecnorm(orientation,2,2), eps);
if median(abs(q(:,1))) >= median(abs(q(:,4)))
    qw = q(:,1); qx = q(:,2); qy = q(:,3); qz = q(:,4);
else
    qx = q(:,1); qy = q(:,2); qz = q(:,3); qw = q(:,4);
end
roll = atan2(2*(qw.*qx + qy.*qz), ...
    1-2*(qx.^2 + qy.^2));
pitchArgument = 2*(qw.*qy - qz.*qx);
pitch = asin(max(-1,min(1,pitchArgument)));
yaw = atan2(2*(qw.*qz + qx.*qy), ...
    1-2*(qy.^2 + qz.^2));
rpy = [roll pitch yaw];
end

function value = localMagnitude(data)
if size(data,2) == 1
    value = data(:,1);
else
    value = sqrt(sum(data.^2,2));
end
end

function localAssertSeries(t, data, channels)
assert(numel(t) >= 2 && size(data,1) == numel(t) && ...
    size(data,2) == channels && all(isfinite(t)) && ...
    all(isfinite(data), "all"), ...
    "SimuVerity:F90:XROBO03:OutputContract", ...
    "A required output violates its finite channel contract.");
end

function value = localTimeMean(t, signal)
duration = t(end)-t(1);
value = trapz(t, signal) / max(duration, eps);
end

function value = localRms(input)
value = sqrt(mean(double(input(:)).^2));
end

function value = localPercentile(input, fraction)
values = sort(double(input(:)));
position = 1 + (numel(values)-1)*fraction;
lowerIndex = floor(position);
upperIndex = ceil(position);
if lowerIndex == upperIndex
    value = values(lowerIndex);
else
    weight = position-lowerIndex;
    value = (1-weight)*values(lowerIndex) + ...
        weight*values(upperIndex);
end
end

function row = localEmptyScenarioRow
row = struct( ...
    "id", "", "class", "", "requested_inputs", struct, ...
    "valid", false, "simulation_pass", false, ...
    "output_contract_pass", false, "finite_pass", false, ...
    "scenario_applied", false, ...
    "duration_s", NaN, "samples", 0, ...
    "forward_displacement_m", NaN, ...
    "mean_forward_speed_mps", NaN, ...
    "positive_forward_fraction", NaN, ...
    "min_body_height_m", NaN, ...
    "height_ripple_m", NaN, ...
    "max_abs_roll_rad", NaN, ...
    "max_abs_pitch_rad", NaN, ...
    "lateral_drift_m", NaN, ...
    "yaw_drift_rad", NaN, ...
    "body_kinematic_closure_rms_mps", NaN, ...
    "joint_angle_max_abs_rad", NaN, ...
    "joint_speed_max_abs_radps", NaN, ...
    "action_max_abs", NaN, ...
    "action_range", NaN, ...
    "torque_max_abs_nm", NaN, ...
    "torque_range_nm", NaN, ...
    "action_torque_closure_relative_rms", NaN, ...
    "control_effort_rms_nm", NaN, ...
    "positive_normal_force_fraction_4", NaN, ...
    "min_contact_transitions_4", NaN, ...
    "minimum_landing_count_4", NaN, ...
    "friction_force_rms_n", NaN, ...
    "done_time_s", NaN, ...
    "reward_integral", NaN, ...
    "error", struct);
end

function integrity = localIntegrity(referencePresence, beforePresence, afterPresence, ...
        modelClosed)
identityBindingsComplete = all(strlength( ...
    [referencePresence beforePresence afterPresence]) > 0);
unchanged = identityBindingsComplete && ...
    beforePresence == afterPresence && afterPresence == referencePresence;
integrity = struct( ...
    "expected_file_presence", referencePresence, ...
    "before_file_presence", beforePresence, ...
    "after_file_presence", afterPresence, ...
    "unchanged", logical(unchanged), ...
    "closed_without_save", logical(modelClosed), ...
    "model_saved", false, ...
    "substantive_adjustments", 0);
end

function value = localGet(object, parameter)
try
    value = string(get_param(object, parameter));
catch
    value = "";
end
end

function closed = localCloseModel(model)
closed = true;
try
    if strlength(string(model)) > 0 && bdIsLoaded(model)
        close_system(model, 0);
    end
    closed = strlength(string(model)) == 0 || ~bdIsLoaded(model);
catch
    closed = false;
end
end

function localWriteJson(path, value)
fid = fopen(path, "w", "n", "UTF-8");
assert(fid >= 0, "SimuVerity:F90:XROBO03:EvidenceWrite", ...
    "Cannot write evidence JSON.");
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fwrite(fid, jsonencode(value, PrettyPrint=true), "char");
end

function value = localNow
value = string(datetime("now", "TimeZone", "local", ...
    "Format", "yyyy-MM-dd'T'HH:mm:ssXXX"));
end

function value = localError(ME)
value = struct( ...
    "identifier", string(ME.identifier), ...
    "message", string(ME.message), ...
    "report", string(getReport(ME, "extended", ...
        "hyperlinks", "off")));
end

function root = localProjectRoot
root = fileparts(mfilename("fullpath"));
for level = 1:4
    root = fileparts(root);
end
end
