function evidence = f90_xbatt03_extract_candidate_evidence(modelPath, outDir)
% Candidate-only public-contract entry; reference evaluation stays separate.
arguments
    modelPath (1,1) string
    outDir (1,1) string
end
evidence = f90_xbatt03_extract_evidence(modelPath, outDir);
assert(~evidence.reference_subject, ...
    "SimuVerity:F90:XBATT03:CandidateIsReference", ...
    "Candidate evaluation must not use the pinned reference model.");
end
