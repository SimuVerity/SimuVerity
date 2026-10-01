function result = d007_extract_candidate_evidence( ...
    benchmarkTaskId, runLabel, attemptLabel, candidatePath, outputRoot)
%D007_EXTRACT_CANDIDATE_EVIDENCE Final three-phase VI compatibility.
add_shared();
assert(upper(string(benchmarkTaskId)) == "D007", ...
    "SimuVerity:UnifiedD16:D007Identity", "D007 extractor received another task.");
result = d16_write_d007_evidence( ...
    runLabel, attemptLabel, candidatePath, outputRoot);
end

function add_shared()
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
addpath(fullfile(root, "shared"), "-begin");
end
