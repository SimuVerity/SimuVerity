function f90_xbatt09_reference_clean_replay_setup(taskId, officialScenariosPath)
%F90_XBATT09_REFERENCE_CLEAN_REPLAY_SETUP Initialize the reference before load.
arguments
    taskId (1,1) string
    officialScenariosPath (1,1) string
end
assert(taskId == "F90-XBATT-09", ...
    "SimuVerity:ReferenceSetup:TaskMismatch", ...
    "This setup is bound only to F90-XBATT-09.");
assert(isfile(officialScenariosPath), ...
    "SimuVerity:ReferenceSetup:OfficialScenariosMissing", ...
    "Official scenarios are missing: %s", officialScenariosPath);

assetRoot = string(pwd);
parameterScript = fullfile(assetRoot, "moduleLibrary_param.m");
profilePath = fullfile(assetRoot, "DischargeCycle.mat");
assert(isfile(parameterScript) && isfile(profilePath), ...
    "SimuVerity:ReferenceSetup:AssetClosureMissing", ...
    "The imported XBATT-09 reference initialization closure is incomplete.");
addpath(assetRoot, "-begin");
parameterCommand = "run('" + replace(replace(parameterScript, "\", "/"), "'", "''") + "')";
evalin("base", parameterCommand);

document = jsondecode(fileread(officialScenariosPath));
assert(isfield(document, "scenarios") && ~isempty(document.scenarios), ...
    "SimuVerity:ReferenceSetup:ScenarioContract", ...
    "XBATT-09 requires at least one official scenario.");
definition = document.scenarios(1);
profiles = load(profilePath, "batteryCurrent", "batteryCurrentValidation");
profileName = string(definition.profile);
assert(isfield(profiles, profileName), ...
    "SimuVerity:ReferenceSetup:ProfileMissing", ...
    "The nominal profile is missing from DischargeCycle.mat.");
batteryCurrent = double(profiles.(profileName));
batteryCurrent(:,2) = batteryCurrent(:,2) .* double(definition.current_scale);
assignin("base", "batteryCurrent", batteryCurrent);
% The official live script saves the source model with this second profile
% selected. It must exist before clean-replay update; the scenario extractor
% still replaces the block input with batteryCurrent for every fixed case.
assignin("base", "batteryCurrentValidation", double(profiles.batteryCurrentValidation));
end
