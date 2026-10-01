function evidence=f90_xtherm01_extract_candidate_evidence(specPath,modelPath,outDir,opts)
% F90-XTHERM-01 is the harder-thermal XTHERM02 source alias. Extraction only.
arguments
    specPath (1,1) string
    modelPath (1,1) string
    outDir (1,1) string
    opts.SaveWaveforms (1,1) logical = true
end
evidence=formal90_extract_xp9_evidence(specPath,modelPath,outDir, ...
    "f90_xtherm01_build_evidence","F90-XTHERM-01", ...
    SaveWaveforms=opts.SaveWaveforms);
end
