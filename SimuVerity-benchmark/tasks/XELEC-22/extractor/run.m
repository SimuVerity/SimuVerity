function evidence = run(candidatePath, officialScenarios, evidencePath)
%RUN Stable SimuVerity extraction boundary for XELEC-22.
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
implementationPath = fullfile(taskRoot, 'vendor/scripts/unified/d16/tasks/d022/d022_extract_candidate_evidence.m');
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

temporaryOutput = string(tempname);
mkdir(temporaryOutput);
outputCleanup = onCleanup(@() localRemoveTree(temporaryOutput)); %#ok<NASGU>
generationRunId = string(getenv("SIMUVERITY_GENERATION_RUN_ID"));
scoringRunId = string(getenv("SIMUVERITY_SCORING_RUN_ID"));
assert(strlength(generationRunId) > 0 && strlength(scoringRunId) > 0, ...
    "SimuVerity:Extractor:IdentityMissing", ...
    "D16 extraction requires generation and scoring run IDs.");
feval('d022_extract_candidate_evidence', "XELEC-22", generationRunId, ...
    scoringRunId, candidatePath, temporaryOutput);
produced = fullfile(temporaryOutput, "candidate_evidence.json");
assert(isfile(produced), "SimuVerity:Extractor:NoEvidence", ...
    "D16 extractor wrote no candidate_evidence.json.");
normalizedEvidence = fullfile(temporaryOutput, "evidence.json");
assert(~isfile(normalizedEvidence) && ~isfolder(normalizedEvidence), ...
    "SimuVerity:Extractor:AmbiguousEvidence", ...
    "D16 extractor produced both candidate_evidence.json and evidence.json.");
[moved, moveMessage] = movefile(produced, normalizedEvidence);
assert(moved && isfile(normalizedEvidence) && ~isfile(produced), ...
    "SimuVerity:Extractor:EvidenceNormalizeFailed", ...
    "Could not normalize D16 candidate evidence: %s", moveMessage);

simuverity_publish_evidence_closure(temporaryOutput, evidencePath);
evidence = jsondecode(fileread(evidencePath));
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
