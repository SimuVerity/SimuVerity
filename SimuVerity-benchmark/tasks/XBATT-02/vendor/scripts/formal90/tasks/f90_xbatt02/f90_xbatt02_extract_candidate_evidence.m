function evidence = f90_xbatt02_extract_candidate_evidence( ...
        modelPath, outputDir)
%F90_XBATT02_EXTRACT_CANDIDATE_EVIDENCE Own the evaluator output directory.
arguments
    modelPath (1,1) string
    outputDir (1,1) string
end
if ~isfolder(outputDir)
    mkdir(outputDir);
end
evidence = f90_xbatt02_candidate_simulation_core(modelPath, outputDir);
end
