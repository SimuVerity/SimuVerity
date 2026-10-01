function evidence=f90_xmed02_extract_candidate_evidence(modelPath,outDir)
% Candidate extraction entrypoint. Offline scoring remains Python-only.
evidence=f90_xmed02_extract_evidence(modelPath,outDir);
end
