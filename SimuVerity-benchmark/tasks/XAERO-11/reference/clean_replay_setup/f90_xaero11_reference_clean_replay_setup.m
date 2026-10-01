function f90_xaero11_reference_clean_replay_setup(taskId, officialScenariosPath)
%F90_XAERO11_REFERENCE_CLEAN_REPLAY_SETUP Initialize the exact ADCS reference.
arguments
    taskId (1,1) string
    officialScenariosPath (1,1) string
end
assert(taskId == "F90-XAERO-11", ...
    "SimuVerity:ReferenceSetup:TaskMismatch", ...
    "This setup is bound only to F90-XAERO-11.");
subject = lower(strtrim(string(getenv("SIMUVERITY_EVALUATION_SUBJECT"))));
assert(subject == "reference", ...
    "SimuVerity:ReferenceSetup:SubjectMismatch", ...
    "The native XAERO-11 workspace may only initialize the sealed reference.");

expectedScenarioBinding = ...
    "present";
assert(isfile(officialScenariosPath) && ...
    localFileIdentity(officialScenariosPath) == expectedScenarioBinding, ...
    "SimuVerity:ReferenceSetup:ScenarioIdentity", ...
    "The official XAERO-11 scenarios are missing or changed.");
document = jsondecode(fileread(officialScenariosPath));
scenarios = document.scenarios;
if iscell(scenarios), scenarios = [scenarios{:}]; end
assert(string(document.task_id) == taskId && numel(scenarios) == 6, ...
    "SimuVerity:ReferenceSetup:ScenarioContract", ...
    "XAERO-11 requires its exact six-scenario contract.");
scenario = scenarios(1);
assert(string(scenario.id) == "nominal_slew" && ...
    double(scenario.operation_mode) == 1 && ...
    isequal(double(scenario.initial_body_rate_rad_s(:)), [0; 0; 0]) && ...
    isequal(double(scenario.target_inertial_unit_vector(:)), [1; 0; 0]) && ...
    double(scenario.sensor_noise_scale) == 1 && ...
    double(scenario.disturbance_scale) == 1, ...
    "SimuVerity:ReferenceSetup:ScenarioContract", ...
    "The source-authoritative nominal slew scenario is missing or changed.");

% Clean replay starts in the root of its fresh bundled reference copy.  Bind
% both the sealed root alias used by the replay helper and the retained source
% entrypoint used by the native extractor.  The reference inventory binds the
% remaining 53-file closure; these are the initializer's direct assets.
assetRoot = string(pwd);
candidateAlias = fullfile(assetRoot, "BFN_00_zfull_system.slx");
sourceModel = fullfile(assetRoot, "src_simulink", "BFN_00_zfull_system.slx");
initializer = fullfile(assetRoot, "src_matlab", "BFN_00_main.m");
helper = fullfile(assetRoot, "funs", "spher2car.m");
fieldData = fullfile(assetRoot, "funs", "sh2020.mat");
expectedModelBinding = ...
    "present";
localAssertAsset(candidateAlias, expectedModelBinding);
localAssertAsset(sourceModel, expectedModelBinding);
localAssertAsset(initializer, ...
    "present");
localAssertAsset(helper, ...
    "present");
localAssertAsset(fieldData, ...
    "present");
localAssertAsset(fullfile(assetRoot, "LICENSE"), ...
    "present");
localAssertAsset(fullfile(assetRoot, "README.md"), ...
    "present");

% BFN_00_main uses source-root-relative addpath/load calls and begins with
% `clear all`, so execute it by name from the official root.  Reapply the first
% public scenario only after it returns, including the public container erased
% by that official clear.  No source value is reconstructed before authority
% initialization and neither model copy is saved.
originalFolder = string(pwd);
originalPath = path;
folderCleanup = onCleanup(@() cd(originalFolder)); %#ok<NASGU>
pathCleanup = onCleanup(@() path(originalPath)); %#ok<NASGU>
cd(assetRoot);
addpath(fullfile(assetRoot, "src_matlab"), "-begin");
evalin("base", "BFN_00_main");

nominalInput = rmfield(scenario, "id");
assignin("base", "adcs_case_input", nominalInput);
assignin("base", "today_mjd2000", 9000.0);
assignin("base", "w0", double(scenario.initial_body_rate_rad_s(:)));
assignin("base", "targets_inertial", repmat( ...
    double(scenario.target_inertial_unit_vector(:)), 1, 3));
noiseScale = double(scenario.sensor_noise_scale);
disturbanceScale = double(scenario.disturbance_scale);
assignin("base", "Magn_noise", 1.18e-9 * sqrt(0.5) * noiseScale);
assignin("base", "IFEHS_noise", 0.0101e-2 * sqrt(0.5) * noiseScale);
assignin("base", "Gyro_noise_n", ...
    0.01 / 60 * pi / 180 * sqrt(1e3) * noiseScale);
assignin("base", "Gyro_noise_b", ...
    1 / 3600 * pi / 180 * sqrt(1e3) * noiseScale);
assignin("base", "m_disturb", ...
    [0.01; 0.05; 0.01] * 0.5e-2 * disturbanceScale);
assignin("base", "Cd", 2.2 * disturbanceScale);
rng(314160, "twister");

load_system(candidateAlias);
model = "BFN_00_zfull_system";
assert(bdIsLoaded(model) && ...
    localSamePath(string(get_param(model, "FileName")), candidateAlias) && ...
    localFileIdentity(string(get_param(model, "FileName"))) == expectedModelBinding, ...
    "SimuVerity:ReferenceSetup:ModelIdentity", ...
    "Clean replay did not load the exact sealed XAERO-11 root alias.");
set_param(model + "/Manual Switch", "sw", "0");

requiredVariables = ["adcs_case_input", "today_mjd2000", "w0", ...
    "targets_inertial", "Magn_noise", "IFEHS_noise", "Gyro_noise_n", ...
    "Gyro_noise_b", "m_disturb", "Cd", "agh", "dgh", "Jsc"];
for index = 1:numel(requiredVariables)
    assert(evalin("base", "exist('" + requiredVariables(index) + ...
        "','var') == 1"), ...
        "SimuVerity:ReferenceSetup:OfficialInitializationIncomplete", ...
        "The official XAERO-11 initializer did not define %s.", ...
        requiredVariables(index));
end
localAssertAsset(candidateAlias, expectedModelBinding);
localAssertAsset(sourceModel, expectedModelBinding);
end

function localAssertAsset(pathValue, expectedBinding)
assert(isfile(pathValue) && localFileIdentity(pathValue) == expectedBinding, ...
    "SimuVerity:ReferenceSetup:AssetClosureMismatch", ...
    "A repository-bundled XAERO-11 asset is missing or changed: %s", pathValue);
end

function value = localFileIdentity(pathValue)
assert(isfile(pathValue), "SimuVerity:ReferenceSetup:AssetMissing", ...
    "Required reference asset is missing: %s", pathValue);
value = "present";
end
function same = localSamePath(firstPath, secondPath)
first = char(java.io.File(char(firstPath)).getCanonicalPath());
second = char(java.io.File(char(secondPath)).getCanonicalPath());
if ispc
    same = strcmpi(first, second);
else
    same = strcmp(first, second);
end
end
