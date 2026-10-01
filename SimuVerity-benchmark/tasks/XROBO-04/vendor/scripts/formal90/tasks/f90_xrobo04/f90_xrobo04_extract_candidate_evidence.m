function receipt = f90_xrobo04_extract_candidate_evidence(modelPath, outDir)
%f90_xrobo04_extract_candidate_evidence
% Candidate adapter for evaluator-owned conventional meshgrid expansion.
arguments
    modelPath (1,1) string
    outDir (1,1) string
end
receipt = f90_xrobo04_score_model(modelPath, outDir, "candidate");
end
