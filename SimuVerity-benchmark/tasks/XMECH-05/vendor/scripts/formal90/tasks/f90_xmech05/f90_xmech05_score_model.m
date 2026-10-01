function evidence = f90_xmech05_score_model(modelPath, outDir)
%F90_XMECH05_SCORE_MODEL Source extraction-only compatibility entrypoint.
%
% No score, threshold, or shortcut-sanity decision is made in MATLAB.
arguments
    modelPath (1,1) string = ""
    outDir (1,1) string = ""
end

localRequireExtractor( ...
    "f90_xmech05_extract_evidence.m", ...
    "present");
evidence = f90_xmech05_extract_evidence(modelPath, outDir);
if strlength(outDir) > 0
    evidencePath = fullfile(outDir, "evidence.json");
    assert(isfile(evidencePath), "SimuVerity:F90:XMECH05:EvidenceMissing", ...
        "Evidence extractor did not write evidence.json.");
end
assert(isfield(evidence, "extraction_only") && ...
    logical(evidence.extraction_only), ...
    "SimuVerity:F90:XMECH05:ExtractionContract", ...
    "Candidate evaluator must return extraction-only evidence.");
end

function localRequireExtractor(fileName, expectedFilePresence)
extractorPath = fullfile(fileparts(mfilename("fullpath")), fileName);
assert(isfile(extractorPath) && localFilePresence(extractorPath) == expectedFilePresence, ...
    "SimuVerity:F90:XMECH05:ExtractorBinding", ...
    "The extraction engine is missing or binding-mismatched.");
end

function binding = localFilePresence(pathValue)
assert(isfile(pathValue), "SimuVerity:FileMissing", "Required file is missing: %s", pathValue);
binding = "present";
end

