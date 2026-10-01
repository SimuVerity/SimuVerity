function result = f90_xaero08_extract_candidate_evidence_core(modelPath, outputDir)
%F90_XAERO08_EXTRACT_CANDIDATE_EVIDENCE_CORE Candidate-only extraction core.
% Public nominal inputs are evaluator-owned; the evidence engine supplies
% them only so the candidate can update/compile before official scenarios.
result = f90_xaero08_extract_evidence(modelPath, outputDir, "candidate");
end
