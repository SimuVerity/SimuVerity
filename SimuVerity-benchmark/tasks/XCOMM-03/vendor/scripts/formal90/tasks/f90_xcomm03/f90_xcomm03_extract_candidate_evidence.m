function evidence = f90_xcomm03_extract_candidate_evidence(modelPath, outDir)
%F90_XCOMM03_EXTRACT_CANDIDATE_EVIDENCE Source extraction-only compatibility entrypoint.
%
% Scoring is intentionally deferred until the central evidence lock exists.
arguments
    modelPath (1,1) string = ""
    outDir (1,1) string = ""
end

localRequireExtractor( ...
    "f90_xcomm03_extract_evidence.m", ...
    "present");
evidence = f90_xcomm03_extract_evidence(modelPath, outDir);
if strlength(outDir) > 0
    evidencePath = fullfile(outDir, "evidence.json");
    assert(isfile(evidencePath), "SimuVerity:F90:XCOMM03:EvidenceMissing", ...
        "Evidence extractor did not write evidence.json.");
end
assert(isfield(evidence, "extraction_only") && ...
    logical(evidence.extraction_only), ...
    "SimuVerity:F90:XCOMM03:ExtractionContract", ...
    "Candidate evaluator must return extraction-only evidence.");
end

function localRequireExtractor(fileName, expectedFilePresence)
extractorPath = fullfile(fileparts(mfilename("fullpath")), fileName);
assert(isfile(extractorPath) && localFilePresence(extractorPath) == expectedFilePresence, ...
    "SimuVerity:F90:XCOMM03:ExtractorBinding", ...
    "The extraction engine is missing or binding-mismatched.");
end

function binding = localFilePresence(pathValue)
assert(isfile(pathValue), "SimuVerity:FileMissing", "Required file is missing: %s", pathValue);
binding = "present";
end

