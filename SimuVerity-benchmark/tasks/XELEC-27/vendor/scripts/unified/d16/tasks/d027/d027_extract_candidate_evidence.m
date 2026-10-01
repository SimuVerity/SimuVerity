function result = d027_extract_candidate_evidence( ...
    benchmarkTaskId, runLabel, attemptLabel, candidatePath, outputRoot)
%D027_EXTRACT_CANDIDATE_EVIDENCE Final NPC aggregate compatibility.
add_shared();
assert(upper(string(benchmarkTaskId)) == "D027", ...
    "SimuVerity:UnifiedD16:D027Identity", "D027 extractor received another task.");
result = d16_write_d027_evidence( ...
    runLabel, attemptLabel, candidatePath, outputRoot);
end

function add_shared()
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
addpath(fullfile(root, "shared"), "-begin");
end
