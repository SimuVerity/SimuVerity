function f90_xrobo03_reference_clean_replay_setup(taskId, officialScenariosPath)
%f90_xrobo03_reference_clean_replay_setup Initialize pretrained agent.
arguments
    taskId (1,1) string
    officialScenariosPath (1,1) string
end
assert(taskId == "F90-XROBO-03", ...
    "SimuVerity:ReferenceSetup:TaskMismatch", ...
    "This setup is bound only to F90-XROBO-03.");
assert(isfile(officialScenariosPath), ...
    "SimuVerity:ReferenceSetup:OfficialScenariosMissing", ...
    "Official scenarios are missing: %s", officialScenariosPath);

assetRoot = string(pwd);
initializer = fullfile(assetRoot, "initializeRobotParameters.m");
agentParameters = fullfile(assetRoot, "rlQuadrupedAgentParams.mat");
kinematics = fullfile(assetRoot, "quadrupedInverseKinematics.m");
assert(isfile(initializer) && isfile(agentParameters) && isfile(kinematics) && ...
    localFileIdentity(initializer) == ...
        "present" && ...
    localFileIdentity(agentParameters) == ...
        "present", ...
    "SimuVerity:ReferenceSetup:AssetClosureMismatch", ...
    "The repository-bundled quadruped initialization closure is incomplete or changed.");
addpath(assetRoot, "-begin");
evalin("base", "run('" + replace(initializer, "'", "''") + "')");

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
learned = load(agentParameters, "params");
assert(isfield(learned, "params"), ...
    "SimuVerity:ReferenceSetup:AgentParametersMissing", ...
    "The repository-bundled quadruped learnable parameters are missing.");
setLearnableParameters(agent, learned.params);
assignin("base", "agent", agent);
end

function value = localFileIdentity(pathValue)
assert(isfile(pathValue), "SimuVerity:ReferenceSetup:AssetMissing", ...
    "Required reference asset is missing: %s", pathValue);
value = "present";
end
