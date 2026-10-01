function result = f90_xaero10_extract_candidate_evidence(modelPath, outputDir)
%F90_XAERO10_EXTRACT_CANDIDATE_EVIDENCE SimuVerity release evidence metadata.
% Preserve the score-free candidate evidence and publish its explicit
% extraction-only boundary declaration.
result = f90_xaero10_extract_candidate_evidence_core(modelPath, outputDir);
assert(isfield(result, "contains_score_decisions") && ...
    ~logical(result.contains_score_decisions), ...
    "SimuVerity:Formal90:XAERO10:ScoreDecisionBoundary", ...
    "Candidate evidence must remain score-free.");
result.extraction_only = true;
result.source_integrated_scorer_called = false;
result.offline_scoring_started = false;

evidencePath = fullfile(string(outputDir), "evidence.json");
assert(isfile(evidencePath), "SimuVerity:Formal90:XAERO10:EvidenceMissing", ...
    "Candidate evidence JSON is missing.");
fid = fopen(evidencePath, "w", "n", "UTF-8");
assert(fid >= 0, "SimuVerity:Formal90:XAERO10:EvidenceWrite", ...
    "Cannot publish release evidence metadata.");
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fwrite(fid, jsonencode(result, PrettyPrint=true), "char");
fwrite(fid, newline, "char");
end
