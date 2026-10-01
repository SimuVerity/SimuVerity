function evidence = f90_xrobo02_extract_reference_evidence(modelPath, outDir)
%f90_xrobo02_extract_reference_evidence Replay the recovered reference.
% This entrypoint is restricted to the exact historical closed-loop reference.
% Candidate evaluation continues to use the current current implementation.
arguments
    modelPath (1,1) string
    outDir (1,1) string
end

expectedReferencePresence = ...
    "present";
subject = string(getenv("SIMUVERITY_EVALUATION_SUBJECT"));
assert(subject == "reference", ...
    "SimuVerity:XROBO02:ReferenceSubject", ...
    "The recovered XROBO-02 reference extractor is reference-only.");
assert(isfile(modelPath) && localFilePresence(modelPath) == expectedReferencePresence, ...
    "SimuVerity:XROBO02:ReferenceIdentity", ...
    "The recovered XROBO-02 closed-loop reference is missing or changed.");

scenarioPath = string(getenv("SIMUVERITY_OFFICIAL_SCENARIOS"));
assert(isfile(scenarioPath) && localFilePresence(scenarioPath) == ...
    "present", ...
    "SimuVerity:XROBO02:ScenarioIdentity", ...
    "The exact five-scenario XROBO-02 contract is missing or changed.");
scenarioDocument = jsondecode(fileread(scenarioPath));

taskDir = string(fileparts(mfilename("fullpath")));
dependency = fullfile(taskDir, "f90_xrobo02_measurement_compatibility.m");
assert(isfile(dependency) && localFilePresence(dependency) == ...
    "present", ...
    "SimuVerity:XROBO02:MeasurementIdentity", ...
    "The current XROBO-02 measurement helper is missing or changed.");

runtimeRoot = string(fileparts(modelPath));
sourceRoot = fullfile(runtimeRoot, "Industrial-Robots-Simscape");
sourceModel = fullfile(sourceRoot, "Robots", "abbYuMi", "Models", ...
    "sm_abbYuMi_trajectory.slx");
initializer = fullfile(sourceRoot, "Robots", "abbYuMi", "Models", ...
    "startup_sm_abbYuMi_trajectory.m");
assert(isfile(sourceModel) && localFilePresence(sourceModel) == ...
    "present" && ...
    isfile(initializer) && localFilePresence(initializer) == ...
    "present", ...
    "SimuVerity:XROBO02:SourceClosure", ...
    "The recovered reference is missing its exact upstream YuMi closure.");

oldPath = path;
oldDir = string(pwd);
[~, model] = fileparts(modelPath);
cleanup = onCleanup(@() localCleanup(oldPath, oldDir, model)); %#ok<NASGU>
addpath(genpath(sourceRoot), "-begin");
cd(fileparts(initializer));
startup_sm_abbYuMi_trajectory;
assignin("base", "cube_l", cube_l);
assignin("base", "brick_point_cloud", brick_point_cloud);
assignin("base", "finger_point_cloud", finger_point_cloud);
assignin("base", "segment_duration", segment_duration);
if bdIsLoaded("sm_abbYuMi_trajectory")
    close_system("sm_abbYuMi_trajectory", 0);
end

def = f90_xrobo02_definition;
ids = ["nominal", string({def.scenarios.id})];
assert(string(scenarioDocument.task_id) == "F90-XROBO-02" && ...
    numel(scenarioDocument.scenarios) == 5 && ...
    isequal(string({scenarioDocument.scenarios.id}), ids), ...
    "SimuVerity:XROBO02:ScenarioContract", ...
    "The official XROBO-02 scenario order differs from the current definition.");

runScenario = @(varargin) f90_xrobo02_measurement_compatibility( ...
    "run_scenario", varargin{:});
staticAudit = @(varargin) f90_xrobo02_measurement_compatibility( ...
    "static_audit", varargin{:});
emptyRow = @() f90_xrobo02_measurement_compatibility("empty_row");
facts = struct( ...
    "platform_valid", false, ...
    "score_inputs_valid", false, ...
    "diagnostics_valid", false, ...
    "gate_reasons", strings(0, 1), ...
    "static_audit", struct, ...
    "scenario_rows", struct([]), ...
    "evaluation_subject", "reference_subject", ...
    "reference_adapter", ...
        "f90_xrobo02_extract_reference_evidence");

try
    initialValues = scenarioDocument.scenarios(1).values;
    initialFields = fieldnames(initialValues);
    for index = 1:numel(initialFields)
        assignin("base", initialFields{index}, initialValues.(initialFields{index}));
    end
    load_system(modelPath);
    modelCleanup = onCleanup(@() localClose(model)); %#ok<NASGU>
    audit = staticAudit(model);
    set_param(model, "SimulationCommand", "update");
    rows = repmat(emptyRow(), 1, numel(ids));
    for index = 1:numel(ids)
        rows(index) = runScenario(model, ids(index), ...
            scenarioDocument.scenarios(index).values, def);
    end
    valid = all([rows.valid]);
    reasons = strings(0, 1);
    if ~valid
        reasons(end + 1, 1) = "One or more scenarios invalid"; %#ok<AGROW>
    end
    facts.platform_valid = true;
    facts.score_inputs_valid = valid;
    facts.diagnostics_valid = true;
    facts.gate_reasons = reasons;
    facts.static_audit = audit;
    facts.scenario_rows = rows;
catch ME
    facts.gate_reasons = "Evaluator/platform failure: " + string(ME.message);
    facts.error_identifier = string(ME.identifier);
    facts.error_message = string(ME.message);
    facts.error_report = string(getReport(ME, "extended", "hyperlinks", "off"));
end

assert(localFilePresence(modelPath) == expectedReferencePresence, ...
    "SimuVerity:XROBO02:ReferenceChanged", ...
    "Reference extraction changed the sealed XROBO-02 model.");
evidence = formal90_write_evidence("F90-XROBO-02", modelPath, outDir, ...
    def.groups.weights, facts, dependency);
end

function localCleanup(oldPath, oldDir, model)
localClose(model);
localClose("sm_abbYuMi_trajectory");
try, cd(oldDir); catch, end
try, path(oldPath); catch, end
end

function localClose(model)
try
    if bdIsLoaded(model), close_system(model, 0); end
catch
end
end

function binding = localFilePresence(pathValue)
assert(isfile(pathValue), "SimuVerity:FileMissing", "Required file is missing: %s", pathValue);
binding = "present";
end
