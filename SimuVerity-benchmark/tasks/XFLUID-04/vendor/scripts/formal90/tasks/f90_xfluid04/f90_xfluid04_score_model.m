function evidence=f90_xfluid04_score_model(modelPath,outDir)
% Extraction-only compatibility entrypoint. Offline scoring is Python.
evidence=f90_xfluid04_extract_evidence(modelPath,outDir);
end
