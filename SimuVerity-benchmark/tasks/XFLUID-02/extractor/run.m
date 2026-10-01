function evidence = run(candidatePath, officialScenarios, evidencePath)
%RUN Stable SimuVerity extraction boundary for XFLUID-02.
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
implementationPath = fullfile(taskRoot, 'vendor/scripts/formal90/tasks/f90_xfluid02/f90_xfluid02_extract_candidate_evidence.m');
assert(isfile(implementationPath), "SimuVerity:Extractor:ImplementationMissing", ...
    "Extractor implementation not found: %s", implementationPath);

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
subject = localEvaluationSubject();

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
mkdir(temporaryOutput);
outputCleanup = onCleanup(@() localRemoveTree(temporaryOutput)); %#ok<NASGU>
if subject == "reference"
    localPrepareReference(candidatePath, taskRoot, scenarioPath);
    referenceCleanup = onCleanup(@() localCloseReference()); %#ok<NASGU>
    referenceImplementationPath = fullfile(taskRoot, ...
        'vendor/scripts/formal90/tasks/f90_xfluid02/f90_xfluid02_extract_reference_evidence.m');
    assert(isfile(referenceImplementationPath), ...
        "SimuVerity:Extractor:ReferenceImplementationMissing", ...
        "Reference-native extractor not found: %s", referenceImplementationPath);
    evidence = feval('f90_xfluid02_extract_reference_evidence', candidatePath, temporaryOutput);
else
    evidence = feval('f90_xfluid02_extract_candidate_evidence', candidatePath, temporaryOutput);
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

function subject = localEvaluationSubject()
subject = lower(strtrim(string(getenv("SIMUVERITY_EVALUATION_SUBJECT"))));
if strlength(subject) == 0, subject = "candidate"; end
assert(any(subject == ["candidate", "reference"]), ...
    "SimuVerity:Extractor:EvaluationSubject", ...
    "SIMUVERITY_EVALUATION_SUBJECT must be candidate or reference.");
end

function localPrepareReference(candidatePath, taskRoot, scenarioPath)
task = jsondecode(fileread(fullfile(taskRoot, "task.json")));
expectedScenarios = fullfile(taskRoot, "official_scenarios.json");
assert(isfile(candidatePath) && isfile(expectedScenarios) && ...
    isequaln(jsondecode(fileread(expectedScenarios)), jsondecode(fileread(scenarioPath))), ...
    "SimuVerity:Extractor:OfficialScenarioBinding", ...
    "Reference extraction requires the task-owned official scenarios.");
repositoryRoot = string(fileparts(fileparts(taskRoot)));
setup = task.reference.clean_replay_setup;
setupPath = fullfile(repositoryRoot, replace(string(setup.path), "/", filesep));
assetRoot = string(getenv("SIMUVERITY_EVALUATOR_ASSET_ROOT"));
runtimeRoot = string(getenv("SIMUVERITY_RUNTIME_SUBMISSION_BUNDLE"));
entrypoint = erase(string(task.reference.entrypoint), "reference/files/");
assetModel = fullfile(assetRoot, replace(entrypoint, "/", filesep));
assert(isfile(setupPath) && isfolder(assetRoot) && isfile(assetModel), ...
    "SimuVerity:Extractor:ReferenceAsset", "Reference setup or asset is missing.");
assert(isfolder(runtimeRoot), "SimuVerity:Extractor:ReferenceRuntime", ...
    "Runtime reference bundle is missing.");
oldDirectory = string(pwd);
directoryCleanup = onCleanup(@() cd(oldDirectory)); %#ok<NASGU>
cd(runtimeRoot);
addpath(fileparts(setupPath), "-begin");
feval(string(setup.entrypoint), string(task.task_id), scenarioPath);
end

function localCloseReference()
try
    if bdIsLoaded("XFLUID02_reference")
        close_system("XFLUID02_reference", 0);
    end
catch
end
try
    if bdIsLoaded("sm_pump_triplex")
        close_system("sm_pump_triplex", 0);
    end
catch
end
try
    project = currentProject;
    if ~isempty(project), close(project); end
catch cleanupException
    if ~strcmp(cleanupException.identifier, ...
            "MATLAB:project:api:NoProjectCurrentlyLoaded")
        rethrow(cleanupException);
    end
end
end

function same = localSamePath(leftPath, rightPath)
leftCanonical = string(java.io.File(char(leftPath)).getCanonicalPath());
rightCanonical = string(java.io.File(char(rightPath)).getCanonicalPath());
if ispc
    same = strcmpi(leftCanonical, rightCanonical);
else
    same = leftCanonical == rightCanonical;
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
