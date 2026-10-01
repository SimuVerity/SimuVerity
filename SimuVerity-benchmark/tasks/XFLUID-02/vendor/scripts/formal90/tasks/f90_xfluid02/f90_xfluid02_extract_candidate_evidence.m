function evidence=f90_xfluid02_extract_candidate_evidence(modelPath,outDir)
% Extraction-only compatibility entrypoint. Offline scoring is Python.
evidence=f90_xfluid02_extract_evidence(modelPath,outDir);
end
