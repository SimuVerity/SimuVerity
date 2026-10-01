function evidence=f90_xmed02_score(modelPath,outDir)
% Extraction-only compatibility entrypoint. Offline scoring is Python.
evidence=f90_xmed02_extract_evidence_core(modelPath,outDir);
end
