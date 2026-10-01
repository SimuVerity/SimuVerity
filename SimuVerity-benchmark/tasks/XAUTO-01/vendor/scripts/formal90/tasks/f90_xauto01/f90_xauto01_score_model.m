function evidence=f90_xauto01_score_model(specPath,modelPath,outDir,opts)
% Extraction-only compatibility entrypoint; scoring is post-lock Python.
arguments
    specPath (1,1) string
    modelPath (1,1) string
    outDir (1,1) string
    opts.SaveWaveforms (1,1) logical = true
end
evidence=formal90_extract_xp9_evidence(specPath,modelPath,outDir, ...
    "f90_xauto01_build_evidence","F90-XAUTO-01", ...
    SaveWaveforms=opts.SaveWaveforms);
end
