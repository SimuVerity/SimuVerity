function result = d008_extract_candidate_evidence( ...
    benchmarkTaskId, runLabel, attemptLabel, candidatePath, outputRoot)
%D008_EXTRACT_CANDIDATE_EVIDENCE D008-only SimuVerity extractor.
add_shared();
assert(upper(string(benchmarkTaskId)) == "D008", ...
    "SimuVerity:UnifiedD16:D008Identity", "D008 extractor received another task.");
result = d16_write_task_evidence( ...
    "D008", runLabel, attemptLabel, candidatePath, outputRoot);
end
function add_shared()
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
addpath(fullfile(root, "shared"), "-begin");
end
