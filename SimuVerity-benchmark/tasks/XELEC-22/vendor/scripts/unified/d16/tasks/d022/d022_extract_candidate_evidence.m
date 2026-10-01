function result = d022_extract_candidate_evidence( ...
    benchmarkTaskId, runLabel, attemptLabel, candidatePath, outputRoot)
%D022_EXTRACT_CANDIDATE_EVIDENCE D022-only SimuVerity extractor.
add_shared();
assert(upper(string(benchmarkTaskId)) == "D022", ...
    "SimuVerity:UnifiedD16:D022Identity", "D022 extractor received another task.");
result = d16_write_task_evidence( ...
    "D022", runLabel, attemptLabel, candidatePath, outputRoot);
end
function add_shared()
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
addpath(fullfile(root, "shared"), "-begin");
end
