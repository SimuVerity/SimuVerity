function evidence = f90_xauto02_extract_candidate_evidence(modelPath, outDir)
%F90_XAUTO02_EXTRACT_CANDIDATE_EVIDENCE Preserve mature-CC evaluator preconditions.
% The authority extractor assumes its evaluator-owned output directory exists
% and resets the MATLAB path internally. Restore the caller's path afterward
% so the standardized dispatcher can finish evidence validation and locking.
assert(~isfile(outDir), "SimuVerity:F90:XAUTO02:OutputPathIsFile", ...
    "Evaluator output path is a file: %s", outDir);
if ~isfolder(outDir)
    mkdir(outDir);
end
callerPath = path;
pathCleanup = onCleanup(@() path(callerPath)); %#ok<NASGU>
evidence = f90_xauto02_candidate_simulation_core(modelPath, outDir);
end
