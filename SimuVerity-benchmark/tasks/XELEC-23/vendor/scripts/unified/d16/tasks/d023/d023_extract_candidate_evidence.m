function result = d023_extract_candidate_evidence( ...
    benchmarkTaskId, runLabel, attemptLabel, candidatePath, outputRoot)
%D023_EXTRACT_CANDIDATE_EVIDENCE D023-only SimuVerity extractor.
add_shared();
assert(upper(string(benchmarkTaskId)) == "D023", ...
    "SimuVerity:UnifiedD16:D023Identity", "D023 extractor received another task.");
result = d16_write_task_evidence( ...
    "D023", runLabel, attemptLabel, candidatePath, outputRoot);
end
function add_shared()
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
addpath(fullfile(root, "shared"), "-begin");
end
