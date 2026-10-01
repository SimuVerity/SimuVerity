function evidence=f90_xauto02_candidate_simulation_core(modelPath,outDir)
% Extraction-only compatibility entrypoint. Offline scoring is Python.
evidence=f90_xauto02_extract_evidence(modelPath,outDir);
end
