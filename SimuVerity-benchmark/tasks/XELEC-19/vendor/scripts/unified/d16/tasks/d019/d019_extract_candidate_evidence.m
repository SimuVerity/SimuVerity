function result = d019_extract_candidate_evidence( ...
    benchmarkTaskId,runLabel,attemptLabel,candidatePath,outputRoot)
%D019_EXTRACT_CANDIDATE_EVIDENCE Current D019 extractor.
add_shared();
assert(upper(string(benchmarkTaskId)) == "D019", ...
    "SimuVerity:UnifiedD16:D019Identity","D019 extractor received another task.");
result = d16_write_d019_evidence( ...
    runLabel,attemptLabel,candidatePath,outputRoot);
end
function add_shared()
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
addpath(fullfile(root,"shared"),"-begin");
end
