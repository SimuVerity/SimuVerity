function evidence = run(candidatePath, officialScenarios, evidencePath)
%RUN Stable SimuVerity extraction boundary for XTHERM-13.
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
implementationPath = fullfile(taskRoot, 'vendor/packages/simuverity_public/tasks/XTHERM-13/policy/ext_xtherm_pvtes_extract_evidence.m');
assert(isfile(implementationPath), "SimuVerity:Extractor:ImplementationMissing", ...
    "Extractor implementation not found: %s", implementationPath);
scenarioPath = localValidateTaskAndScenarioContract(taskRoot, officialScenarios);

oldPath = path;
oldScenario = string(getenv("SIMUVERITY_OFFICIAL_SCENARIOS"));
oldTaskRoot = string(getenv("SIMUVERITY_TASK_ROOT"));
oldVendorRoot = string(getenv("SIMUVERITY_TASK_VENDOR_ROOT"));
cleanup = onCleanup(@() localCleanup(oldPath, oldScenario, oldTaskRoot, ...
    oldVendorRoot)); %#ok<NASGU>
setenv("SIMUVERITY_OFFICIAL_SCENARIOS", scenarioPath);
setenv("SIMUVERITY_TASK_ROOT", taskRoot);
setenv("SIMUVERITY_TASK_VENDOR_ROOT", vendorRoot);
addpath(supportRoot, "-begin");
addpath(genpath(vendorRoot), "-begin");

temporaryOutput = string(tempname);
mkdir(temporaryOutput);
outputCleanup = onCleanup(@() localRemoveTree(temporaryOutput)); %#ok<NASGU>
try
    if localEvaluationSubject() == "reference"
        evaluatorAssetRoot = localReferenceContext(candidatePath, implementationPath);
        evidence = feval('ext_xtherm_pvtes_extract_evidence', candidatePath, temporaryOutput, scenarioPath, evaluatorAssetRoot);
    else
        evidence = feval('ext_xtherm_pvtes_extract_evidence', candidatePath, temporaryOutput, scenarioPath, "");
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

function scenarioPath = localValidateTaskAndScenarioContract(taskRoot, officialScenarios, varargin)
task = jsondecode(fileread(fullfile(taskRoot, "task.json")));
assert(string(task.schema) == "simuverity.task.v1" && ...
    string(task.release) == "simuverity-101-v1" && ...
    string(task.task_id) == "XTHERM-13" && ...
    string(task.reference.materialization) == "bundled", ...
    "SimuVerity:Extractor:TaskBinding", "Public task binding is incomplete.");
scenarioPath = fullfile(taskRoot, "official_scenarios.json");
assert(isfile(scenarioPath), "SimuVerity:Extractor:OfficialScenariosMissing", ...
    "Task-owned official scenarios are missing.");
expected = jsondecode(fileread(scenarioPath));
if isstruct(officialScenarios)
    supplied = officialScenarios;
else
    suppliedPath = string(officialScenarios);
    assert(isfile(suppliedPath), "SimuVerity:Extractor:OfficialScenariosMissing", ...
        "Supplied official scenarios are missing.");
    supplied = jsondecode(fileread(suppliedPath));
end
assert(isequaln(supplied, expected), ...
    "SimuVerity:Extractor:OfficialScenarioBinding", ...
    "Supplied scenarios differ from the task-owned contract.");
end

function subject = localEvaluationSubject()
subject = lower(strtrim(string(getenv("SIMUVERITY_EVALUATION_SUBJECT"))));
if strlength(subject) == 0, subject = "candidate"; end
assert(any(subject == ["candidate", "reference"]), ...
    "SimuVerity:Extractor:EvaluationSubject", ...
    "SIMUVERITY_EVALUATION_SUBJECT must be candidate or reference.");
end

function assetRoot = localReferenceContext(candidatePath, varargin)
assert(isfile(candidatePath), "SimuVerity:Extractor:ReferenceSubject", ...
    "Reference subject is missing: %s", candidatePath);
for index = 1:numel(varargin)
    value = string(varargin{index});
    if endsWith(lower(value), ".m") && any(contains(value, ["/", "\"]))
        assert(isfile(value), "SimuVerity:Extractor:ReferenceImplementationMissing", ...
            "Reference extractor implementation is missing: %s", value);
    end
end
assetRoot = string(getenv("SIMUVERITY_EVALUATOR_ASSET_ROOT"));
assert(isfolder(assetRoot), "SimuVerity:Extractor:EvaluatorAssetRoot", ...
    "Evaluator-owned reference asset root is missing.");
end

function localWriteText(pathValue, textValue)
fid = fopen(pathValue, "w");
assert(fid >= 0, "SimuVerity:Extractor:WriteFailed", ...
    "Cannot write: %s", pathValue);
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fwrite(fid, unicode2native(char(textValue), "UTF-8"), "uint8");
end

function localCleanup(oldPath, oldScenario, oldTaskRoot, oldVendorRoot)
path(oldPath);
setenv("SIMUVERITY_OFFICIAL_SCENARIOS", oldScenario);
setenv("SIMUVERITY_TASK_ROOT", oldTaskRoot);
setenv("SIMUVERITY_TASK_VENDOR_ROOT", oldVendorRoot);
end

function localRemoveTree(pathValue)
if isfolder(pathValue), rmdir(pathValue, "s"); end
end
