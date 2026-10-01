function result = d006_extract_candidate_evidence( ...
    benchmarkTaskId, runLabel, attemptLabel, candidatePath, outputRoot)
%D006_EXTRACT_CANDIDATE_EVIDENCE D006-only SimuVerity extractor.
add_shared();
assert(upper(string(benchmarkTaskId)) == "D006", ...
    "SimuVerity:UnifiedD16:D006Identity", "D006 extractor received another task.");
result = d16_write_task_evidence( ...
    "D006", runLabel, attemptLabel, candidatePath, outputRoot);
end
function add_shared()
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
addpath(fullfile(root, "shared"), "-begin");
end
