function receipt = f90_xtherm06_extract_candidate_evidence(modelPath, outDir)
% Candidate-only public-contract evaluator; reference evaluation is separate.
arguments
    modelPath (1,1) string
    outDir (1,1) string
end
receipt = f90_xtherm06_score_model(modelPath, outDir, "candidate");
end
