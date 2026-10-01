function result = d011_extract_candidate_evidence( ...
    benchmarkTaskId, runLabel, attemptLabel, candidatePath, outputRoot)
%D011_EXTRACT_CANDIDATE_EVIDENCE Final causal-drive policy extractor.
add_shared();
assert(upper(string(benchmarkTaskId)) == "D011", ...
    "SimuVerity:UnifiedD16:D011Identity", "D011 extractor received another task.");
result = d16_write_d011_evidence( ...
    runLabel, attemptLabel, candidatePath, outputRoot);
end

function add_shared()
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
addpath(fullfile(root, "shared"), "-begin");
end
