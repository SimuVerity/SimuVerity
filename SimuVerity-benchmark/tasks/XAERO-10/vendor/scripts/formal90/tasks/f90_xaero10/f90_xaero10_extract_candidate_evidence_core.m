function result = f90_xaero10_extract_candidate_evidence_core(modelPath, outputDir)
% Versioned XAERO-10 candidate evidence entrypoint.
result = f90_xaero10_extract_evidence(modelPath, outputDir, "candidate");
end
