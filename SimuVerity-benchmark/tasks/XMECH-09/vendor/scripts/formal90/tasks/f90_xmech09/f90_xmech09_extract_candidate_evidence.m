function evidence = f90_xmech09_extract_candidate_evidence(modelPath, outDir)
arguments
    modelPath (1,1) string
    outDir (1,1) string
end
evidence = f90_xmech09_extract_reference_evidence( ...
    modelPath, outDir, "candidate");
end
