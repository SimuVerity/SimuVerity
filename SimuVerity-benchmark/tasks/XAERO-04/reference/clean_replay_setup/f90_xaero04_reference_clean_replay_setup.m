function f90_xaero04_reference_clean_replay_setup(taskId, officialScenariosPath)
%F90_XAERO04_REFERENCE_CLEAN_REPLAY_SETUP Initialize exact VTOL reference.
arguments
    taskId (1,1) string
    officialScenariosPath (1,1) string
end
assert(taskId == "F90-XAERO-04", ...
    "SimuVerity:ReferenceSetup:TaskMismatch", ...
    "This setup is bound only to F90-XAERO-04.");
assert(isfile(officialScenariosPath), ...
    "SimuVerity:ReferenceSetup:OfficialScenariosMissing", ...
    "Official scenarios are missing: %s", officialScenariosPath);

assetRoot = string(pwd);
projectRoot = fullfile(assetRoot, "VTOLApp");
projectFile = fullfile(projectRoot, "VTOLRefApp.prj");
startup = fullfile(projectRoot, "steps", "setupPlant.m");
gainInitializer = fullfile(projectRoot, "utilities", "Setup", ...
    "exampleHelperInitializeVTOLGains.m");
interfaceInitializer = fullfile(projectRoot, "utilities", "Setup", ...
    "exampleHelperDefineCtrlInterface.m");
localAssertAsset(projectFile, ...
    "present");
localAssertAsset(startup, ...
    "present");
localAssertAsset(gainInitializer, ...
    "present");
localAssertAsset(interfaceInitializer, ...
    "present");
required = [ ...
    fullfile(projectRoot, "models", "VTOLAutopilotController.slx"); ...
    fullfile(projectRoot, "models", "VTOLDynamics.slx"); ...
    fullfile(projectRoot, "data", "VTOLDynamicsData.sldd")];
assert(all(isfile(required)), ...
    "SimuVerity:ReferenceSetup:AssetClosureMissing", ...
    "The imported XAERO-04 reference initialization closure is incomplete.");

% Opening the official project executes its StartUp shortcut setupPlant.m.
% This is the same initialization boundary used by the current reference
% extractor; it defines the flightState enum, all controller gain structs,
% guidance constants, controller buses, plant parameters and configuration.
project = openProject(projectRoot); %#ok<NASGU>
assert(evalin("base", "exist('controlParams','var') == 1"), ...
    "SimuVerity:ReferenceSetup:OfficialStartupIncomplete", ...
    "Official project startup did not define controlParams.");
assert(evalin("base", "exist('FWControlParams','var') == 1"), ...
    "SimuVerity:ReferenceSetup:OfficialStartupIncomplete", ...
    "Official project startup did not define FWControlParams.");
assert(evalin("base", "exist('AAC','var') == 1"), ...
    "SimuVerity:ReferenceSetup:OfficialStartupIncomplete", ...
    "Official project startup did not define AAC.");
assert(evalin("base", "exist('R_WAYPOINTTRANSITION','var') == 1"), ...
    "SimuVerity:ReferenceSetup:OfficialStartupIncomplete", ...
    "Official project startup did not define R_WAYPOINTTRANSITION.");
assert(isstruct(evalin("base", "controlParams")) && ...
    isstruct(evalin("base", "FWControlParams")) && ...
    isa(evalin("base", "AAC"), "Simulink.Bus") && ...
    isscalar(evalin("base", "R_WAYPOINTTRANSITION")), ...
    "SimuVerity:ReferenceSetup:OfficialStartupType", ...
    "Official project startup returned invalid controller initialization values.");

document = jsondecode(fileread(officialScenariosPath));
assert(isfield(document, "scenarios") && ~isempty(document.scenarios), ...
    "SimuVerity:ReferenceSetup:ScenarioContract", ...
    "XAERO-04 requires at least one official scenario.");
scenario = document.scenarios(1);

% Apply the first official scenario exactly as the locked native reference
% extractor does, after the complete official project startup has run.
assignin("base", "TestMode", 1);
assignin("base", "Visualization", 0);
assignin("base", "SensorType", 0);
assignin("base", "ElectricPropulsion", 0);
assignin("base", "useQGC", 0);
assignin("base", "TuningMode", 0);
assignin("base", "Deployment", false);
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
        error("SimuVerity:ReferenceSetup:ScenarioContract", ...
            "XAERO-04 MissionKind is unsupported.");
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

% The project startup loads its nested VTOLTiltrotor model. Reference
% validation stages the declared entrypoint at the submission root, so close
% only that already-initialized top model before clean replay loads the staged
% copy. The initialized workspace and referenced controller/plant stay intact.
if bdIsLoaded("VTOLTiltrotor")
    close_system("VTOLTiltrotor", 0);
end
end

function localAssertAsset(pathValue, expectedBinding)
assert(isfile(pathValue) && localFileIdentity(pathValue) == expectedBinding, ...
    "SimuVerity:ReferenceSetup:AssetClosureMismatch", ...
    "The repository-bundled VTOL initialization asset is missing or changed: %s", ...
    pathValue);
end

function value = localFileIdentity(pathValue)
assert(isfile(pathValue), "SimuVerity:ReferenceSetup:AssetMissing", ...
    "Required reference asset is missing: %s", pathValue);
value = "present";
end
