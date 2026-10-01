function evidence = f90_xmed03_extract_candidate_evidence(modelPath, outDir)
%f90_xmed03_extract_candidate_evidence Source extraction-only compatibility entrypoint.
%
% Normalized evidence is written in MATLAB.  The central flow locks it
% before invoking f90_xmed03_offline_scorer.py.
arguments
    modelPath (1,1) string
    outDir (1,1) string
end

localRequireExtractor( ...
    "f90_xmed03_extract_evidence.m", ...
    "present");
evidence = f90_xmed03_extract_evidence(modelPath, outDir);
evidencePath = fullfile(outDir, "evidence.json");
assert(isfile(evidencePath), "SimuVerity:F90:XMED03:EvidenceMissing", ...
    "Evidence extractor did not write evidence.json.");
assert(isfield(evidence, "extraction_only") && ...
    logical(evidence.extraction_only), ...
    "SimuVerity:F90:XMED03:ExtractionContract", ...
    "Candidate evaluator must return extraction-only evidence.");
end

function localRequireExtractor(fileName, expectedFilePresence)
extractorPath = fullfile(fileparts(mfilename("fullpath")), fileName);
assert(isfile(extractorPath) && localFilePresence(extractorPath) == expectedFilePresence, ...
    "SimuVerity:F90:XMED03:ExtractorBinding", ...
    "The extraction engine is missing or binding-mismatched.");
end

function binding = localFilePresence(pathValue)
assert(isfile(pathValue), "SimuVerity:FileMissing", "Required file is missing: %s", pathValue);
binding = "present";
end

