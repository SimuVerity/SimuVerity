function f90_xrobo08_reference_clean_replay_setup(taskId, officialScenariosPath, model)
%f90_xrobo08_reference_clean_replay_setup Initialize exact ball-balance assets.
arguments
    taskId (1,1) string
    officialScenariosPath (1,1) string
    model (1,1) string
end
assert(taskId == "F90-XROBO-08", ...
    "SimuVerity:ReferenceSetup:TaskMismatch", ...
    "This setup is bound only to F90-XROBO-08.");
assert(isfile(officialScenariosPath) && bdIsLoaded(model), ...
    "SimuVerity:ReferenceSetup:Contract", ...
    "Official scenarios and the loaded reference model are required.");

assetRoot = string(pwd);
mainRoot = fullfile(assetRoot, "main");
dataRoot = fullfile(assetRoot, "data");
parameterFile = fullfile(mainRoot, "kinova_params.m");
agentFile = fullfile(dataRoot, "kinovaBallBalanceAgent.mat");
calcFile = fullfile(mainRoot, "calcMOI.m");
contactFile = fullfile(mainRoot, "cor2SpringDamperParams.m");
expected = [ ...
    "present"; ...
    "present"; ...
    "present"; ...
    "present"];
files = [parameterFile; agentFile; calcFile; contactFile];
for index = 1:numel(files)
    assert(isfile(files(index)) && localFileIdentity(files(index)) == expected(index), ...
        "SimuVerity:ReferenceSetup:AssetClosureMismatch", ...
        "A repository-bundled ball-balance initialization asset is missing or changed.");
end
addpath(mainRoot, dataRoot, "-begin");
localRunPinnedParameters(parameterFile, model);
loaded = load(agentFile);
policyName = localPolicyField(loaded);
assignin("base", "f90_reference_agent", loaded.(policyName));
agentBlock = model + "/RL Agent";
assert(getSimulinkBlockHandle(agentBlock) > 0, ...
    "SimuVerity:ReferenceSetup:AgentBlockMissing", ...
    "The exact reference RL Agent block is unavailable.");
set_param(agentBlock, "Agent", "f90_reference_agent");
end

function localRunPinnedParameters(parameterFile, model)
originalBlock = "rlKinovaBallBalance/Kinova Ball Balance/7 DOF Manipulator";
runtimeBlock = model + "/Kinova Ball Balance/7 DOF Manipulator";
assert(getSimulinkBlockHandle(runtimeBlock) > 0, ...
    "SimuVerity:ReferenceSetup:ManipulatorBlockMissing", ...
    "The loaded reference alias has no exact 7 DOF Manipulator block.");
parameterSource = string(fileread(parameterFile));
assert(count(parameterSource, originalBlock) == 2, ...
    "SimuVerity:ReferenceSetup:ParameterScriptContract", ...
    "The pinned parameter script no longer has its exact two model-bound calls.");
if runtimeBlock ~= originalBlock
    parameterSource = replace(parameterSource, originalBlock, runtimeBlock);
    assert(~contains(parameterSource, originalBlock), ...
        "SimuVerity:ReferenceSetup:ParameterScriptRewrite", ...
        "The pinned parameter script still targets the unloaded source model.");
end
evalin("base", parameterSource);
end

function name = localPolicyField(value)
preferred = ["agent", "saved_agent", "trainedAgent"];
fields = string(fieldnames(value));
for candidate = preferred
    if any(fields == candidate), name = candidate; return, end
end
assert(numel(fields) == 1, ...
    "SimuVerity:ReferenceSetup:PolicyField", ...
    "The pinned policy MAT file has no unique agent object.");
name = fields(1);
end

function value = localFileIdentity(pathValue)
assert(isfile(pathValue), "SimuVerity:ReferenceSetup:AssetMissing", ...
    "Required reference asset is missing: %s", pathValue);
value = "present";
end
