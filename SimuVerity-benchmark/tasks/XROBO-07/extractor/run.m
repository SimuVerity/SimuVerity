function evidence = run(candidatePath, officialScenarios, evidencePath)
%RUN Stable SimuVerity extraction boundary for XROBO-07.
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
implementationPath = fullfile(taskRoot, 'vendor/scripts/formal90/tasks/f90_xrobo07/f90_xrobo07_extract_candidate_evidence.m');
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
localBindReferenceDependencies(candidatePath);

temporaryOutput = string(tempname);
outputCleanup = onCleanup(@() localRemoveTree(temporaryOutput)); %#ok<NASGU>
try
    evidence = feval('f90_xrobo07_extract_candidate_evidence', candidatePath, temporaryOutput);
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

function localBindReferenceDependencies(candidatePath)
subject = lower(strtrim(string(getenv("SIMUVERITY_EVALUATION_SUBJECT"))));
if strlength(subject) == 0, subject = "candidate"; end
assert(any(subject == ["candidate", "reference"]), ...
    "SimuVerity:Extractor:EvaluationSubject", "Invalid evaluation subject.");
if subject == "reference"
    assert(isfile(candidatePath), "SimuVerity:Extractor:ReferenceSubject", ...
        "Reference subject is missing: %s", candidatePath);
    addpath(fileparts(candidatePath), "-begin");
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
