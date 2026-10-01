function result = d014_extract_candidate_evidence( ...
    benchmarkTaskId, runLabel, attemptLabel, candidatePath, outputRoot)
%D014_EXTRACT_CANDIDATE_EVIDENCE Fail-closed D014 evidence extractor.
add_shared();
assert(upper(string(benchmarkTaskId)) == "D014", ...
    "SimuVerity:UnifiedD16:D014Identity", "D014 extractor received another task.");
result = d16_write_d014_evidence( ...
    runLabel, attemptLabel, candidatePath, outputRoot);
end
function add_shared()
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
addpath(fullfile(root, "shared"), "-begin");
end
