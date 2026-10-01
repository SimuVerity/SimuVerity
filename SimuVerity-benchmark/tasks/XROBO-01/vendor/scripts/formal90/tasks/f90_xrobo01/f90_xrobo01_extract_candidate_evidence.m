function evidence = f90_xrobo01_extract_candidate_evidence(modelPath, outDir)
%f90_xrobo01_extract_candidate_evidence Extraction-only GROUP_SCORING entrypoint.
evidence = f90_xrobo01_extract_evidence(modelPath, outDir);
end
