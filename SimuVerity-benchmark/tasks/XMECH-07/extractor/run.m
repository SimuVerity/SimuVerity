function evidence = run(candidatePath, officialScenarios, evidencePath)
%RUN Stable SimuVerity extraction boundary for XMECH-07.
arguments
    candidatePath (1,1) string
    officialScenarios
    evidencePath (1,1) string
end
assert(isfile(candidatePath), "SimuVerity:Extractor:CandidateMissing", ...
    "Candidate model not found: %s", candidatePath);
taskRoot = string(fileparts(fileparts(mfilename("fullpath"))));
vendorRoot = fullfile(taskRoot, "vendor");
supportRoot = fullfile(taskRoot, "extractor", "support");
implementationPath = fullfile(taskRoot, 'vendor/scripts/formal90/tasks/f90_xmech07/f90_xmech07_extract_candidate_evidence.m');
assert(isfile(implementationPath), "SimuVerity:Extractor:ImplementationMissing", ...
    "Extractor implementation not found: %s", implementationPath);
referenceImplementationPath = fullfile(taskRoot, ...
    'vendor/scripts/formal90/tasks/f90_xmech07/f90_xmech07_extract_reference_evidence.m');

temporaryScenario = "";
if isstruct(officialScenarios)
    temporaryScenario = string(tempname) + ".json";
    localWriteText(temporaryScenario, jsonencode(officialScenarios));
    scenarioPath = temporaryScenario;
else
    scenarioPath = string(officialScenarios);
end
assert(isfile(scenarioPath), "SimuVerity:Extractor:OfficialScenariosMissing", ...
    "Official scenario contract not found: %s", scenarioPath);

oldPath = path;
oldScenario = string(getenv("SIMUVERITY_OFFICIAL_SCENARIOS"));
oldTaskRoot = string(getenv("SIMUVERITY_TASK_ROOT"));
oldVendorRoot = string(getenv("SIMUVERITY_TASK_VENDOR_ROOT"));
cleanup = onCleanup(@() localCleanup(oldPath, oldScenario, oldTaskRoot, ...
    oldVendorRoot, temporaryScenario)); %#ok<NASGU>
setenv("SIMUVERITY_OFFICIAL_SCENARIOS", scenarioPath);
setenv("SIMUVERITY_TASK_ROOT", taskRoot);
setenv("SIMUVERITY_TASK_VENDOR_ROOT", vendorRoot);
addpath(supportRoot, "-begin");
addpath(genpath(vendorRoot), "-begin");

temporaryOutput = string(tempname);
outputCleanup = onCleanup(@() localRemoveTree(temporaryOutput)); %#ok<NASGU>
try
    subject = localEvaluationSubject();
    if subject == "reference"
        [referenceModel, evaluatorAssetRoot] = localReferenceContext( ...
            candidatePath, taskRoot, scenarioPath, ...
            referenceImplementationPath);
        evidence = feval('f90_xmech07_extract_reference_evidence', referenceModel, temporaryOutput, scenarioPath, evaluatorAssetRoot);
    else
        evidence = feval('f90_xmech07_extract_candidate_evidence', candidatePath, temporaryOutput);
    end
catch exception
    produced = fullfile(temporaryOutput, "evidence.json");
    if isfile(produced)
        simuverity_publish_diagnostic_evidence(produced, evidencePath);
    end
    rethrow(exception)
end
produced = fullfile(temporaryOutput, "evidence.json");
if ~isfile(produced)
    assert(isstruct(evidence), "SimuVerity:Extractor:NoEvidence", ...
        "Extractor returned no structure and wrote no evidence.json.");
    localWriteText(produced, jsonencode(evidence));
end

simuverity_publish_evidence_closure(temporaryOutput, evidencePath);
evidence = jsondecode(fileread(evidencePath));
end

function subject = localEvaluationSubject
subject = lower(strtrim(string(getenv("SIMUVERITY_EVALUATION_SUBJECT"))));
if strlength(subject) == 0, subject = "candidate"; end
assert(any(subject == ["candidate", "reference"]), ...
    "SimuVerity:Extractor:EvaluationSubject", ...
    "SIMUVERITY_EVALUATION_SUBJECT must be candidate or reference.");
end

function [modelPath, assetRoot] = localReferenceContext(candidatePath, varargin)
taskRoot = string(fileparts(fileparts(mfilename("fullpath"))));
task = jsondecode(fileread(fullfile(taskRoot, "task.json")));
assert(string(task.reference.materialization) == "bundled", ...
    "SimuVerity:Extractor:ReferenceBinding", "Bundled reference binding required.");
entrypoint = string(task.reference.entrypoint);
prefix = "reference/files/";
assert(startsWith(entrypoint, prefix), "SimuVerity:Extractor:ReferenceBinding", ...
    "Bundled reference entrypoint is outside reference/files.");
relativeModel = extractAfter(entrypoint, strlength(prefix));
assetRoot = string(getenv("SIMUVERITY_EVALUATOR_ASSET_ROOT"));
runtimeRoot = string(getenv("SIMUVERITY_RUNTIME_SUBMISSION_BUNDLE"));
assetModel = fullfile(assetRoot, replace(relativeModel, "/", filesep));
modelPath = fullfile(runtimeRoot, replace(relativeModel, "/", filesep));
assert(isfile(candidatePath) && isfolder(assetRoot) && isfile(assetModel), ...
    "SimuVerity:Extractor:ReferenceAsset", "Bundled reference asset is missing.");
assert(isfolder(runtimeRoot) && isfile(modelPath), ...
    "SimuVerity:Extractor:ReferenceRuntime", "Runtime reference entrypoint is missing.");
for index = 1:numel(varargin)
    value = string(varargin{index});
    if endsWith(lower(value), ".m") && any(contains(value, ["/", "\"]))
        assert(isfile(value), "SimuVerity:Extractor:ReferenceImplementationMissing", ...
            "Reference extractor implementation is missing: %s", value);
    end
end
end

function localValidateOfficialScenarios(taskRoot, scenarioPath, varargin)
expectedPath = fullfile(taskRoot, "official_scenarios.json");
assert(isfile(expectedPath) && isfile(scenarioPath) && ...
    isequaln(jsondecode(fileread(expectedPath)), jsondecode(fileread(scenarioPath))), ...
    "SimuVerity:Extractor:OfficialScenarioBinding", ...
    "Reference extraction requires the task-owned official scenarios.");
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

function localWriteText(pathValue, textValue)
fid = fopen(pathValue, "w");
assert(fid >= 0, "SimuVerity:Extractor:WriteFailed", ...
    "Cannot write: %s", pathValue);
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fwrite(fid, unicode2native(char(textValue), "UTF-8"), "uint8");
end

function localCleanup(oldPath, oldScenario, oldTaskRoot, oldVendorRoot, temporaryScenario)
path(oldPath);
setenv("SIMUVERITY_OFFICIAL_SCENARIOS", oldScenario);
setenv("SIMUVERITY_TASK_ROOT", oldTaskRoot);
setenv("SIMUVERITY_TASK_VENDOR_ROOT", oldVendorRoot);
if strlength(temporaryScenario) > 0 && isfile(temporaryScenario), delete(temporaryScenario); end
end

function localRemoveTree(pathValue)
if isfolder(pathValue), rmdir(pathValue, "s"); end
end
